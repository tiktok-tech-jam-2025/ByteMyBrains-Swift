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
}

struct OCRResult {
    let assetIdentifier: String
    let textBoxes: [TextBoundingBox]
    let processingTime: TimeInterval
    let error: Error?
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
        
        processImagesSequentially(selection: selection, identifiers: imageIdentifiers, currentIndex: 0, results: [])
    }
    
    func cancelProcessing() {
        isProcessing = false
    }
    
    // MARK: - Private Methods
    
    private func processImagesSequentially(selection: [String: PHPickerResult],
                                         identifiers: [String],
                                         currentIndex: Int,
                                         results: [OCRResult]) {
        guard isProcessing && currentIndex < identifiers.count else {
            isProcessing = false
            if currentIndex >= identifiers.count {
                delegate?.ocrProcessor(self, didCompleteWithResults: results)
            }
            return
        }
        
        let identifier = identifiers[currentIndex]
        delegate?.ocrProcessor(self, didProcessImage: currentIndex + 1, of: identifiers.count)
        
        guard let pickerResult = selection[identifier] else {
            let errorResult = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: 0, error: OCRError.failedToLoadImage)
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
            let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: 0, error: OCRError.unsupportedImageType)
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
                let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: 0, error: error)
                completion(result)
                return
            }
            
            guard let uiImage = image as? UIImage else {
                print("❌ Could not cast loaded object to UIImage for \(identifier)")
                let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: 0, error: OCRError.failedToLoadImage)
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
            let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: 0, error: OCRError.failedToProcessImage)
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
                let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: 0, error: error)
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
    

    private func handleTextRecognitionResults(request: VNRequest, error: Error?, identifier: String, startTime: CFAbsoluteTime, completion: @escaping (OCRResult) -> Void) {
        print("🔍 handleTextRecognitionResults called for \(identifier)")
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ Processing time: \(processingTime)s")
        
        if let error = error {
            print("❌ OCR Error in handleTextRecognitionResults: \(error)")
            let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: processingTime, error: error)
            completion(result)
            return
        }
        
        print("📊 Request results type: \(type(of: request.results))")
        print("📊 Request results count: \(request.results?.count ?? -1)")
        
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            print("❌ Could not cast request.results to [VNRecognizedTextObservation]")
            print("📋 Actual results: \(request.results?.description ?? "nil")")
            let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: processingTime, error: OCRError.failedToProcessImage)
            completion(result)
            return
        }
        
        print("✅ Got \(observations.count) VNRecognizedTextObservation objects")
        
        var textBoxes: [TextBoundingBox] = []
        
        for (index, observation) in observations.enumerated() {
            print("📝 Processing observation \(index + 1) of \(observations.count)")
            
            // Get the top candidate for recognized text
            guard let topCandidate = observation.topCandidates(1).first else {
                print("⚠️ No top candidate for observation \(index + 1)")
                continue
            }
            
            print("✅ Found text: '\(topCandidate.string)' (confidence: \(topCandidate.confidence))")
            
            // Create bounding box with the recognized text
            let textBox = TextBoundingBox(
                text: topCandidate.string,
                boundingBox: observation.boundingBox,
                confidence: topCandidate.confidence,
                assetIdentifier: identifier
            )
            textBoxes.append(textBox)
        }
        
        print("🎉 Created \(textBoxes.count) text boxes for \(identifier)")
        let result = OCRResult(assetIdentifier: identifier, textBoxes: textBoxes, processingTime: processingTime, error: nil)
        print("📤 About to call completion with result")
        completion(result)
        print("✅ Completion called for \(identifier)")
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
