//
//  OCRProcessor.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 29/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

/*
OCRProcessor.swift
Handles OCR processing for selected images with bounding box text extraction.
*/

import UIKit
import PhotosUI
import Vision
import CoreML

// MARK: - OCR Result Models

struct TextBoundingBox {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
    let assetIdentifier: String
    var classification: ClassificationResult?
    
    init(text: String, boundingBox: CGRect, confidence: Float, assetIdentifier: String) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.assetIdentifier = assetIdentifier
        self.classification = nil
    }
    
    mutating func setClassification(_ classification: ClassificationResult) {
        self.classification = classification
    }
}

struct OCRResult {
    let assetIdentifier: String
    let textBoxes: [TextBoundingBox]
    let processingTime: TimeInterval
    let classificationTime: TimeInterval
    let error: Error?
    
    var totalProcessingTime: TimeInterval {
        return processingTime + classificationTime
    }
    
    var sensitiveTextCount: Int {
        return textBoxes.filter { $0.classification?.isSensitive == true }.count
    }
    
    var hasSensitiveText: Bool {
        return sensitiveTextCount > 0
    }
}

// MARK: - OCR Configuration

enum OCRConfiguration {
    case fast      // Fast recognition with lower accuracy
    case accurate  // Accurate recognition (default)
    case custom(recognitionLevel: VNRequestTextRecognitionLevel,
               usesLanguageCorrection: Bool,
               minimumTextHeight: Float,
               recognitionLanguages: [String]?)
}

// MARK: - OCR Processor Delegate

protocol OCRProcessorDelegate: AnyObject {
    func ocrProcessor(_ processor: OCRProcessor, didStartProcessing totalImages: Int)
    func ocrProcessor(_ processor: OCRProcessor, didProcessImage at: Int, of: Int)
    func ocrProcessor(_ processor: OCRProcessor, didCompleteWithResults results: [OCRResult])
    func ocrProcessor(_ processor: OCRProcessor, didFailWithError error: Error)
}

// MARK: - OCR Processor

class OCRProcessor {
    
    weak var delegate: OCRProcessorDelegate?
    private var isProcessing = false
    private var configuration: OCRConfiguration = .accurate
    private let textClassificationManager = TextClassificationManager()
    
    // MARK: - Public Methods
    
    func processImages(from selection: [String: PHPickerResult], configuration: OCRConfiguration = .accurate) {
        self.configuration = configuration
        processImages(from: selection)
    }
    
    func processImages(from selection: [String: PHPickerResult]) {
        guard !isProcessing else {
            delegate?.ocrProcessor(self, didFailWithError: OCRError.alreadyProcessing)
            return
        }
        
        guard !selection.isEmpty else {
            delegate?.ocrProcessor(self, didFailWithError: OCRError.noImagesSelected)
            return
        }
        
        isProcessing = true
        let imageIdentifiers = Array(selection.keys)
        delegate?.ocrProcessor(self, didStartProcessing: imageIdentifiers.count)
        
        print("🚀 Starting OCR processing with text classification for \(imageIdentifiers.count) images")
        
        processImagesSequentially(selection: selection, identifiers: imageIdentifiers, currentIndex: 0, results: [])
    }
    
    func cancelProcessing() {
        isProcessing = false
        print("🛑 OCR processing cancelled")
    }
    
    // MARK: - Private Methods
    
    private func processImagesSequentially(selection: [String: PHPickerResult],
                                         identifiers: [String],
                                         currentIndex: Int,
                                         results: [OCRResult]) {
        guard isProcessing && currentIndex < identifiers.count else {
            isProcessing = false
            if currentIndex >= identifiers.count {
                print("🎉 OCR processing completed for all \(identifiers.count) images")
                delegate?.ocrProcessor(self, didCompleteWithResults: results)
            }
            return
        }
        
        let identifier = identifiers[currentIndex]
        delegate?.ocrProcessor(self, didProcessImage: currentIndex + 1, of: identifiers.count)
        
        guard let pickerResult = selection[identifier] else {
            let errorResult = OCRResult(
                assetIdentifier: identifier,
                textBoxes: [],
                processingTime: 0,
                classificationTime: 0,
                error: OCRError.failedToLoadImage
            )
            processNext(selection: selection, identifiers: identifiers, currentIndex: currentIndex, results: results + [errorResult])
            return
        }
        
        loadImageAndProcess(pickerResult: pickerResult, identifier: identifier) { [weak self] (result: OCRResult) in
            guard let self = self else { return }
            self.processNext(selection: selection, identifiers: identifiers, currentIndex: currentIndex, results: results + [result])
        }
    }
    
    private func processNext(selection: [String: PHPickerResult], identifiers: [String], currentIndex: Int, results: [OCRResult]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.processImagesSequentially(selection: selection, identifiers: identifiers, currentIndex: currentIndex + 1, results: results)
        }
    }
    
    private func loadImageAndProcess(pickerResult: PHPickerResult, identifier: String, completion: @escaping (OCRResult) -> Void) {
        print("🔄 loadImageAndProcess called for \(identifier)")
        let itemProvider = pickerResult.itemProvider
        
        print("📋 ItemProvider registered types: \(itemProvider.registeredTypeIdentifiers)")
        
        guard itemProvider.canLoadObject(ofClass: UIImage.self) else {
            print("❌ ItemProvider cannot load UIImage for \(identifier)")
            let result = OCRResult(
                assetIdentifier: identifier,
                textBoxes: [],
                processingTime: 0,
                classificationTime: 0,
                error: OCRError.unsupportedImageType
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
                let result = OCRResult(
                    assetIdentifier: identifier,
                    textBoxes: [],
                    processingTime: 0,
                    classificationTime: 0,
                    error: error
                )
                completion(result)
                return
            }
            
            guard let uiImage = image as? UIImage else {
                print("❌ Could not cast loaded object to UIImage for \(identifier)")
                let result = OCRResult(
                    assetIdentifier: identifier,
                    textBoxes: [],
                    processingTime: 0,
                    classificationTime: 0,
                    error: OCRError.failedToLoadImage
                )
                completion(result)
                return
            }
            
            print("✅ Successfully loaded UIImage for \(identifier): \(uiImage.size)")
            self.performOCR(on: uiImage, identifier: identifier, completion: completion)
        }
    }
    
    private func performOCR(on image: UIImage, identifier: String, completion: @escaping (OCRResult) -> Void) {
        print("🔍 performOCR called for \(identifier)")
        print("📸 Image size: \(image.size)")
        
        guard let cgImage = image.cgImage else {
            print("❌ Could not get cgImage from UIImage")
            let result = OCRResult(
                assetIdentifier: identifier,
                textBoxes: [],
                processingTime: 0,
                classificationTime: 0,
                error: OCRError.failedToProcessImage
            )
            completion(result)
            return
        }
        
        print("✅ Got cgImage: \(cgImage.width)x\(cgImage.height)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create text recognition request
        let request = VNRecognizeTextRequest { [weak self] request, error in
            print("🎯 VNRecognizeTextRequest completion block called for \(identifier)")
            self?.handleTextRecognitionResults(request: request, error: error, identifier: identifier, startTime: startTime, completion: completion)
        }
        
        // Configure the request based on the current configuration
        configureRequest(request, with: configuration)
        print("⚙️ Request configured with \(configuration)")
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        print("🎯 Created VNImageRequestHandler")
        
        DispatchQueue.global(qos: .userInitiated).async {
            print("🚀 About to perform Vision request for \(identifier)")
            do {
                try handler.perform([request])
                print("✅ Vision request completed successfully for \(identifier)")
            } catch {
                print("❌ Vision request failed for \(identifier): \(error)")
                let result = OCRResult(
                    assetIdentifier: identifier,
                    textBoxes: [],
                    processingTime: 0,
                    classificationTime: 0,
                    error: error
                )
                completion(result)
            }
        }
    }
    
    private func configureRequest(_ request: VNRecognizeTextRequest, with configuration: OCRConfiguration) {
        switch configuration {
        case .fast:
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.02
            
        case .accurate:
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.01
            
        case .custom(let recognitionLevel, let usesLanguageCorrection, let minimumTextHeight, let recognitionLanguages):
            request.recognitionLevel = recognitionLevel
            request.usesLanguageCorrection = usesLanguageCorrection
            request.minimumTextHeight = minimumTextHeight
            if let languages = recognitionLanguages {
                request.recognitionLanguages = languages
            }
        }
    }
    
    // MARK: - Text Classification
    
    private func classifyTextBoxes(_ textBoxes: [TextBoundingBox]) -> ([TextBoundingBox], TimeInterval) {
        let classificationStartTime = CFAbsoluteTimeGetCurrent()
        
        print("🔄 Starting text classification for \(textBoxes.count) text boxes")
        
        let classifiedTextBoxes = textBoxes.map { textBox in
            var mutableTextBox = textBox
            let classification = textClassificationManager.classify(text: textBox.text)
            mutableTextBox.setClassification(classification)
            
            let emoji = classification.isSensitive ? "🔴" : "🟢"
            print("\(emoji) '\(textBox.text)' -> \(classification.predictedClass.uppercased()) (confidence: \(String(format: "%.2f", classification.confidence)), method: \(classification.method))")
            
            return mutableTextBox
        }
        
        let classificationTime = CFAbsoluteTimeGetCurrent() - classificationStartTime
        let sensitiveCount = classifiedTextBoxes.filter { $0.classification?.isSensitive == true }.count
        
        print("🎯 Classification completed: \(sensitiveCount)/\(textBoxes.count) sensitive in \(String(format: "%.1f", classificationTime * 1000))ms")
        
        return (classifiedTextBoxes, classificationTime)
    }
    
    private func handleTextRecognitionResults(request: VNRequest, error: Error?, identifier: String, startTime: CFAbsoluteTime, completion: @escaping (OCRResult) -> Void) {
        print("🔍 handleTextRecognitionResults called for \(identifier)")
        let ocrProcessingTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ OCR Processing time: \(ocrProcessingTime)s")
        
        if let error = error {
            print("❌ OCR Error in handleTextRecognitionResults: \(error)")
            let result = OCRResult(
                assetIdentifier: identifier,
                textBoxes: [],
                processingTime: ocrProcessingTime,
                classificationTime: 0,
                error: error
            )
            completion(result)
            return
        }
        
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            print("❌ Could not cast request.results to [VNRecognizedTextObservation]")
            let result = OCRResult(
                assetIdentifier: identifier,
                textBoxes: [],
                processingTime: ocrProcessingTime,
                classificationTime: 0,
                error: OCRError.failedToProcessImage
            )
            completion(result)
            return
        }
        
        print("✅ Got \(observations.count) VNRecognizedTextObservation objects")
        
        var textBoxes: [TextBoundingBox] = []
        
        for (index, observation) in observations.enumerated() {
            guard let topCandidate = observation.topCandidates(1).first else {
                continue
            }
            
            let textBox = TextBoundingBox(
                text: topCandidate.string,
                boundingBox: observation.boundingBox,
                confidence: topCandidate.confidence,
                assetIdentifier: identifier
            )
            textBoxes.append(textBox)
        }
        
        print("📝 Created \(textBoxes.count) text boxes for \(identifier)")
        
        // Classify the extracted text
        let (classifiedTextBoxes, classificationTime) = classifyTextBoxes(textBoxes)
        
        let result = OCRResult(
            assetIdentifier: identifier,
            textBoxes: classifiedTextBoxes,
            processingTime: ocrProcessingTime,
            classificationTime: classificationTime,
            error: nil
        )
        
        print("🎉 Completed processing for \(identifier):")
        print("   - OCR: \(String(format: "%.2f", ocrProcessingTime))s")
        print("   - Classification: \(String(format: "%.3f", classificationTime))s")
        print("   - Total: \(String(format: "%.2f", result.totalProcessingTime))s")
        print("   - Sensitive text regions: \(result.sensitiveTextCount)/\(result.textBoxes.count)")
        
        completion(result)
    }
}

// MARK: - OCR Errors

enum OCRError: LocalizedError {
    case alreadyProcessing
    case noImagesSelected
    case failedToLoadImage
    case unsupportedImageType
    case failedToProcessImage
    
    var errorDescription: String? {
        switch self {
        case .alreadyProcessing:
            return "OCR processing is already in progress"
        case .noImagesSelected:
            return "No images selected for processing"
        case .failedToLoadImage:
            return "Failed to load image"
        case .unsupportedImageType:
            return "Unsupported image type"
        case .failedToProcessImage:
            return "Failed to process image"
        }
    }
}
