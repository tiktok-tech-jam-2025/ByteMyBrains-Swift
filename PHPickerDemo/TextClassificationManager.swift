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
        // For now, return a mock ModelInfo since we can't easily parse pickle in Swift
        // You could convert your model_info.pkl to JSON for easier loading
        return ModelInfo(
            modelType: "LogisticRegression",
            classes: ["non_sensitive", "nric", "email", "credit_card", "phone", "birthday", "address"],
            featureNames: nil,
            tfidfVocabSize: 1000,
            regexFeatures: ["nric", "email", "credit_card", "phone", "birthday", "address_keyword"]
        )
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
        
        // Load model info (using mock data for now)
        modelInfo = ModelLoader.loadModelInfo()
        
        if let modelInfo = modelInfo {
            print("📋 Model info loaded:")
            print("   - Model type: \(modelInfo.modelType)")
            print("   - Classes: \(modelInfo.classes)")
            print("   - TF-IDF vocab size: \(modelInfo.tfidfVocabSize)")
        }
        
        // Check what models we have
        let modelsAvailable = [
            "Model Info": modelInfoData != nil,
            "TF-IDF": tfidfData != nil,
            "Regex": regexData != nil,
            "Classifier": classifierData != nil
        ]
        
        print("📊 Models availability:")
        for (name, available) in modelsAvailable {
            print("   - \(name): \(available ? "✅" : "❌")")
        }
        
        // For now, we'll use regex-based classification
        print("⚠️  Using regex-based classification (pickle parsing not implemented yet)")
        print("💡 Regex patterns loaded for: \(quickRegexPatterns.keys.sorted())")
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
        if let classifier = classifier,
           let tfidfTransformer = tfidfTransformer {
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
        // This would use your loaded ML models
        // For now, return a placeholder
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        return ClassificationResult(
            predictedClass: "non_sensitive",
            confidence: 0.7,
            allProbabilities: ["non_sensitive": 0.7],
            processingTime: processingTime,
            method: "ml"
        )
    }
    
    func classifyBatch(texts: [String]) -> [ClassificationResult] {
        return texts.map { classify(text: $0) }
    }
    
    // MARK: - Utility Methods
    
    func getModelStatus() -> [String: Any] {
        return [
            "regex_patterns_loaded": !quickRegexPatterns.isEmpty,
            "regex_categories": Array(quickRegexPatterns.keys),
            "model_info_available": modelInfo != nil,
            "tfidf_data_loaded": tfidfData != nil,
            "regex_data_loaded": regexData != nil,
            "classifier_data_loaded": classifierData != nil,
            "classes": modelInfo?.classes ?? []
        ]
    }
}

// MARK: - Placeholder classes for ML components
// These will be implemented when we load the actual models

class TFIDFTransformer {
    private let data: Data
    
    init(data: Data) {
        self.data = data
        // TODO: Parse pickle data and implement TF-IDF transformation
    }
    
    func transform(text: String) -> [Double] {
        // Placeholder implementation
        return Array(repeating: 0.0, count: 1000)
    }
}

class RegexFeatureExtractor {
    private let data: Data
    
    init(data: Data) {
        self.data = data
        // TODO: Parse pickle data and implement regex feature extraction
    }
    
    func extractFeatures(text: String) -> [Double] {
        // Placeholder implementation
        return Array(repeating: 0.0, count: 6)
    }
}

class MLClassifier {
    private let data: Data
    
    init(data: Data) {
        self.data = data
        // TODO: Parse pickle data and implement classification
    }
    
    func predict(features: [Double]) -> (String, [String: Double]) {
        // Placeholder implementation
        return ("non_sensitive", ["non_sensitive": 0.8])
    }
}
