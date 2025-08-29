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
        let itemProvider = pickerResult.itemProvider
        
        guard itemProvider.canLoadObject(ofClass: UIImage.self) else {
            let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: 0, error: OCRError.unsupportedImageType)
            completion(result)
            return
        }
        
        itemProvider.loadObject(ofClass: UIImage.self) { [weak self] (image: NSItemProviderReading?, error: Error?) in
            guard let self = self else { return }
            
            if let error = error {
                let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: 0, error: error)
                completion(result)
                return
            }
            
            guard let uiImage = image as? UIImage else {
                let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: 0, error: OCRError.failedToLoadImage)
                completion(result)
                return
            }
            
            self.performOCR(on: uiImage, identifier: identifier, completion: completion)
        }
    }
    
    private func performOCR(on image: UIImage, identifier: String, completion: @escaping (OCRResult) -> Void) {
        guard let cgImage = image.cgImage else {
            let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: 0, error: OCRError.failedToProcessImage)
            completion(result)
            return
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create text recognition request
        let request = VNRecognizeTextRequest { [weak self] request, error in
            self?.handleTextRecognitionResults(request: request, error: error, identifier: identifier, startTime: startTime, completion: completion)
        }
        
        // Configure the request based on the current configuration
        configureRequest(request, with: configuration)
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
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
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        if let error = error {
            let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: processingTime, error: error)
            completion(result)
            return
        }
        
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            let result = OCRResult(assetIdentifier: identifier, textBoxes: [], processingTime: processingTime, error: OCRError.failedToProcessImage)
            completion(result)
            return
        }
        
        var textBoxes: [TextBoundingBox] = []
        
        for observation in observations {
            // Get the top candidate for recognized text
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            
            // Create bounding box with the recognized text
            let textBox = TextBoundingBox(
                text: topCandidate.string,
                boundingBox: observation.boundingBox,
                confidence: topCandidate.confidence,
                assetIdentifier: identifier
            )
            textBoxes.append(textBox)
        }
        
        let result = OCRResult(assetIdentifier: identifier, textBoxes: textBoxes, processingTime: processingTime, error: nil)
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
