//
//  ObjectDetectionProcessor.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 30/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

import UIKit
import PhotosUI
import Vision
import CoreML
import Foundation

// MARK: - Object Detection Processor Delegate

protocol ObjectDetectionProcessorDelegate: AnyObject {
    func objectDetectionProcessor(_ processor: ObjectDetectionProcessor, didStartProcessing totalImages: Int)
    func objectDetectionProcessor(_ processor: ObjectDetectionProcessor, didProcessImage at: Int, of: Int)
    func objectDetectionProcessor(_ processor: ObjectDetectionProcessor, didCompleteWithResults results: [ObjectDetectionResult])
    func objectDetectionProcessor(_ processor: ObjectDetectionProcessor, didFailWithError error: Error)
}

// MARK: - Object Detection Processor

class ObjectDetectionProcessor {
    
    weak var delegate: ObjectDetectionProcessorDelegate?
    private var isProcessing = false
    private var configuration: ObjectDetectionConfiguration = .balanced
    
    // YOLO model
    private var yoloModel: MLModel?
    private var visionModel: VNCoreMLModel?
    
    // MARK: - Initialization
    
    init() {
        loadYOLOModel()
    }
    
    // MARK: - Model Loading
    
    private func loadYOLOModel() {
        print("🤖 Loading YOLOv12n model...")
        
        // Debug: List all .mlmodelc files in the bundle
        if let bundlePath = Bundle.main.resourcePath {
            let fileManager = FileManager.default
            do {
                let allFiles = try fileManager.contentsOfDirectory(atPath: bundlePath)
                let modelFiles = allFiles.filter { $0.hasSuffix(".mlmodelc") }
                print("📁 Found .mlmodelc files in bundle: \(modelFiles)")
                
                // Also check Models subfolder
                let modelsPath = bundlePath + "/Models"
                if fileManager.fileExists(atPath: modelsPath) {
                    let modelsFiles = try fileManager.contentsOfDirectory(atPath: modelsPath)
                    let modelsModelFiles = modelsFiles.filter { $0.hasSuffix(".mlmodelc") }
                    print("📁 Found .mlmodelc files in Models folder: \(modelsModelFiles)")
                } else {
                    print("📁 Models folder does not exist in bundle")
                }
            } catch {
                print("❌ Error listing bundle contents: \(error)")
            }
        }
        
        // Try multiple possible locations and names
        let possibleLocations = [
            ("yolo12n", nil),                    // Root of bundle
            ("yolo12n", "Models"),               // Models subfolder
            ("yolov12n", nil),                   // Alternative name
            ("yolov12n", "Models"),              // Alternative name in Models
        ]
        
        var modelURL: URL?
        
        for (name, subdirectory) in possibleLocations {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc", subdirectory: subdirectory) {
                modelURL = url
                print("✅ Found model at: \(url.path)")
                break
            } else {
                let location = subdirectory != nil ? "\(subdirectory!)/\(name).mlmodelc" : "\(name).mlmodelc"
                print("❌ Not found: \(location)")
            }
        }
        
        guard let finalModelURL = modelURL else {
            print("❌ YOLOv12n model file not found in any expected location")
            return
        }
        
        do {
            yoloModel = try MLModel(contentsOf: finalModelURL)
            visionModel = try VNCoreMLModel(for: yoloModel!)
            print("✅ YOLOv12n model loaded successfully from: \(finalModelURL.lastPathComponent)")
            print("📊 Model input: \(yoloModel!.modelDescription.inputDescriptionsByName)")
            print("📊 Model output: \(yoloModel!.modelDescription.outputDescriptionsByName)")
        } catch {
            print("❌ Failed to load YOLOv12n model: \(error)")
            yoloModel = nil
            visionModel = nil
        }
    }
    
    
    // MARK: - Public Methods
    
    func processImages(from selection: [String: PHPickerResult], configuration: ObjectDetectionConfiguration = .balanced) {
        self.configuration = configuration
        processImages(from: selection)
    }
    
    func processImages(from selection: [String: PHPickerResult]) {
        guard !isProcessing else {
            delegate?.objectDetectionProcessor(self, didFailWithError: ObjectDetectionError.alreadyProcessing)
            return
        }
        
        guard !selection.isEmpty else {
            delegate?.objectDetectionProcessor(self, didFailWithError: ObjectDetectionError.noImagesSelected)
            return
        }
        
        guard yoloModel != nil, visionModel != nil else {
            delegate?.objectDetectionProcessor(self, didFailWithError: ObjectDetectionError.modelNotFound)
            return
        }
        
        isProcessing = true
        let imageIdentifiers = Array(selection.keys)
        delegate?.objectDetectionProcessor(self, didStartProcessing: imageIdentifiers.count)
        
        print("🚀 Starting object detection for \(imageIdentifiers.count) images")
        print("⚙️ Configuration: \(configuration)")
        print("🎯 Confidence threshold: \(configuration.confidenceThreshold)")
        
        processImagesSequentially(selection: selection, identifiers: imageIdentifiers, currentIndex: 0, results: [])
    }
    
    func cancelProcessing() {
        isProcessing = false
        print("🛑 Object detection processing cancelled")
    }
    
    // MARK: - Sequential Processing
    
    private func processImagesSequentially(selection: [String: PHPickerResult],
                                         identifiers: [String],
                                         currentIndex: Int,
                                         results: [ObjectDetectionResult]) {
        guard isProcessing && currentIndex < identifiers.count else {
            isProcessing = false
            if currentIndex >= identifiers.count {
                print("🎉 Object detection completed for all \(identifiers.count) images")
                delegate?.objectDetectionProcessor(self, didCompleteWithResults: results)
            }
            return
        }
        
        let identifier = identifiers[currentIndex]
        delegate?.objectDetectionProcessor(self, didProcessImage: currentIndex + 1, of: identifiers.count)
        
        guard let pickerResult = selection[identifier] else {
            let errorResult = ObjectDetectionResult(
                assetIdentifier: identifier,
                objectBoxes: [],
                processingTime: 0,
                error: ObjectDetectionError.invalidImageFormat
            )
            processNext(selection: selection, identifiers: identifiers, currentIndex: currentIndex, results: results + [errorResult])
            return
        }
        
        loadImageAndDetectObjects(pickerResult: pickerResult, identifier: identifier) { [weak self] result in
            guard let self = self else { return }
            self.processNext(selection: selection, identifiers: identifiers, currentIndex: currentIndex, results: results + [result])
        }
    }
    
    private func processNext(selection: [String: PHPickerResult], identifiers: [String], currentIndex: Int, results: [ObjectDetectionResult]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.processImagesSequentially(selection: selection, identifiers: identifiers, currentIndex: currentIndex + 1, results: results)
        }
    }
    
    // MARK: - Image Loading and Processing
    
    private func loadImageAndDetectObjects(pickerResult: PHPickerResult, identifier: String, completion: @escaping (ObjectDetectionResult) -> Void) {
        print("🔄 loadImageAndDetectObjects called for \(identifier)")
        let itemProvider = pickerResult.itemProvider
        
        guard itemProvider.canLoadObject(ofClass: UIImage.self) else {
            print("❌ ItemProvider cannot load UIImage for \(identifier)")
            let result = ObjectDetectionResult(
                assetIdentifier: identifier,
                objectBoxes: [],
                processingTime: 0,
                error: ObjectDetectionError.invalidImageFormat
            )
            completion(result)
            return
        }
        
        print("✅ ItemProvider can load UIImage, starting load for \(identifier)")
        
        itemProvider.loadObject(ofClass: UIImage.self) { [weak self] (image: NSItemProviderReading?, error: Error?) in
            print("📥 loadObject completion called for \(identifier)")
            
            guard let self = self else {
                print("❌ Self is nil in loadObject completion for \(identifier)")
                return
            }
            
            if let error = error {
                print("❌ Error loading image for \(identifier): \(error)")
                let result = ObjectDetectionResult(
                    assetIdentifier: identifier,
                    objectBoxes: [],
                    processingTime: 0,
                    error: error
                )
                completion(result)
                return
            }
            
            guard let uiImage = image as? UIImage else {
                print("❌ Could not cast loaded object to UIImage for \(identifier)")
                let result = ObjectDetectionResult(
                    assetIdentifier: identifier,
                    objectBoxes: [],
                    processingTime: 0,
                    error: ObjectDetectionError.invalidImageFormat
                )
                completion(result)
                return
            }
            
            print("✅ Successfully loaded UIImage for \(identifier): \(uiImage.size)")
            self.performObjectDetection(on: uiImage, identifier: identifier, completion: completion)
        }
    }
    
    // MARK: - Object Detection
    
    private func performObjectDetection(on image: UIImage, identifier: String, completion: @escaping (ObjectDetectionResult) -> Void) {
        print("🔍 performObjectDetection called for \(identifier)")
        print("📸 Image size: \(image.size)")
        
        guard let cgImage = image.cgImage else {
            print("❌ Could not get cgImage from UIImage")
            let result = ObjectDetectionResult(
                assetIdentifier: identifier,
                objectBoxes: [],
                processingTime: 0,
                error: ObjectDetectionError.invalidImageFormat
            )
            completion(result)
            return
        }
        
        guard let visionModel = self.visionModel else {
            print("❌ Vision model not available")
            let result = ObjectDetectionResult(
                assetIdentifier: identifier,
                objectBoxes: [],
                processingTime: 0,
                error: ObjectDetectionError.modelNotFound
            )
            completion(result)
            return
        }
        
        print("✅ Got cgImage: \(cgImage.width)x\(cgImage.height)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create object detection request
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            print("🎯 VNCoreMLRequest completion block called for \(identifier)")
            self?.handleObjectDetectionResults(request: request, error: error, identifier: identifier, startTime: startTime, completion: completion)
        }
        
        // Configure the request
        request.imageCropAndScaleOption = .scaleFill
        print("⚙️ Request configured for object detection")
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        print("🎯 Created VNImageRequestHandler")
        
        DispatchQueue.global(qos: .userInitiated).async {
            print("🚀 About to perform Vision request for \(identifier)")
            do {
                try handler.perform([request])
                print("✅ Vision request completed successfully for \(identifier)")
            } catch {
                print("❌ Vision request failed for \(identifier): \(error)")
                let result = ObjectDetectionResult(
                    assetIdentifier: identifier,
                    objectBoxes: [],
                    processingTime: 0,
                    error: error
                )
                completion(result)
            }
        }
    }
    
    // MARK: - Results Handling
    
    private func handleObjectDetectionResults(request: VNRequest, error: Error?, identifier: String, startTime: CFAbsoluteTime, completion: @escaping (ObjectDetectionResult) -> Void) {
        print("🔍 handleObjectDetectionResults called for \(identifier)")
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ Object detection processing time: \(processingTime)s")
        
        if let error = error {
            print("❌ Object detection error in handleResults: \(error)")
            let result = ObjectDetectionResult(
                assetIdentifier: identifier,
                objectBoxes: [],
                processingTime: processingTime,
                error: error
            )
            completion(result)
            return
        }
        
        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            print("❌ Could not cast request.results to [VNRecognizedObjectObservation]")
            let result = ObjectDetectionResult(
                assetIdentifier: identifier,
                objectBoxes: [],
                processingTime: processingTime,
                error: ObjectDetectionError.predictionFailed
            )
            completion(result)
            return
        }
        
        print("✅ Got \(observations.count) VNRecognizedObjectObservation objects")
        
        var objectBoxes: [ObjectBoundingBox] = []
        
        for observation in observations {
            guard let topLabel = observation.labels.first else { continue }
            
            // Apply confidence threshold
            if topLabel.confidence < configuration.confidenceThreshold {
                continue
            }
            
            // Get class name from identifier
            let className = topLabel.identifier
            
            // Validate class name exists in our YOLO classes
            guard YOLOClasses.allClasses.contains(className) else {
                print("⚠️ Unknown class name: \(className)")
                continue
            }
            
            let classIndex = YOLOClasses.getClassIndex(for: className) ?? -1
            
            let objectBox = ObjectBoundingBox(
                className: className,
                confidence: topLabel.confidence,
                boundingBox: observation.boundingBox,
                assetIdentifier: identifier,
                classIndex: classIndex
            )
            
            objectBoxes.append(objectBox)
            
            let sensitiveEmoji = objectBox.isSensitive ? "🔴" : "🟢"
            print("\(sensitiveEmoji) Detected: \(objectBox.displayName) (confidence: \(String(format: "%.2f", objectBox.confidence)))")
        }
        
        // Apply Non-Maximum Suppression if needed
        objectBoxes = applyNonMaximumSuppression(to: objectBoxes)
        
        print("📝 Created \(objectBoxes.count) object boxes for \(identifier)")
        
        let result = ObjectDetectionResult(
            assetIdentifier: identifier,
            objectBoxes: objectBoxes,
            processingTime: processingTime,
            error: nil
        )
        
        print("🎉 Completed object detection for \(identifier):")
        print("   - Processing time: \(String(format: "%.2f", processingTime))s")
        print("   - Objects detected: \(result.totalObjectCount)")
        print("   - Sensitive objects: \(result.sensitiveObjectCount)")
        
        completion(result)
    }
    
    // MARK: - Non-Maximum Suppression
    
    private func applyNonMaximumSuppression(to objectBoxes: [ObjectBoundingBox]) -> [ObjectBoundingBox] {
        // Group by class name
        let groupedBoxes = Dictionary(grouping: objectBoxes) { $0.className }
        var suppressedBoxes: [ObjectBoundingBox] = []
        
        for (_, boxes) in groupedBoxes {
            // Sort by confidence (highest first)
            let sortedBoxes = boxes.sorted { $0.confidence > $1.confidence }
            var keep: [Bool] = Array(repeating: true, count: sortedBoxes.count)
            
            for i in 0..<sortedBoxes.count {
                if !keep[i] { continue }
                
                for j in (i + 1)..<sortedBoxes.count {
                    if !keep[j] { continue }
                    
                    let iou = calculateIOU(box1: sortedBoxes[i].boundingBox, box2: sortedBoxes[j].boundingBox)
                    if iou > configuration.nmsThreshold {
                        keep[j] = false
                    }
                }
            }
            
            for (index, shouldKeep) in keep.enumerated() {
                if shouldKeep {
                    suppressedBoxes.append(sortedBoxes[index])
                }
            }
        }
        
        return suppressedBoxes
    }
    
    // MARK: - Helper Methods
    
    private func calculateIOU(box1: CGRect, box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        let intersectionArea = intersection.width * intersection.height
        let union = box1.area + box2.area - intersectionArea
        
        return union > 0 ? Float(intersectionArea / union) : 0
    }
}

// MARK: - CGRect Extension

private extension CGRect {
    var area: CGFloat {
        return width * height
    }
}
