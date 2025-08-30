//
//  TextClassificationManager.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 29/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

import Foundation
import UIKit
import CoreML

// MARK: - PII Labels for DistilBERT

struct PIILabels {
    static let labelToId: [String: Int] = [
        "no_pii": 0,
        "name": 1,
        "email": 2,
        "phone_number": 3,
        "ssn": 4,
        "address": 5,
        "login": 6
    ]
    
    static let idToLabel: [Int: String] = [
        0: "no_pii",
        1: "name",
        2: "email",
        3: "phone_number",
        4: "ssn",
        5: "address",
        6: "login"
    ]
    
    static let allLabels = ["no_pii", "name", "email", "phone_number", "ssn", "address", "login"]
}

// MARK: - Sensitive Text Category Enum (Updated for DistilBERT)

enum SensitiveTextCategory: String, CaseIterable {
    case noPii = "no_pii"
    case name = "name"
    case email = "email"
    case phoneNumber = "phone_number"
    case ssn = "ssn"
    case address = "address"
    case login = "login"
    
    var displayName: String {
        switch self {
        case .noPii: return "No PII"
        case .name: return "Name"
        case .email: return "Email"
        case .phoneNumber: return "Phone Number"
        case .ssn: return "SSN"
        case .address: return "Address"
        case .login: return "Login"
        }
    }
    
    var color: UIColor {
        switch self {
        case .noPii: return .systemGray
        case .name: return .systemRed
        case .email: return .systemOrange
        case .phoneNumber: return .systemGreen
        case .ssn: return .systemPurple
        case .address: return .systemYellow
        case .login: return .systemPink
        }
    }
}

// MARK: - DistilBERT Model Info

struct DistilBERTModelInfo: Codable {
    let modelType: String = "DistilBERT"
    let classes: [String] = PIILabels.allLabels
    let maxLength: Int
    let version: String
    
    init(maxLength: Int = 128, version: String = "1.0") {
        self.maxLength = maxLength
        self.version = version
    }
}

// MARK: - Classification Result (Updated)

struct ClassificationResult {
    let predictedClass: String
    let confidence: Double
    let allProbabilities: [String: Double]
    let processingTime: TimeInterval
    let method: String // "regex", "distilbert", or "fallback"
    
    var isSensitive: Bool {
        return predictedClass != "no_pii"
    }
    
    var category: SensitiveTextCategory {
        return SensitiveTextCategory(rawValue: predictedClass) ?? .noPii
    }
}

// MARK: - Tokenizer for DistilBERT

class DistilBERTTokenizer {
    private var vocabulary: [String: Int] = [:]
    private var specialTokens: [String: Int] = [:]
    private let maxLength: Int
    private let padTokenId: Int
    private let clsTokenId: Int
    private let sepTokenId: Int
    private let unkTokenId: Int
    
    init(maxLength: Int = 128) {
        self.maxLength = maxLength
        self.padTokenId = 0 // [PAD]
        self.clsTokenId = 101 // [CLS]
        self.sepTokenId = 102 // [SEP]
        self.unkTokenId = 100 // [UNK]
        
        loadTokenizer()
    }
    
    private func loadTokenizer() {
        // Load tokenizer from your tokenizer.json file
        guard let path = Bundle.main.path(forResource: "tokenizer", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Could not load tokenizer.json, using fallback vocabulary")
            createFallbackVocabulary()
            return
        }
        
        // Parse vocabulary from tokenizer.json
        if let model = json["model"] as? [String: Any],
           let vocab = model["vocab"] as? [String: Int] {
            self.vocabulary = vocab
            print("✅ Loaded vocabulary with \(vocab.count) tokens")
        } else {
            print("⚠️ Could not parse vocabulary from tokenizer.json, using fallback")
            createFallbackVocabulary()
        }
        
        // Parse special tokens
        if let addedTokens = json["added_tokens"] as? [[String: Any]] {
            for token in addedTokens {
                if let content = token["content"] as? String,
                   let id = token["id"] as? Int {
                    specialTokens[content] = id
                }
            }
            print("✅ Loaded \(specialTokens.count) special tokens")
        }
    }
    
    private func createFallbackVocabulary() {
        // Create a minimal vocabulary for basic functionality
        vocabulary = [
            "[PAD]": 0,
            "[UNK]": 100,
            "[CLS]": 101,
            "[SEP]": 102,
            "email": 1000,
            "phone": 1001,
            "name": 1002,
            "address": 1003,
            "ssn": 1004,
            "login": 1005,
            "@": 1010,
            ".com": 1011,
            "the": 1020,
            "and": 1021,
            "is": 1022,
            "my": 1023,
            "call": 1024,
            "me": 1025
        ]
        print("✅ Created fallback vocabulary with \(vocabulary.count) tokens")
    }
    
    func tokenize(text: String) -> [Int] {
        let cleanText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Simple word-piece tokenization
        var tokens: [Int] = [clsTokenId] // Start with [CLS]
        
        // Combine whitespaces and punctuation character sets
        let separatorCharacterSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let words = cleanText.components(separatedBy: separatorCharacterSet)
            .filter { !$0.isEmpty }
        
        for word in words {
            if let tokenId = vocabulary[word] {
                tokens.append(tokenId)
            } else {
                // Handle unknown tokens
                tokens.append(unkTokenId)
            }
            
            // Stop if we're approaching max length
            if tokens.count >= maxLength - 1 {
                break
            }
        }
        
        // Add [SEP] token
        tokens.append(sepTokenId)
        
        // Pad to max length
        while tokens.count < maxLength {
            tokens.append(padTokenId)
        }
        
        // Truncate if necessary
        if tokens.count > maxLength {
            tokens = Array(tokens.prefix(maxLength - 1)) + [sepTokenId]
        }
        
        return tokens
    }
    
    func createAttentionMask(tokenIds: [Int]) -> [Int] {
        return tokenIds.map { $0 != padTokenId ? 1 : 0 }
    }
}

// MARK: - DistilBERT Model Wrapper

class DistilBERTClassifier {
    private var model: MLModel?
    private let tokenizer: DistilBERTTokenizer
    private let modelInfo: DistilBERTModelInfo

    var isModelLoaded: Bool {
        return model != nil
    }
    
    init() {
        self.tokenizer = DistilBERTTokenizer()
        self.modelInfo = DistilBERTModelInfo()
        loadModel()
    }
    
    private func loadModel() {
        // Try .mlpackage first, then .mlmodelc
        var modelURL = Bundle.main.url(forResource: "distilbert-pii-clf-v2", withExtension: "mlpackage")
        
        if modelURL == nil {
            modelURL = Bundle.main.url(forResource: "distilbert-pii-clf-v2", withExtension: "mlmodelc")
        }
        
        guard let url = modelURL else {
            print("❌ Could not find distilbert-pii-clf-v2 model in bundle")
            print("   Looking for: distilbert-pii-clf-v2.mlpackage or distilbert-pii-clf-v2.mlmodelc")
            return
        }
        
        do {
            self.model = try MLModel(contentsOf: url)
            print("✅ Successfully loaded DistilBERT model from: \(url.lastPathComponent)")
            inspectModel()
        } catch {
            print("❌ Failed to load DistilBERT model: \(error)")
        }
    }
    
    private func inspectModel() {
        guard let model = model else { return }
        
        print("📋 Model Description:")
        print("   Model: \(model.modelDescription.metadata[MLModelMetadataKey.description] ?? "No description")")
        
        print("\n📥 Input Features:")
        for input in model.modelDescription.inputDescriptionsByName {
            print("   - \(input.key): \(input.value)")
        }
        
        print("\n📤 Output Features:")
        for output in model.modelDescription.outputDescriptionsByName {
            print("   - \(output.key): \(output.value)")
        }
    }
    
    func predict(text: String) -> (String, [String: Double])? {
        guard let model = model else {
            print("❌ Model not loaded")
            return nil
        }
        
        // Tokenize input
        let tokenIds = tokenizer.tokenize(text: text)
        let attentionMask = tokenizer.createAttentionMask(tokenIds: tokenIds)
        
        print("🔍 Tokenized: \(tokenIds.prefix(10))... (length: \(tokenIds.count))")
        print("🔍 Attention mask: \(attentionMask.prefix(10))... (length: \(attentionMask.count))")
        
        do {
            // Try different input name variations
            let inputVariations = [
                ["input_ids", "attention_mask"],
                ["inputIds", "attentionMask"],
                ["input", "mask"]
            ]
            
            var inputFeatures: MLFeatureProvider?
            
            for variation in inputVariations {
                do {
                    inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
                        variation[0]: MLMultiArray(tokenIds),
                        variation[1]: MLMultiArray(attentionMask)
                    ])
                    print("✅ Using input names: \(variation)")
                    break
                } catch {
                    print("⚠️ Failed with input names \(variation): \(error)")
                    continue
                }
            }
            
            guard let features = inputFeatures else {
                print("❌ Could not create input features with any name variation")
                return nil
            }
            
            // Make prediction
            let prediction = try model.prediction(from: features)
            
            // Try different output name variations
            let outputVariations = ["probabilities", "output", "logits", "scores", "prediction"]
            
            for outputName in outputVariations {
                if let probabilities = prediction.featureValue(for: outputName)?.multiArrayValue {
                    print("✅ Using output name: \(outputName)")
                    return processProbabilities(probabilities)
                }
            }
            
            print("❌ Could not find output with any of these names: \(outputVariations)")
            print("Available outputs: \(prediction.featureNames)")
            
        } catch {
            print("❌ Prediction failed: \(error)")
        }
        
        return nil
    }
    
    private func processProbabilities(_ probabilities: MLMultiArray) -> (String, [String: Double]) {
        var probDict: [String: Double] = [:]
        var maxProb = 0.0
        var predictedLabel = "no_pii"
        
        print("🔍 Raw probabilities shape: \(probabilities.shape)")
        print("🔍 Raw probabilities count: \(probabilities.count)")
        
        for i in 0..<min(probabilities.count, PIILabels.allLabels.count) {
            let prob = probabilities[i].doubleValue
            let label = PIILabels.allLabels[i]
            probDict[label] = prob
            
            if prob > maxProb {
                maxProb = prob
                predictedLabel = label
            }
            
            print("   \(label): \(String(format: "%.4f", prob))")
        }
        
        return (predictedLabel, probDict)
    }
}

// MARK: - Text Classification Manager (Updated)

class TextClassificationManager {
    
    // Model components
    private var distilBERTClassifier: DistilBERTClassifier?
    
    // Fallback regex patterns for quick classification
    private let quickRegexPatterns: [String: [NSRegularExpression]] = {
        var patterns: [String: [NSRegularExpression]] = [:]
        
        // Email patterns
        patterns["email"] = [
            try! NSRegularExpression(pattern: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b", options: [])
        ]
        
        // Phone patterns
        patterns["phone_number"] = [
            try! NSRegularExpression(pattern: "\\+?1?[-\\s]?\\(?\\d{3}\\)?[-\\s]?\\d{3}[-\\s]?\\d{4}", options: []),
            try! NSRegularExpression(pattern: "\\b\\d{3}[-\\s]?\\d{3}[-\\s]?\\d{4}\\b", options: [])
        ]
        
        // SSN patterns
        patterns["ssn"] = [
            try! NSRegularExpression(pattern: "\\b\\d{3}[-\\s]?\\d{2}[-\\s]?\\d{4}\\b", options: [])
        ]
        
        // Name patterns (simple)
        patterns["name"] = [
            try! NSRegularExpression(pattern: "\\b(my name is|i am|i'm)\\s+[A-Z][a-z]+\\s+[A-Z][a-z]+\\b", options: .caseInsensitive)
        ]
        
        // Address patterns
        patterns["address"] = [
            try! NSRegularExpression(pattern: "\\b\\d+\\s+[A-Za-z]+\\s+(Street|St|Road|Rd|Avenue|Ave)\\b", options: .caseInsensitive)
        ]
        
        return patterns
    }()
    
    init() {
        loadModels()
    }
    
    // MARK: - Model Loading
    
    private func loadModels() {
        print("🔄 Loading DistilBERT PII classification model...")
        
        // Initialize DistilBERT classifier
        distilBERTClassifier = DistilBERTClassifier()
        
        print("📊 Fallback regex patterns loaded for: \(quickRegexPatterns.keys.sorted())")
    }
    
    // MARK: - Classification Methods
    
    func classify(text: String) -> ClassificationResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🔍 Classifying text: '\(cleanText)'")
        
        // First try DistilBERT model
        if let distilBERT = distilBERTClassifier,
           let (predictedClass, probabilities) = distilBERT.predict(text: cleanText) {
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            let confidence = probabilities[predictedClass] ?? 0.0
            
            print("✅ DistilBERT classification: \(predictedClass) (confidence: \(String(format: "%.3f", confidence))) in \(String(format: "%.1f", processingTime * 1000))ms")
            
            return ClassificationResult(
                predictedClass: predictedClass,
                confidence: confidence,
                allProbabilities: probabilities,
                processingTime: processingTime,
                method: "distilbert"
            )
        }
        
        // Fallback to regex patterns
        if let regexResult = classifyWithQuickRegex(text: cleanText) {
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ Regex fallback classification: \(regexResult) in \(String(format: "%.1f", processingTime * 1000))ms")
            
            return ClassificationResult(
                predictedClass: regexResult,
                confidence: 0.85,
                allProbabilities: [regexResult: 0.85, "no_pii": 0.15],
                processingTime: processingTime,
                method: "regex"
            )
        }
        
        // Final fallback
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        print("ℹ️ No classification match, defaulting to no_pii")
        
        return ClassificationResult(
            predictedClass: "no_pii",
            confidence: 0.8,
            allProbabilities: ["no_pii": 0.8],
            processingTime: processingTime,
            method: "fallback"
        )
    }
    
    private func classifyWithQuickRegex(text: String) -> String? {
        for (category, patterns) in quickRegexPatterns {
            for pattern in patterns {
                let range = NSRange(location: 0, length: text.utf16.count)
                if pattern.firstMatch(in: text, options: [], range: range) != nil {
                    return category
                }
            }
        }
        return nil
    }
    
    func classifyBatch(texts: [String]) -> [ClassificationResult] {
        return texts.map { classify(text: $0) }
    }
    
    // MARK: - Testing Methods
    
    func testModel() {
        print("\n🧪 Testing DistilBERT model integration...")
        print("=" * 50)
        
        let testCases = [
            "My email is john.doe@example.com",
            "Call me at 555-123-4567",
            "My name is John Smith",
            "SSN: 123-45-6789",
            "I live at 123 Main Street",
            "Username: admin, Password: secret123",
            "This is just normal text",
            "Contact info: jane@company.org",
            "Phone: (555) 987-6543",
            "My address is 456 Oak Avenue"
        ]
        
        for (index, testText) in testCases.enumerated() {
            print("\n📝 Test \(index + 1): '\(testText)'")
            print("-" * 40)
            
            let result = classify(text: testText)
            
            print("   → \(result.predictedClass) (confidence: \(String(format: "%.3f", result.confidence)))")
            print("   → Method: \(result.method), Time: \(String(format: "%.1f", result.processingTime * 1000))ms")
            print("   → Is Sensitive: \(result.isSensitive)")
            print("   → Category: \(result.category.displayName)")
            
            // Show top 3 predictions if we have probabilities
            if result.allProbabilities.count > 1 {
                let sortedProbs = result.allProbabilities.sorted { $0.value > $1.value }
                print("   → Top predictions:")
                for (label, prob) in sortedProbs.prefix(3) {
                    print("     - \(label): \(String(format: "%.3f", prob))")
                }
            }
        }
        
        print("\n" + "=" * 50)
        print("🏁 Testing complete!")
    }
    
    // MARK: - Utility Methods
    
    func getModelStatus() -> [String: Any] {
        let hasDistilBERT = distilBERTClassifier?.isModelLoaded ?? false
        
        return [
            "distilbert_loaded": hasDistilBERT,
            "distilbert_available": distilBERTClassifier != nil,
            "regex_patterns_loaded": !quickRegexPatterns.isEmpty,
            "regex_categories": Array(quickRegexPatterns.keys),
            "pii_labels": PIILabels.allLabels,
            "model_type": "DistilBERT",
            "fallback_available": true
        ]
    }
    
    func printModelStatus() {
        print("\n📊 Model Status Report")
        print("=" * 30)
        
        let status = getModelStatus()
        for (key, value) in status {
            print("   \(key): \(value)")
        }
        print("=" * 30)
    }
}

// MARK: - MLMultiArray Extension for convenience

extension MLMultiArray {
    convenience init(_ array: [Int]) {
        try! self.init(shape: [1, NSNumber(value: array.count)], dataType: .int32)
        for (index, value) in array.enumerated() {
            self[[0, NSNumber(value: index)]] = NSNumber(value: value)
        }
    }
    
    convenience init(_ array: [Double]) {
        try! self.init(shape: [1, NSNumber(value: array.count)], dataType: .double)
        for (index, value) in array.enumerated() {
            self[[0, NSNumber(value: index)]] = NSNumber(value: value)
        }
    }
}

// MARK: - String Extension for repeat

extension String {
    static func * (string: String, times: Int) -> String {
        return String(repeating: string, count: times)
    }
}

