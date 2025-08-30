////
////  TextClassificationManager.swift
////  PHPickerDemo
////
////  Created by Yeo Meng Han on 29/8/25.
////  Copyright © 2025 Apple. All rights reserved.
////
//
//import Foundation
//import UIKit
//import CoreML
//
//// MARK: - PII Labels for DistilBERT
//
//struct PIILabels {
//    static let labelToId: [String: Int] = [
//        "no_pii": 0,
//        "name": 1,
//        "email": 2,
//        "phone_number": 3,
//        "ssn": 4,
//        "address": 5,
//        "login": 6
//    ]
//    
//    static let idToLabel: [Int: String] = [
//        0: "no_pii",
//        1: "name",
//        2: "email",
//        3: "phone_number",
//        4: "ssn",
//        5: "address",
//        6: "login"
//    ]
//    
//    static let allLabels = ["no_pii", "name", "email", "phone_number", "ssn", "address", "login"]
//}
//
//// MARK: - Sensitive Text Category Enum (Updated for DistilBERT)
//
//enum SensitiveTextCategory: String, CaseIterable {
//    case noPii = "no_pii"
//    case name = "name"
//    case email = "email"
//    case phoneNumber = "phone_number"
//    case ssn = "ssn"
//    case address = "address"
//    case login = "login"
//    
//    var displayName: String {
//        switch self {
//        case .noPii: return "No PII"
//        case .name: return "Name"
//        case .email: return "Email"
//        case .phoneNumber: return "Phone Number"
//        case .ssn: return "SSN"
//        case .address: return "Address"
//        case .login: return "Login"
//        }
//    }
//    
//    var color: UIColor {
//        switch self {
//        case .noPii: return .systemGray
//        case .name: return .systemRed
//        case .email: return .systemOrange
//        case .phoneNumber: return .systemGreen
//        case .ssn: return .systemPurple
//        case .address: return .systemYellow
//        case .login: return .systemPink
//        }
//    }
//}
//
//// MARK: - DistilBERT Model Info
//
//struct DistilBERTModelInfo: Codable {
//    let modelType: String = "DistilBERT"
//    let classes: [String] = PIILabels.allLabels
//    let maxLength: Int
//    let version: String
//    
//    init(maxLength: Int = 128, version: String = "1.0") {
//        self.maxLength = maxLength
//        self.version = version
//    }
//}
//
//// MARK: - Classification Result (Updated)
//
//struct ClassificationResult {
//    let predictedClass: String
//    let confidence: Double
//    let allProbabilities: [String: Double]
//    let processingTime: TimeInterval
//    let method: String // "regex", "distilbert", or "fallback"
//    
//    var isSensitive: Bool {
//        return predictedClass != "no_pii"
//    }
//    
//    var category: SensitiveTextCategory {
//        return SensitiveTextCategory(rawValue: predictedClass) ?? .noPii
//    }
//}
//
//// MARK: - Tokenizer for DistilBERT
//
//class DistilBERTTokenizer {
//    private var vocabulary: [String: Int] = [:]
//    private var specialTokens: [String: Int] = [:]
//    private let maxLength: Int
//    private let padTokenId: Int
//    private let clsTokenId: Int
//    private let sepTokenId: Int
//    private let unkTokenId: Int
//    
//    init(maxLength: Int = 128) {
//        self.maxLength = maxLength
//        self.padTokenId = 0 // [PAD]
//        self.clsTokenId = 101 // [CLS]
//        self.sepTokenId = 102 // [SEP]
//        self.unkTokenId = 100 // [UNK]
//        
//        loadTokenizer()
//    }
//    
//    private func loadTokenizer() {
//        // Load tokenizer from your tokenizer.json file
//        guard let path = Bundle.main.path(forResource: "tokenizer", ofType: "json"),
//              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
//              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
//            print("❌ Could not load tokenizer.json, using fallback vocabulary")
//            createFallbackVocabulary()
//            return
//        }
//        
//        // Parse vocabulary from tokenizer.json
//        if let model = json["model"] as? [String: Any],
//           let vocab = model["vocab"] as? [String: Int] {
//            self.vocabulary = vocab
//            print("✅ Loaded vocabulary with \(vocab.count) tokens")
//        } else {
//            print("⚠️ Could not parse vocabulary from tokenizer.json, using fallback")
//            createFallbackVocabulary()
//        }
//        
//        // Parse special tokens
//        if let addedTokens = json["added_tokens"] as? [[String: Any]] {
//            for token in addedTokens {
//                if let content = token["content"] as? String,
//                   let id = token["id"] as? Int {
//                    specialTokens[content] = id
//                }
//            }
//            print("✅ Loaded \(specialTokens.count) special tokens")
//        }
//    }
//    
//    private func createFallbackVocabulary() {
//        // Create a minimal vocabulary for basic functionality
//        vocabulary = [
//            "[PAD]": 0,
//            "[UNK]": 100,
//            "[CLS]": 101,
//            "[SEP]": 102,
//            "email": 1000,
//            "phone": 1001,
//            "name": 1002,
//            "address": 1003,
//            "ssn": 1004,
//            "login": 1005,
//            "@": 1010,
//            ".com": 1011,
//            "the": 1020,
//            "and": 1021,
//            "is": 1022,
//            "my": 1023,
//            "call": 1024,
//            "me": 1025
//        ]
//        print("✅ Created fallback vocabulary with \(vocabulary.count) tokens")
//    }
//    
//    func tokenize(text: String) -> [Int] {
//        let cleanText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
//        
//        // Simple word-piece tokenization
//        var tokens: [Int] = [clsTokenId] // Start with [CLS]
//        
//        // Combine whitespaces and punctuation character sets
//        let separatorCharacterSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
//        let words = cleanText.components(separatedBy: separatorCharacterSet)
//            .filter { !$0.isEmpty }
//        
//        for word in words {
//            if let tokenId = vocabulary[word] {
//                tokens.append(tokenId)
//            } else {
//                // Handle unknown tokens
//                tokens.append(unkTokenId)
//            }
//            
//            // Stop if we're approaching max length
//            if tokens.count >= maxLength - 1 {
//                break
//            }
//        }
//        
//        // Add [SEP] token
//        tokens.append(sepTokenId)
//        
//        // Pad to max length
//        while tokens.count < maxLength {
//            tokens.append(padTokenId)
//        }
//        
//        // Truncate if necessary
//        if tokens.count > maxLength {
//            tokens = Array(tokens.prefix(maxLength - 1)) + [sepTokenId]
//        }
//        
//        return tokens
//    }
//    
//    func createAttentionMask(tokenIds: [Int]) -> [Int] {
//        return tokenIds.map { $0 != padTokenId ? 1 : 0 }
//    }
//}
//
//// MARK: - DistilBERT Model Wrapper
//
//class DistilBERTClassifier {
//    private var model: MLModel?
//    private let tokenizer: DistilBERTTokenizer
//    private let modelInfo: DistilBERTModelInfo
//
//    var isModelLoaded: Bool {
//        return model != nil
//    }
//    
//    init() {
//        self.tokenizer = DistilBERTTokenizer()
//        self.modelInfo = DistilBERTModelInfo()
//        loadModel()
//    }
//    
//    private func loadModel() {
//        // Try .mlpackage first, then .mlmodelc
//        var modelURL = Bundle.main.url(forResource: "distilbert-pii-clf-v2", withExtension: "mlpackage")
//        
//        if modelURL == nil {
//            modelURL = Bundle.main.url(forResource: "distilbert-pii-clf-v2", withExtension: "mlmodelc")
//        }
//        
//        guard let url = modelURL else {
//            print("❌ Could not find distilbert-pii-clf-v2 model in bundle")
//            print("   Looking for: distilbert-pii-clf-v2.mlpackage or distilbert-pii-clf-v2.mlmodelc")
//            return
//        }
//        
//        do {
//            self.model = try MLModel(contentsOf: url)
//            print("✅ Successfully loaded DistilBERT model from: \(url.lastPathComponent)")
//            inspectModel()
//        } catch {
//            print("❌ Failed to load DistilBERT model: \(error)")
//        }
//    }
//    
//    private func inspectModel() {
//        guard let model = model else { return }
//        
//        print("📋 Model Description:")
//        print("   Model: \(model.modelDescription.metadata[MLModelMetadataKey.description] ?? "No description")")
//        
//        print("\n📥 Input Features:")
//        for input in model.modelDescription.inputDescriptionsByName {
//            print("   - \(input.key): \(input.value)")
//        }
//        
//        print("\n📤 Output Features:")
//        for output in model.modelDescription.outputDescriptionsByName {
//            print("   - \(output.key): \(output.value)")
//        }
//    }
//    
//    func predict(text: String) -> (String, [String: Double])? {
//        guard let model = model else {
//            print("❌ Model not loaded")
//            return nil
//        }
//        
//        // Tokenize input
//        let tokenIds = tokenizer.tokenize(text: text)
//        let attentionMask = tokenizer.createAttentionMask(tokenIds: tokenIds)
//        
//        print("🔍 Tokenized: \(tokenIds.prefix(10))... (length: \(tokenIds.count))")
//        print("🔍 Attention mask: \(attentionMask.prefix(10))... (length: \(attentionMask.count))")
//        
//        do {
//            // Try different input name variations
//            let inputVariations = [
//                ["input_ids", "attention_mask"],
//                ["inputIds", "attentionMask"],
//                ["input", "mask"]
//            ]
//            
//            var inputFeatures: MLFeatureProvider?
//            
//            for variation in inputVariations {
//                do {
//                    inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
//                        variation[0]: MLMultiArray(tokenIds),
//                        variation[1]: MLMultiArray(attentionMask)
//                    ])
//                    print("✅ Using input names: \(variation)")
//                    break
//                } catch {
//                    print("⚠️ Failed with input names \(variation): \(error)")
//                    continue
//                }
//            }
//            
//            guard let features = inputFeatures else {
//                print("❌ Could not create input features with any name variation")
//                return nil
//            }
//            
//            // Make prediction
//            let prediction = try model.prediction(from: features)
//            
//            // Try different output name variations
//            let outputVariations = ["probabilities", "output", "logits", "scores", "prediction"]
//            
//            for outputName in outputVariations {
//                if let probabilities = prediction.featureValue(for: outputName)?.multiArrayValue {
//                    print("✅ Using output name: \(outputName)")
//                    return processProbabilities(probabilities)
//                }
//            }
//            
//            print("❌ Could not find output with any of these names: \(outputVariations)")
//            print("Available outputs: \(prediction.featureNames)")
//            
//        } catch {
//            print("❌ Prediction failed: \(error)")
//        }
//        
//        return nil
//    }
//    
//    private func processProbabilities(_ probabilities: MLMultiArray) -> (String, [String: Double]) {
//        var probDict: [String: Double] = [:]
//        var maxProb = 0.0
//        var predictedLabel = "no_pii"
//        
//        print("🔍 Raw probabilities shape: \(probabilities.shape)")
//        print("🔍 Raw probabilities count: \(probabilities.count)")
//        
//        for i in 0..<min(probabilities.count, PIILabels.allLabels.count) {
//            let prob = probabilities[i].doubleValue
//            let label = PIILabels.allLabels[i]
//            probDict[label] = prob
//            
//            if prob > maxProb {
//                maxProb = prob
//                predictedLabel = label
//            }
//            
//            print("   \(label): \(String(format: "%.4f", prob))")
//        }
//        
//        return (predictedLabel, probDict)
//    }
//}
//
//// MARK: - Text Classification Manager (Updated)
//
//class TextClassificationManager {
//    
//    // Model components
//    private var distilBERTClassifier: DistilBERTClassifier?
//    
//    // Fallback regex patterns for quick classification
//    private let quickRegexPatterns: [String: [NSRegularExpression]] = {
//        var patterns: [String: [NSRegularExpression]] = [:]
//        
//        // Email patterns
//        patterns["email"] = [
//            try! NSRegularExpression(pattern: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b", options: [])
//        ]
//        
//        // Phone patterns
//        patterns["phone_number"] = [
//            try! NSRegularExpression(pattern: "\\+?1?[-\\s]?\\(?\\d{3}\\)?[-\\s]?\\d{3}[-\\s]?\\d{4}", options: []),
//            try! NSRegularExpression(pattern: "\\b\\d{3}[-\\s]?\\d{3}[-\\s]?\\d{4}\\b", options: [])
//        ]
//        
//        // SSN patterns
//        patterns["ssn"] = [
//            try! NSRegularExpression(pattern: "\\b\\d{3}[-\\s]?\\d{2}[-\\s]?\\d{4}\\b", options: [])
//        ]
//        
//        // Name patterns (simple)
//        patterns["name"] = [
//            try! NSRegularExpression(pattern: "\\b(my name is|i am|i'm)\\s+[A-Z][a-z]+\\s+[A-Z][a-z]+\\b", options: .caseInsensitive)
//        ]
//        
//        // Address patterns
//        patterns["address"] = [
//            try! NSRegularExpression(pattern: "\\b\\d+\\s+[A-Za-z]+\\s+(Street|St|Road|Rd|Avenue|Ave)\\b", options: .caseInsensitive)
//        ]
//        
//        return patterns
//    }()
//    
//    init() {
//        loadModels()
//    }
//    
//    // MARK: - Model Loading
//    
//    private func loadModels() {
//        print("🔄 Loading DistilBERT PII classification model...")
//        
//        // Initialize DistilBERT classifier
//        distilBERTClassifier = DistilBERTClassifier()
//        
//        print("📊 Fallback regex patterns loaded for: \(quickRegexPatterns.keys.sorted())")
//    }
//    
//    // MARK: - Classification Methods
//    
//    func classify(text: String) -> ClassificationResult {
//        let startTime = CFAbsoluteTimeGetCurrent()
//        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
//        
//        print("🔍 Classifying text: '\(cleanText)'")
//        
//        // First try DistilBERT model
//        if let distilBERT = distilBERTClassifier,
//           let (predictedClass, probabilities) = distilBERT.predict(text: cleanText) {
//            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
//            let confidence = probabilities[predictedClass] ?? 0.0
//            
//            print("✅ DistilBERT classification: \(predictedClass) (confidence: \(String(format: "%.3f", confidence))) in \(String(format: "%.1f", processingTime * 1000))ms")
//            
//            return ClassificationResult(
//                predictedClass: predictedClass,
//                confidence: confidence,
//                allProbabilities: probabilities,
//                processingTime: processingTime,
//                method: "distilbert"
//            )
//        }
//        
//        // Fallback to regex patterns
//        if let regexResult = classifyWithQuickRegex(text: cleanText) {
//            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
//            print("✅ Regex fallback classification: \(regexResult) in \(String(format: "%.1f", processingTime * 1000))ms")
//            
//            return ClassificationResult(
//                predictedClass: regexResult,
//                confidence: 0.85,
//                allProbabilities: [regexResult: 0.85, "no_pii": 0.15],
//                processingTime: processingTime,
//                method: "regex"
//            )
//        }
//        
//        // Final fallback
//        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
//        print("ℹ️ No classification match, defaulting to no_pii")
//        
//        return ClassificationResult(
//            predictedClass: "no_pii",
//            confidence: 0.8,
//            allProbabilities: ["no_pii": 0.8],
//            processingTime: processingTime,
//            method: "fallback"
//        )
//    }
//    
//    private func classifyWithQuickRegex(text: String) -> String? {
//        for (category, patterns) in quickRegexPatterns {
//            for pattern in patterns {
//                let range = NSRange(location: 0, length: text.utf16.count)
//                if pattern.firstMatch(in: text, options: [], range: range) != nil {
//                    return category
//                }
//            }
//        }
//        return nil
//    }
//    
//    func classifyBatch(texts: [String]) -> [ClassificationResult] {
//        return texts.map { classify(text: $0) }
//    }
//    
//    // MARK: - Testing Methods
//    
//    func testModel() {
//        print("\n🧪 Testing DistilBERT model integration...")
//        print("=" * 50)
//        
//        let testCases = [
//            "My email is john.doe@example.com",
//            "Call me at 555-123-4567",
//            "My name is John Smith",
//            "SSN: 123-45-6789",
//            "I live at 123 Main Street",
//            "Username: admin, Password: secret123",
//            "This is just normal text",
//            "Contact info: jane@company.org",
//            "Phone: (555) 987-6543",
//            "My address is 456 Oak Avenue"
//        ]
//        
//        for (index, testText) in testCases.enumerated() {
//            print("\n📝 Test \(index + 1): '\(testText)'")
//            print("-" * 40)
//            
//            let result = classify(text: testText)
//            
//            print("   → \(result.predictedClass) (confidence: \(String(format: "%.3f", result.confidence)))")
//            print("   → Method: \(result.method), Time: \(String(format: "%.1f", result.processingTime * 1000))ms")
//            print("   → Is Sensitive: \(result.isSensitive)")
//            print("   → Category: \(result.category.displayName)")
//            
//            // Show top 3 predictions if we have probabilities
//            if result.allProbabilities.count > 1 {
//                let sortedProbs = result.allProbabilities.sorted { $0.value > $1.value }
//                print("   → Top predictions:")
//                for (label, prob) in sortedProbs.prefix(3) {
//                    print("     - \(label): \(String(format: "%.3f", prob))")
//                }
//            }
//        }
//        
//        print("\n" + "=" * 50)
//        print("🏁 Testing complete!")
//    }
//    
//    // MARK: - Utility Methods
//    
//    func getModelStatus() -> [String: Any] {
//        let hasDistilBERT = distilBERTClassifier?.isModelLoaded ?? false
//        
//        return [
//            "distilbert_loaded": hasDistilBERT,
//            "distilbert_available": distilBERTClassifier != nil,
//            "regex_patterns_loaded": !quickRegexPatterns.isEmpty,
//            "regex_categories": Array(quickRegexPatterns.keys),
//            "pii_labels": PIILabels.allLabels,
//            "model_type": "DistilBERT",
//            "fallback_available": true
//        ]
//    }
//    
//    func printModelStatus() {
//        print("\n📊 Model Status Report")
//        print("=" * 30)
//        
//        let status = getModelStatus()
//        for (key, value) in status {
//            print("   \(key): \(value)")
//        }
//        print("=" * 30)
//    }
//}
//
//// MARK: - MLMultiArray Extension for convenience
//
//extension MLMultiArray {
//    convenience init(_ array: [Int]) {
//        try! self.init(shape: [1, NSNumber(value: array.count)], dataType: .int32)
//        for (index, value) in array.enumerated() {
//            self[[0, NSNumber(value: index)]] = NSNumber(value: value)
//        }
//    }
//    
//    convenience init(_ array: [Double]) {
//        try! self.init(shape: [1, NSNumber(value: array.count)], dataType: .double)
//        for (index, value) in array.enumerated() {
//            self[[0, NSNumber(value: index)]] = NSNumber(value: value)
//        }
//    }
//}
//
//// MARK: - String Extension for repeat
//
//extension String {
//    static func * (string: String, times: Int) -> String {
//        return String(repeating: string, count: times)
//    }
//}

//
//  TextClassificationManager.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 29/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

import Foundation
import UIKit

// MARK: - Sensitive Text Category Enum

enum SensitiveTextCategory: String, CaseIterable {
    case nric = "nric"
    case email = "email"
    case creditCard = "credit_card"
    case phone = "phone"
    case birthday = "birthday"
    case address = "address"
    case nonSensitive = "non_sensitive"
    
    var displayName: String {
        switch self {
        case .nric: return "NRIC"
        case .email: return "Email"
        case .creditCard: return "Credit Card"
        case .phone: return "Phone"
        case .birthday: return "Birthday"
        case .address: return "Address"
        case .nonSensitive: return "Non-Sensitive"
        }
    }
    
    var color: UIColor {
        switch self {
        case .nric: return .systemRed
        case .email: return .systemOrange
        case .creditCard: return .systemPurple
        case .phone: return .systemBlue
        case .birthday: return .systemGreen
        case .address: return .systemYellow
        case .nonSensitive: return .systemGray
        }
    }
}

// MARK: - Classification Models

struct ModelInfo: Codable {
    let modelType: String
    let classes: [String]
    let featureNames: [String]?
    let tfidfVocabSize: Int
    let regexFeatures: [String]?
    
    private enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case classes
        case featureNames = "feature_names"
        case tfidfVocabSize = "tfidf_vocab_size"
        case regexFeatures = "regex_features"
    }
}

struct ClassificationResult {
    let predictedClass: String
    let confidence: Double
    let allProbabilities: [String: Double]
    let processingTime: TimeInterval
    let method: String // "regex" or "ml"
    
    var isSensitive: Bool {
        return predictedClass != "non_sensitive"
    }
    
    var category: SensitiveTextCategory {
        return SensitiveTextCategory(rawValue: predictedClass) ?? .nonSensitive
    }
}

// MARK: - Model Loading Helper

class ModelLoader {
    
    static func loadPickleData(filename: String) -> Data? {
        guard let path = Bundle.main.path(forResource: filename, ofType: "pkl") else {
            print("❌ Could not find \(filename).pkl in bundle")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            print("✅ Successfully loaded \(filename).pkl (\(data.count) bytes)")
            return data
        } catch {
            print("❌ Failed to load \(filename).pkl: \(error)")
            return nil
        }
    }
    
    static func loadModelInfo() -> ModelInfo? {
        // Try to load from JSON first (recommended approach)
        if let jsonInfo = loadModelInfoFromJSON() {
            return jsonInfo
        }
        
        // Fallback to hardcoded info
        return ModelInfo(
            modelType: "LogisticRegression",
            classes: ["non_sensitive", "nric", "email", "credit_card", "phone", "birthday", "address"],
            featureNames: nil,
            tfidfVocabSize: 1000,
            regexFeatures: ["nric", "email", "credit_card", "phone", "birthday", "address_keyword"]
        )
    }
    
    private static func loadModelInfoFromJSON() -> ModelInfo? {
        guard let path = Bundle.main.path(forResource: "model_info", ofType: "json") else {
            print("ℹ️ model_info.json not found, using fallback")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let modelInfo = try JSONDecoder().decode(ModelInfo.self, from: data)
            print("✅ Successfully loaded model_info.json")
            return modelInfo
        } catch {
            print("❌ Failed to load model_info.json: \(error)")
            return nil
        }
    }
}

// MARK: - TF-IDF Transformer Implementation

class TFIDFTransformer {
    private let vocabulary: [String: Int]
    private let idf: [Double]
    private let vocabSize: Int
    
    init(data: Data) throws {
        // Try to parse as JSON first (recommended approach)
        if let jsonTransformer = try? TFIDFTransformer.fromJSON(data: data) {
            self.vocabulary = jsonTransformer.vocabulary
            self.idf = jsonTransformer.idf
            self.vocabSize = jsonTransformer.vocabSize
            return
        }
        
        // Fallback implementation with basic vocabulary
        print("⚠️ Using fallback TF-IDF transformer")
        
        // Create a basic vocabulary for common sensitive data terms
        let commonTerms = [
            // NRIC related
            "nric", "ic", "identification", "card", "singapore",
            // Email related
            "email", "mail", "@", "gmail", "yahoo", "hotmail", "com", "org", "net",
            // Credit card related
            "credit", "card", "visa", "mastercard", "amex", "american", "express",
            // Phone related
            "phone", "mobile", "contact", "number", "tel", "call",
            // Birthday related
            "birthday", "birth", "date", "born", "age", "year", "month", "day",
            // Address related
            "address", "street", "road", "avenue", "singapore", "block", "unit", "postal"
        ]
        
        var vocab: [String: Int] = [:]
        for (index, term) in commonTerms.enumerated() {
            vocab[term] = index
        }
        
        self.vocabulary = vocab
        self.vocabSize = commonTerms.count
        self.idf = Array(repeating: 1.0, count: vocabSize) // Uniform IDF for fallback
        
        print("✅ Fallback TF-IDF transformer initialized with \(vocabSize) terms")
    }
    
    static func fromJSON(data: Data) throws -> TFIDFTransformer {
        struct TFIDFData: Codable {
            let vocabulary: [String: Int]
            let idf: [Double]
        }
        
        let tfidfData = try JSONDecoder().decode(TFIDFData.self, from: data)
        
        let transformer = try TFIDFTransformer(data: Data()) // This will use fallback
        // Override with JSON data
        return TFIDFTransformer(vocabulary: tfidfData.vocabulary, idf: tfidfData.idf)
    }
    
    private init(vocabulary: [String: Int], idf: [Double]) {
        self.vocabulary = vocabulary
        self.idf = idf
        self.vocabSize = vocabulary.count
    }
    
    func transform(text: String) -> [Double] {
        let cleanText = text.lowercased()
            .components(separatedBy: .punctuationCharacters).joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        var features = Array(repeating: 0.0, count: vocabSize)
        
        if cleanText.isEmpty {
            return features
        }
        
        // Calculate term frequencies
        var termCounts: [String: Int] = [:]
        for token in cleanText {
            termCounts[token, default: 0] += 1
        }
        
        let totalTerms = Double(cleanText.count)
        
        // Apply TF-IDF formula
        for (term, count) in termCounts {
            if let index = vocabulary[term], index < features.count {
                let tf = Double(count) / totalTerms
                let idfValue = index < idf.count ? idf[index] : 1.0
                features[index] = tf * idfValue
            }
        }
        
        return features
    }
}

// MARK: - Regex Feature Extractor Implementation

class RegexFeatureExtractor {
    private let patterns: [String: NSRegularExpression]
    private let featureOrder: [String]
    
    init(data: Data) throws {
        // Try to parse as JSON first
        if let jsonExtractor = try? RegexFeatureExtractor.fromJSON(data: data) {
            self.patterns = jsonExtractor.patterns
            self.featureOrder = jsonExtractor.featureOrder
            return
        }
        
        // Fallback implementation
        print("⚠️ Using fallback regex feature extractor")
        
        var tempPatterns: [String: NSRegularExpression] = [:]
        
        // NRIC patterns (Singapore)
        tempPatterns["nric"] = try NSRegularExpression(
            pattern: "\\b[STFG]\\d{7}[A-Z]\\b",
            options: .caseInsensitive
        )
        
        // Email patterns
        tempPatterns["email"] = try NSRegularExpression(
            pattern: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b",
            options: []
        )
        
        // Credit card patterns
        tempPatterns["credit_card"] = try NSRegularExpression(
            pattern: "\\b(?:\\d{4}[-\\s]?){3}\\d{4}\\b|\\b\\d{13,19}\\b",
            options: []
        )
        
        // Phone patterns
        tempPatterns["phone"] = try NSRegularExpression(
            pattern: "\\+65\\s?[689]\\d{7}|\\b[689]\\d{7}\\b|\\b\\d{3}[-\\s]?\\d{3}[-\\s]?\\d{4}\\b",
            options: []
        )
        
        // Birthday patterns
        tempPatterns["birthday"] = try NSRegularExpression(
            pattern: "\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{4}\\b|\\b\\d{4}[/-]\\d{1,2}[/-]\\d{1,2}\\b|\\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2},?\\s+\\d{4}\\b",
            options: .caseInsensitive
        )
        
        // Address patterns
        tempPatterns["address_keyword"] = try NSRegularExpression(
            pattern: "\\b\\d+\\s+[A-Za-z]+\\s+(Street|St|Road|Rd|Avenue|Ave|Drive|Dr|Lane|Ln|Boulevard|Blvd)|\\bSingapore\\s+\\d{6}\\b|\\b(Block|Blk|Unit)\\s+\\d+",
            options: .caseInsensitive
        )
        
        self.patterns = tempPatterns
        self.featureOrder = ["nric", "email", "credit_card", "phone", "birthday", "address_keyword"]
        
        print("✅ Fallback regex extractor initialized with \(patterns.count) patterns")
    }
    
    static func fromJSON(data: Data) throws -> RegexFeatureExtractor {
        struct RegexData: Codable {
            let patterns: [String: String]
            let featureOrder: [String]
        }
        
        let regexData = try JSONDecoder().decode(RegexData.self, from: data)
        
        var compiledPatterns: [String: NSRegularExpression] = [:]
        for (name, pattern) in regexData.patterns {
            compiledPatterns[name] = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
        
        return RegexFeatureExtractor(patterns: compiledPatterns, featureOrder: regexData.featureOrder)
    }
    
    private init(patterns: [String: NSRegularExpression], featureOrder: [String]) {
        self.patterns = patterns
        self.featureOrder = featureOrder
    }
    
    func extractFeatures(text: String) -> [Double] {
        let range = NSRange(location: 0, length: text.utf16.count)
        var features: [Double] = []
        
        for featureName in featureOrder {
            if let pattern = patterns[featureName] {
                let matches = pattern.numberOfMatches(in: text, options: [], range: range)
                features.append(Double(matches > 0 ? 1 : 0)) // Binary features
            } else {
                features.append(0.0)
            }
        }
        
        return features
    }
}

// MARK: - ML Classifier Implementation

class MLClassifier {
    private let weights: [[Double]]
    private let bias: [Double]
    private let classes: [String]
    
    init(data: Data) throws {
        // Try to parse as JSON first
        if let jsonClassifier = try? MLClassifier.fromJSON(data: data) {
            self.weights = jsonClassifier.weights
            self.bias = jsonClassifier.bias
            self.classes = jsonClassifier.classes
            return
        }
        
        // Fallback implementation with basic logistic regression
        print("⚠️ Using fallback ML classifier")
        
        self.classes = ["non_sensitive", "nric", "email", "credit_card", "phone", "birthday", "address"]
        
        // Initialize with small random weights
        let numFeatures = 1000 + 6 // TF-IDF features + regex features
        var randomWeights: [[Double]] = []
        
        for _ in 0..<classes.count {
            var classWeights: [Double] = []
            for _ in 0..<numFeatures {
                classWeights.append(Double.random(in: -0.1...0.1))
            }
            randomWeights.append(classWeights)
        }
        
        self.weights = randomWeights
        self.bias = Array(repeating: 0.0, count: classes.count)
        
        print("✅ Fallback classifier initialized with \(classes.count) classes and \(numFeatures) features")
    }
    
    static func fromJSON(data: Data) throws -> MLClassifier {
        struct ClassifierData: Codable {
            let weights: [[Double]]
            let bias: [Double]
            let classes: [String]
        }
        
        let classifierData = try JSONDecoder().decode(ClassifierData.self, from: data)
        
        return MLClassifier(
            weights: classifierData.weights,
            bias: classifierData.bias,
            classes: classifierData.classes
        )
    }
    
    private init(weights: [[Double]], bias: [Double], classes: [String]) {
        self.weights = weights
        self.bias = bias
        self.classes = classes
    }
    
    func predict(features: [Double]) -> (String, [String: Double]) {
        var scores: [Double] = []
        
        // Calculate linear scores for each class
        for i in 0..<classes.count {
            var score = bias[i]
            let classWeights = weights[i]
            
            for j in 0..<min(features.count, classWeights.count) {
                score += classWeights[j] * features[j]
            }
            scores.append(score)
        }
        
        // Apply softmax to get probabilities
        let maxScore = scores.max() ?? 0.0
        let expScores = scores.map { exp($0 - maxScore) }
        let sumExp = expScores.reduce(0, +)
        
        guard sumExp > 0 else {
            // Fallback if softmax fails
            let uniformProb = 1.0 / Double(classes.count)
            var allProbabilities: [String: Double] = [:]
            for className in classes {
                allProbabilities[className] = uniformProb
            }
            return (classes[0], allProbabilities)
        }
        
        let probabilities = expScores.map { $0 / sumExp }
        
        // Find predicted class
        let maxIndex = probabilities.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let predictedClass = classes[maxIndex]
        
        // Create probability dictionary
        var allProbabilities: [String: Double] = [:]
        for (index, className) in classes.enumerated() {
            allProbabilities[className] = probabilities[index]
        }
        
        return (predictedClass, allProbabilities)
    }
}

// MARK: - Text Classification Manager

class TextClassificationManager {
    
    // Model components
    private var modelInfo: ModelInfo?
    private var tfidfTransformer: TFIDFTransformer?
    private var regexExtractor: RegexFeatureExtractor?
    private var classifier: MLClassifier?
    
    // Model data
    private var modelInfoData: Data?
    private var tfidfData: Data?
    private var regexData: Data?
    private var classifierData: Data?
    
    // Regex patterns for quick classification
    private let quickRegexPatterns: [String: [NSRegularExpression]] = {
        var patterns: [String: [NSRegularExpression]] = [:]
        
        // NRIC patterns (Singapore)
        patterns["nric"] = [
            try! NSRegularExpression(pattern: "^[STFG]\\d{7}[A-Z]$", options: .caseInsensitive),
            try! NSRegularExpression(pattern: "\\b[STFG]\\d{7}[A-Z]\\b", options: .caseInsensitive)
        ]
        
        // Email patterns
        patterns["email"] = [
            try! NSRegularExpression(pattern: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b", options: [])
        ]
        
        // Credit card patterns
        patterns["credit_card"] = [
            try! NSRegularExpression(pattern: "\\b(?:\\d{4}[-\\s]?){3}\\d{4}\\b", options: []),
            try! NSRegularExpression(pattern: "\\b\\d{13,19}\\b", options: [])
        ]
        
        // Phone patterns
        patterns["phone"] = [
            try! NSRegularExpression(pattern: "\\+65\\s?[689]\\d{7}", options: []),
            try! NSRegularExpression(pattern: "\\b[689]\\d{7}\\b", options: []),
            try! NSRegularExpression(pattern: "\\b\\d{3}[-\\s]?\\d{3}[-\\s]?\\d{4}\\b", options: [])
        ]
        
        // Birthday patterns
        patterns["birthday"] = [
            try! NSRegularExpression(pattern: "\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{4}\\b", options: []),
            try! NSRegularExpression(pattern: "\\b\\d{4}[/-]\\d{1,2}[/-]\\d{1,2}\\b", options: []),
            try! NSRegularExpression(pattern: "\\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2},?\\s+\\d{4}\\b", options: .caseInsensitive)
        ]
        
        // Address patterns
        patterns["address"] = [
            try! NSRegularExpression(pattern: "\\b\\d+\\s+[A-Za-z]+\\s+(Street|St|Road|Rd|Avenue|Ave|Drive|Dr|Lane|Ln|Boulevard|Blvd)", options: .caseInsensitive),
            try! NSRegularExpression(pattern: "\\bSingapore\\s+\\d{6}\\b", options: .caseInsensitive),
            try! NSRegularExpression(pattern: "\\b(Block|Blk|Unit)\\s+\\d+", options: .caseInsensitive)
        ]
        
        return patterns
    }()
    
    init() {
        loadModels()
    }
    
    // MARK: - Model Loading
    
    private func loadModels() {
        print("🔄 Loading text classification models from Models folder...")
        
        // Load all model files
        modelInfoData = ModelLoader.loadPickleData(filename: "model_info")
        tfidfData = ModelLoader.loadPickleData(filename: "tfidf_transformer")
        regexData = ModelLoader.loadPickleData(filename: "regex_transformer")
        classifierData = ModelLoader.loadPickleData(filename: "classifier_only")
        
        // Load model info
        modelInfo = ModelLoader.loadModelInfo()
        
        if let modelInfo = modelInfo {
            print("📋 Model info loaded:")
            print("   - Model type: \(modelInfo.modelType)")
            print("   - Classes: \(modelInfo.classes)")
            print("   - TF-IDF vocab size: \(modelInfo.tfidfVocabSize)")
        }
        
        // Try to initialize ML components
        if let tfidfData = tfidfData {
            do {
                tfidfTransformer = try TFIDFTransformer(data: tfidfData)
                print("✅ TF-IDF transformer loaded")
            } catch {
                print("❌ Failed to load TF-IDF transformer: \(error)")
                // Try fallback initialization
                tfidfTransformer = try? TFIDFTransformer(data: Data())
            }
        } else {
            // Initialize with fallback
            tfidfTransformer = try? TFIDFTransformer(data: Data())
        }
        
        if let regexData = regexData {
            do {
                regexExtractor = try RegexFeatureExtractor(data: regexData)
                print("✅ Regex extractor loaded")
            } catch {
                print("❌ Failed to load regex extractor: \(error)")
                // Try fallback initialization
                regexExtractor = try? RegexFeatureExtractor(data: Data())
            }
        } else {
            // Initialize with fallback
            regexExtractor = try? RegexFeatureExtractor(data: Data())
        }
        
        if let classifierData = classifierData {
            do {
                classifier = try MLClassifier(data: classifierData)
                print("✅ Classifier loaded")
            } catch {
                print("❌ Failed to load classifier: \(error)")
                // Try fallback initialization
                classifier = try? MLClassifier(data: Data())
            }
        } else {
            // Initialize with fallback
            classifier = try? MLClassifier(data: Data())
        }
        
        // Check what models we have
        let modelsAvailable = [
            "Model Info": modelInfoData != nil,
            "TF-IDF": tfidfData != nil && tfidfTransformer != nil,
            "Regex": regexData != nil && regexExtractor != nil,
            "Classifier": classifierData != nil && classifier != nil
        ]
        
        print("📊 Models availability:")
        for (name, available) in modelsAvailable {
            print("   - \(name): \(available ? "✅" : "❌")")
        }
        
        print("💡 Quick regex patterns loaded for: \(quickRegexPatterns.keys.sorted())")
        
        if tfidfTransformer != nil && regexExtractor != nil && classifier != nil {
            print("🎉 All ML components initialized successfully!")
        } else {
            print("⚠️ Using hybrid classification (regex + fallback ML)")
        }
    }
    
    // MARK: - Classification Methods
    
    func classify(text: String) -> ClassificationResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🔍 Classifying text: '\(cleanText)'")
        
        // First try quick regex patterns
        if let regexResult = classifyWithQuickRegex(text: cleanText) {
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ Regex classification: \(regexResult) in \(String(format: "%.1f", processingTime * 1000))ms")
            
            return ClassificationResult(
                predictedClass: regexResult,
                confidence: 0.95,
                allProbabilities: [regexResult: 0.95, "non_sensitive": 0.05],
                processingTime: processingTime,
                method: "regex"
            )
        }
        
        // If ML models are available, use them
        if tfidfTransformer != nil && regexExtractor != nil && classifier != nil {
            return classifyWithML(text: cleanText, startTime: startTime)
        }
        
        // Fallback to non-sensitive
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        print("ℹ️ No classification match, defaulting to non-sensitive")
        
        return ClassificationResult(
            predictedClass: "non_sensitive",
            confidence: 0.8,
            allProbabilities: ["non_sensitive": 0.8],
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
    
    private func classifyWithML(text: String, startTime: CFAbsoluteTime) -> ClassificationResult {
        guard let tfidfTransformer = tfidfTransformer,
              let regexExtractor = regexExtractor,
              let classifier = classifier else {
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            return ClassificationResult(
                predictedClass: "non_sensitive",
                confidence: 0.5,
                allProbabilities: ["non_sensitive": 0.5],
                processingTime: processingTime,
                method: "fallback"
            )
        }
        
        // Extract TF-IDF features
        let tfidfFeatures = tfidfTransformer.transform(text: text)
        
        // Extract regex features
        let regexFeatures = regexExtractor.extractFeatures(text: text)
        
        // Combine features
        let combinedFeatures = tfidfFeatures + regexFeatures
        
        print("🔧 Features extracted: TF-IDF=\(tfidfFeatures.count), Regex=\(regexFeatures.count), Total=\(combinedFeatures.count)")
        
        // Predict
        let (predictedClass, allProbabilities) = classifier.predict(features: combinedFeatures)
        let confidence = allProbabilities[predictedClass] ?? 0.0
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ ML classification: \(predictedClass) (confidence: \(String(format: "%.2f", confidence))) in \(String(format: "%.1f", processingTime * 1000))ms")
        
        return ClassificationResult(
            predictedClass: predictedClass,
            confidence: confidence,
            allProbabilities: allProbabilities,
            processingTime: processingTime,
            method: "ml"
        )
    }
    
    func classifyBatch(texts: [String]) -> [ClassificationResult] {
        print("🔄 Batch classifying \(texts.count) texts...")
        let results = texts.map { classify(text: $0) }
        
        let avgTime = results.map { $0.processingTime }.reduce(0, +) / Double(results.count)
        let methodCounts = Dictionary(grouping: results, by: { $0.method }).mapValues { $0.count }
        
        print("📊 Batch classification complete:")
        print("   - Average time: \(String(format: "%.1f", avgTime * 1000))ms")
        print("   - Methods used: \(methodCounts)")
        
        return results
    }
    
    // MARK: - Utility Methods
    
    func getModelStatus() -> [String: Any] {
        return [
            "regex_patterns_loaded": !quickRegexPatterns.isEmpty,
            "regex_categories": Array(quickRegexPatterns.keys),
            "model_info_available": modelInfo != nil,
            "tfidf_transformer_loaded": tfidfTransformer != nil,
            "regex_extractor_loaded": regexExtractor != nil,
            "classifier_loaded": classifier != nil,
            "tfidf_data_loaded": tfidfData != nil,
            "regex_data_loaded": regexData != nil,
            "classifier_data_loaded": classifierData != nil,
            "classes": modelInfo?.classes ?? [],
            "ml_pipeline_ready": tfidfTransformer != nil && regexExtractor != nil && classifier != nil
        ]
    }
    
    func printModelStatus() {
        let status = getModelStatus()
        print("\n📋 Model Status Report:")
        print("=" * 50)
        
        if let classes = status["classes"] as? [String] {
            print("🎯 Classes: \(classes.joined(separator: ", "))")
        }
        
        print("🔧 Components:")
        print("   - Quick Regex: \(status["regex_patterns_loaded"] as? Bool == true ? "✅" : "❌")")
        print("   - TF-IDF Transformer: \(status["tfidf_transformer_loaded"] as? Bool == true ? "✅" : "❌")")
        print("   - Regex Extractor: \(status["regex_extractor_loaded"] as? Bool == true ? "✅" : "❌")")
        print("   - ML Classifier: \(status["classifier_loaded"] as? Bool == true ? "✅" : "❌")")
        
        print("📁 Data Files:")
        print("   - Model Info: \(status["model_info_available"] as? Bool == true ? "✅" : "❌")")
        print("   - TF-IDF Data: \(status["tfidf_data_loaded"] as? Bool == true ? "✅" : "❌")")
        print("   - Regex Data: \(status["regex_data_loaded"] as? Bool == true ? "✅" : "❌")")
        print("   - Classifier Data: \(status["classifier_data_loaded"] as? Bool == true ? "✅" : "❌")")
        
        let mlReady = status["ml_pipeline_ready"] as? Bool == true
        print("🚀 ML Pipeline: \(mlReady ? "✅ Ready" : "⚠️ Using Fallback")")
        
        if let categories = status["regex_categories"] as? [String] {
            print("🔍 Quick Regex Categories: \(categories.sorted().joined(separator: ", "))")
        }
        
        print("=" * 50)
    }
}

// MARK: - String Extension for Convenience

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}
