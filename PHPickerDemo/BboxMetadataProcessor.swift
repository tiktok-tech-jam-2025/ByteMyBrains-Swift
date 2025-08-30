//
//  BboxMetadataProcessor.swift
//  PHPickerDemo
//
//  Created by GitHub Copilot on 30/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

/*
BboxMetadataProcessor.swift
Handles extraction of bounding box coordinates and pixel data for PII-labeled regions.
*/

import UIKit
import CoreGraphics
import PhotosUI

// MARK: - Bounding Box Metadata Models

struct PIIBoundingBox {
    let coordinates: BoundingBoxCoordinates
    let pixelData: PixelData
    let assetIdentifier: String
    let text: String?
    
    init(coordinates: BoundingBoxCoordinates, 
         pixelData: PixelData, 
         assetIdentifier: String, 
         text: String? = nil) {
        self.coordinates = coordinates
        self.pixelData = pixelData
        self.assetIdentifier = assetIdentifier
        self.text = text
    }
}

struct BoundingBoxCoordinates {
    let normalizedRect: CGRect  // Vision framework normalized coordinates (0-1)
    let pixelRect: CGRect       // Actual pixel coordinates
    let imageSize: CGSize       // Original image dimensions
    
    init(normalizedRect: CGRect, imageSize: CGSize) {
        self.normalizedRect = normalizedRect
        self.imageSize = imageSize
        
        // Convert normalized coordinates to pixel coordinates
        self.pixelRect = CGRect(
            x: normalizedRect.origin.x * imageSize.width,
            y: (1 - normalizedRect.origin.y - normalizedRect.height) * imageSize.height, // Vision uses bottom-left origin
            width: normalizedRect.width * imageSize.width,
            height: normalizedRect.height * imageSize.height
        )
    }
}

struct PixelData {
    let rgba: [UInt8]           // RGBA pixel values
    let width: Int              // Width of extracted region
    let height: Int             // Height of extracted region
    let bytesPerPixel: Int      // Typically 4 for RGBA
    let bytesPerRow: Int        // Row stride
    
    var totalBytes: Int {
        return rgba.count
    }
}

struct BboxMetadataResult {
    let assetIdentifier: String
    let piiBoundingBoxes: [PIIBoundingBox]
    let processingTime: TimeInterval
    let originalImageSize: CGSize
    let error: Error?
    
    var piiCount: Int {
        return piiBoundingBoxes.count
    }
    
    var totalPixelDataSize: Int {
        return piiBoundingBoxes.reduce(0) { $0 + $1.pixelData.totalBytes }
    }
}

// MARK: - Bounding Box Metadata Processor Delegate

protocol BboxMetadataProcessorDelegate: AnyObject {
    func bboxProcessor(_ processor: BboxMetadataProcessor, didStartProcessing totalImages: Int)
    func bboxProcessor(_ processor: BboxMetadataProcessor, didProcessImage at: Int, of: Int)
    func bboxProcessor(_ processor: BboxMetadataProcessor, didCompleteWithResults results: [BboxMetadataResult])
    func bboxProcessor(_ processor: BboxMetadataProcessor, didFailWithError error: Error)
}

// MARK: - Bounding Box Metadata Processor

class BboxMetadataProcessor {
    
    weak var delegate: BboxMetadataProcessorDelegate?
    private var isProcessing = false
    
    // MARK: - Public Methods
    
    /// Extract PII bounding box metadata from OCR results
    func extractPIIMetadata(from ocrResults: [OCRResult], selection: [String: PHPickerResult]) {
        guard !isProcessing else {
            delegate?.bboxProcessor(self, didFailWithError: BboxMetadataError.alreadyProcessing)
            return
        }
        
        guard !ocrResults.isEmpty else {
            delegate?.bboxProcessor(self, didFailWithError: BboxMetadataError.noResultsProvided)
            return
        }
        
        isProcessing = true
        delegate?.bboxProcessor(self, didStartProcessing: ocrResults.count)
        
        print("🚀 Starting PII metadata extraction for \(ocrResults.count) images")
        
        processResultsSequentially(ocrResults: ocrResults, selection: selection, currentIndex: 0, results: [])
    }
    
    /// Extract PII metadata from object detection results
    func extractPIIMetadata(from objectResults: [Any], selection: [String: PHPickerResult]) {
        // TODO: Implement when ObjectDetectionResult structure is available
        print("🔄 Object detection metadata extraction not yet implemented")
        delegate?.bboxProcessor(self, didFailWithError: BboxMetadataError.notImplemented)
    }
    
    func cancelProcessing() {
        isProcessing = false
        print("🛑 PII metadata extraction cancelled")
    }
    
    // MARK: - Private Methods
    
    private func processResultsSequentially(ocrResults: [OCRResult], 
                                          selection: [String: PHPickerResult], 
                                          currentIndex: Int, 
                                          results: [BboxMetadataResult]) {
        guard isProcessing && currentIndex < ocrResults.count else {
            isProcessing = false
            if currentIndex >= ocrResults.count {
                print("🎉 PII metadata extraction completed for all \(ocrResults.count) images")
                delegate?.bboxProcessor(self, didCompleteWithResults: results)
            }
            return
        }
        
        let ocrResult = ocrResults[currentIndex]
        delegate?.bboxProcessor(self, didProcessImage: currentIndex + 1, of: ocrResults.count)
        
        guard let pickerResult = selection[ocrResult.assetIdentifier] else {
            let errorResult = BboxMetadataResult(
                assetIdentifier: ocrResult.assetIdentifier,
                piiBoundingBoxes: [],
                processingTime: 0,
                originalImageSize: .zero,
                error: BboxMetadataError.failedToLoadImage
            )
            processNext(ocrResults: ocrResults, selection: selection, currentIndex: currentIndex, results: results + [errorResult])
            return
        }
        
        extractMetadataFromOCRResult(ocrResult: ocrResult, pickerResult: pickerResult) { [weak self] result in
            guard let self = self else { return }
            self.processNext(ocrResults: ocrResults, selection: selection, currentIndex: currentIndex, results: results + [result])
        }
    }
    
    private func processNext(ocrResults: [OCRResult], selection: [String: PHPickerResult], currentIndex: Int, results: [BboxMetadataResult]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.processResultsSequentially(ocrResults: ocrResults, selection: selection, currentIndex: currentIndex + 1, results: results)
        }
    }
    
    private func extractMetadataFromOCRResult(ocrResult: OCRResult, pickerResult: PHPickerResult, completion: @escaping (BboxMetadataResult) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Filter for PII text boxes only
        let piiTextBoxes = ocrResult.textBoxes.filter { $0.classification?.isSensitive == true }
        
        guard !piiTextBoxes.isEmpty else {
            let result = BboxMetadataResult(
                assetIdentifier: ocrResult.assetIdentifier,
                piiBoundingBoxes: [],
                processingTime: CFAbsoluteTimeGetCurrent() - startTime,
                originalImageSize: .zero,
                error: nil
            )
            completion(result)
            return
        }
        
        print("🔍 Extracting metadata for \(piiTextBoxes.count) PII regions in \(ocrResult.assetIdentifier)")
        
        loadImageAndExtractPixelData(pickerResult: pickerResult, piiTextBoxes: piiTextBoxes, assetIdentifier: ocrResult.assetIdentifier, startTime: startTime, completion: completion)
    }
    
    private func loadImageAndExtractPixelData(pickerResult: PHPickerResult, 
                                            piiTextBoxes: [TextBoundingBox], 
                                            assetIdentifier: String, 
                                            startTime: CFAbsoluteTime,
                                            completion: @escaping (BboxMetadataResult) -> Void) {
        let itemProvider = pickerResult.itemProvider
        
        guard itemProvider.canLoadObject(ofClass: UIImage.self) else {
            let result = BboxMetadataResult(
                assetIdentifier: assetIdentifier,
                piiBoundingBoxes: [],
                processingTime: CFAbsoluteTimeGetCurrent() - startTime,
                originalImageSize: .zero,
                error: BboxMetadataError.unsupportedImageType
            )
            completion(result)
            return
        }
        
        itemProvider.loadObject(ofClass: UIImage.self) { [weak self] (image: NSItemProviderReading?, error: Error?) in
            guard let self = self else { return }
            
            if let error = error {
                let result = BboxMetadataResult(
                    assetIdentifier: assetIdentifier,
                    piiBoundingBoxes: [],
                    processingTime: CFAbsoluteTimeGetCurrent() - startTime,
                    originalImageSize: .zero,
                    error: error
                )
                completion(result)
                return
            }
            
            guard let uiImage = image as? UIImage else {
                let result = BboxMetadataResult(
                    assetIdentifier: assetIdentifier,
                    piiBoundingBoxes: [],
                    processingTime: CFAbsoluteTimeGetCurrent() - startTime,
                    originalImageSize: .zero,
                    error: BboxMetadataError.failedToLoadImage
                )
                completion(result)
                return
            }
            
            self.extractPixelDataFromImage(uiImage: uiImage, piiTextBoxes: piiTextBoxes, assetIdentifier: assetIdentifier, startTime: startTime, completion: completion)
        }
    }
    
    private func extractPixelDataFromImage(uiImage: UIImage, 
                                         piiTextBoxes: [TextBoundingBox], 
                                         assetIdentifier: String, 
                                         startTime: CFAbsoluteTime,
                                         completion: @escaping (BboxMetadataResult) -> Void) {
        guard let cgImage = uiImage.cgImage else {
            let result = BboxMetadataResult(
                assetIdentifier: assetIdentifier,
                piiBoundingBoxes: [],
                processingTime: CFAbsoluteTimeGetCurrent() - startTime,
                originalImageSize: uiImage.size,
                error: BboxMetadataError.failedToProcessImage
            )
            completion(result)
            return
        }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        var piiBoundingBoxes: [PIIBoundingBox] = []
        
        for textBox in piiTextBoxes {
            guard let classification = textBox.classification else { continue }
            
            let coordinates = BoundingBoxCoordinates(normalizedRect: textBox.boundingBox, imageSize: imageSize)
            
            if let pixelData = extractPixelData(from: cgImage, rect: coordinates.pixelRect) {
                let piiBbox = PIIBoundingBox(
                    coordinates: coordinates,
                    pixelData: pixelData,
                    assetIdentifier: assetIdentifier,
                    text: textBox.text
                )
                piiBoundingBoxes.append(piiBbox)
                
                print("📦 Extracted \(pixelData.totalBytes) bytes for PII region: '\(textBox.text)'")
            }
        }
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        let result = BboxMetadataResult(
            assetIdentifier: assetIdentifier,
            piiBoundingBoxes: piiBoundingBoxes,
            processingTime: processingTime,
            originalImageSize: uiImage.size,
            error: nil
        )
        
        print("🎉 Metadata extraction completed for \(assetIdentifier):")
        print("   - PII regions: \(piiBoundingBoxes.count)")
        print("   - Total pixel data: \(result.totalPixelDataSize) bytes")
        print("   - Processing time: \(String(format: "%.3f", processingTime))s")
        
        completion(result)
    }
    
    private func extractPixelData(from cgImage: CGImage, rect: CGRect) -> PixelData? {
        let clampedRect = rect.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        guard !clampedRect.isEmpty else {
            print("⚠️ Bounding box is outside image bounds")
            return nil
        }
        
        let width = Int(clampedRect.width)
        let height = Int(clampedRect.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("❌ Failed to create CGContext for pixel extraction")
            return nil
        }
        
        // Draw the cropped region
        context.draw(cgImage, in: CGRect(x: Int(-clampedRect.origin.x), y: Int(-clampedRect.origin.y), width: cgImage.width, height: cgImage.height))
        
        guard let data = context.data else {
            print("❌ Failed to get pixel data from context")
            return nil
        }
        
        let pixelCount = width * height * bytesPerPixel
        let rgba = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: pixelCount))
        
        return PixelData(
            rgba: rgba,
            width: width,
            height: height,
            bytesPerPixel: bytesPerPixel,
            bytesPerRow: bytesPerRow
        )
    }
}

// MARK: - Bounding Box Metadata Errors

enum BboxMetadataError: LocalizedError {
    case alreadyProcessing
    case noResultsProvided
    case failedToLoadImage
    case unsupportedImageType
    case failedToProcessImage
    case notImplemented
    
    var errorDescription: String? {
        switch self {
        case .alreadyProcessing:
            return "Metadata extraction is already in progress"
        case .noResultsProvided:
            return "No OCR or detection results provided"
        case .failedToLoadImage:
            return "Failed to load image for metadata extraction"
        case .unsupportedImageType:
            return "Unsupported image type for metadata extraction"
        case .failedToProcessImage:
            return "Failed to process image for metadata extraction"
        case .notImplemented:
            return "Feature not yet implemented"
        }
    }
}

// MARK: - Utility Extensions

extension PIIBoundingBox {
    var debugDescription: String {
        return """
        PIIBoundingBox:
        - Text: "\(text ?? "N/A")"
        - Coordinates: \(coordinates.pixelRect)
        - Pixel Data: \(pixelData.width)x\(pixelData.height) (\(pixelData.totalBytes) bytes)
        """
    }
}
