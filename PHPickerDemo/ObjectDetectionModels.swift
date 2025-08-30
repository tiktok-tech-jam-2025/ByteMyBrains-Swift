//
//  ObjectDetectionModels.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 30/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

import Foundation
import UIKit

// MARK: - Object Detection Models

struct ObjectBoundingBox {
    let className: String
    let confidence: Float
    let boundingBox: CGRect
    let assetIdentifier: String
    let isSensitive: Bool
    let classIndex: Int
    
    init(className: String, confidence: Float, boundingBox: CGRect, assetIdentifier: String, classIndex: Int) {
        self.className = className
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.assetIdentifier = assetIdentifier
        self.classIndex = classIndex
        self.isSensitive = SensitiveObjectClassifier.shared.isSensitive(className: className)
    }
    
    var displayName: String {
        switch className {
        case "0": return "Phone Screen"
        case "1": return "Laptop Screen"
        case "paper": return "Document"
        default: return className.capitalized
        }
    }
    
    var sensitivityReason: String? {
        guard isSensitive else { return nil }
        
        switch className {
        case "person": return "Contains person"
        case "face": return "Contains face"
        case "0": return "Phone screen may contain sensitive info"
        case "1": return "Laptop screen may contain sensitive info"
        case "paper": return "Document may contain sensitive text"
        case "laptop": return "Laptop screen may be visible"
        case "cell phone": return "Phone screen may be visible"
        case "tv": return "TV screen may show sensitive content"
        default: return "Potentially sensitive object"
        }
    }
}

struct ObjectDetectionResult {
    let assetIdentifier: String
    let objectBoxes: [ObjectBoundingBox]
    let processingTime: TimeInterval
    let error: Error?
    
    var sensitiveObjectCount: Int {
        return objectBoxes.filter { $0.isSensitive }.count
    }
    
    var hasSensitiveObjects: Bool {
        return sensitiveObjectCount > 0
    }
    
    var totalObjectCount: Int {
        return objectBoxes.count
    }
}

// MARK: - Sensitive Object Classifier

class SensitiveObjectClassifier {
    static let shared = SensitiveObjectClassifier()
    
    private init() {}
    
    // Define which YOLO classes are considered sensitive
    private let sensitiveClasses: Set<String> = [
        // People and faces
        "person",
        "face",
        
        // Screens that may contain sensitive information
        "0",          // Phone screen (custom class)
        "1",          // Laptop screen (custom class)
        "laptop",
        "cell phone",
        "tv",
        
        // Documents
        "paper",      // Documents (custom class)
        
        // Optional: Other potentially sensitive items
        // "book",    // Books might contain sensitive info
        // "keyboard", // Keyboards might show what's being typed
    ]
    
    func isSensitive(className: String) -> Bool {
        return sensitiveClasses.contains(className.lowercased())
    }
    
    func getAllSensitiveClasses() -> [String] {
        return Array(sensitiveClasses).sorted()
    }
    
    func getSensitivityCategory(for className: String) -> SensitivityCategory {
        switch className.lowercased() {
        case "person", "face":
            return .person
        case "0", "1", "laptop", "cell phone", "tv":
            return .screen
        case "paper":
            return .document
        default:
            return .other
        }
    }
}

// MARK: - Sensitivity Categories

enum SensitivityCategory: String, CaseIterable {
    case person = "person"
    case screen = "screen"
    case document = "document"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .person: return "Person/Face"
        case .screen: return "Screen/Display"
        case .document: return "Document"
        case .other: return "Other Sensitive"
        }
    }
    
    var color: UIColor {
        switch self {
        case .person: return .systemRed
        case .screen: return .systemOrange
        case .document: return .systemPurple
        case .other: return .systemYellow
        }
    }
    
    var emoji: String {
        switch self {
        case .person: return "👤"
        case .screen: return "📱"
        case .document: return "📄"
        case .other: return "⚠️"
        }
    }
}

// MARK: - YOLO Class Definitions

struct YOLOClasses {
    static let allClasses = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake",
        "chair", "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop",
        "mouse", "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
        "toothbrush", "paper", "face", "0", "1"
    ]
    
    static func getClassName(for index: Int) -> String {
        guard index >= 0 && index < allClasses.count else {
            return "unknown"
        }
        return allClasses[index]
    }
    
    static func getClassIndex(for name: String) -> Int? {
        return allClasses.firstIndex(of: name)
    }
    
    static let totalClasses = allClasses.count
}

// MARK: - Object Detection Configuration

enum ObjectDetectionConfiguration {
    case fast      // Lower confidence threshold, faster processing
    case balanced  // Default settings
    case precise   // Higher confidence threshold, slower processing
    
    var confidenceThreshold: Float {
        switch self {
        case .fast: return 0.3
        case .balanced: return 0.5
        case .precise: return 0.7
        }
    }
    
    var nmsThreshold: Float {
        switch self {
        case .fast: return 0.4
        case .balanced: return 0.5
        case .precise: return 0.6
        }
    }
}

// MARK: - Object Detection Errors

enum ObjectDetectionError: LocalizedError {
    case modelNotFound
    case modelLoadFailed
    case invalidImageFormat
    case predictionFailed
    case alreadyProcessing
    case noImagesSelected
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "YOLOv12n model file not found in app bundle"
        case .modelLoadFailed:
            return "Failed to load YOLOv12n model"
        case .invalidImageFormat:
            return "Invalid image format for object detection"
        case .predictionFailed:
            return "Object detection prediction failed"
        case .alreadyProcessing:
            return "Object detection is already in progress"
        case .noImagesSelected:
            return "No images selected for object detection"
        }
    }
}
