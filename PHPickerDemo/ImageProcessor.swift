//
//  ImageProcessor.swift
//  PHPickerDemo
//
//  Created by GitHub Copilot on 30/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

/*
ImageProcessor.swift
Handles image manipulation operations including blurring PII regions and reconstructing
original images from encrypted metadata.
*/

import UIKit
import CoreGraphics

// MARK: - Image Processing Models

struct BlurredImagePackage {
    let blurredImage: UIImage
    let encryptedPackage: SecureMetadataPackage
    let originalImageSize: CGSize
    let blurMethod: BlurMethod
    let packagedAt: Date
    
    init(blurredImage: UIImage, encryptedPackage: SecureMetadataPackage, originalImageSize: CGSize, blurMethod: BlurMethod = .gaussian) {
        self.blurredImage = blurredImage
        self.encryptedPackage = encryptedPackage
        self.originalImageSize = originalImageSize
        self.blurMethod = blurMethod
        self.packagedAt = Date()
    }
}

enum BlurMethod {
    case gaussian
    case pixelate
    case solid
    case blackout
    
    var description: String {
        switch self {
        case .gaussian: return "Gaussian Blur"
        case .pixelate: return "Pixelation"
        case .solid: return "Solid Color"
        case .blackout: return "Black Rectangle"
        }
    }
}

// MARK: - Image Processor

class ImageProcessor {
    
    static let shared = ImageProcessor()
    private let cryptoManager = CryptographyManager.shared
    
    private init() {}
    
    // MARK: - Alice (Sender) Operations
    
    /// Alice: Create blurred image with encrypted metadata package
    func createBlurredImagePackage(originalImage: UIImage, 
                                 bboxResult: BboxMetadataResult, 
                                 imageKey: ImageKey,
                                 blurMethod: BlurMethod = .gaussian) throws -> BlurredImagePackage {
        
        print("🖼️ Alice: Creating blurred image package with \(bboxResult.piiBoundingBoxes.count) PII regions")
        
        // Create blurred version of image
        let blurredImage = try applyBlurToPIIRegions(
            image: originalImage, 
            bboxResult: bboxResult,
            method: blurMethod
        )
        
        // Encrypt the PII metadata
        let encryptedPackage = try cryptoManager.encryptImageMetadata(bboxResult, using: imageKey)
        
        let package = BlurredImagePackage(
            blurredImage: blurredImage,
            encryptedPackage: encryptedPackage,
            originalImageSize: originalImage.size,
            blurMethod: blurMethod
        )
        
        print("📦 Alice: Created blurred image package - \(encryptedPackage.encryptedBoundingBoxes.count) encrypted regions")
        return package
    }
    
    // MARK: - Bob (Receiver) Operations
    
    /// Bob: Reconstruct original image from blurred image + encrypted metadata
    func reconstructOriginalImage(from package: BlurredImagePackage) throws -> UIImage {
        
        print("🎨 Bob: Reconstructing original image from blurred version + encrypted metadata")
        
        // Decrypt the PII metadata
        let decryptedBoundingBoxes = try cryptoManager.decryptImageMetadata(package.encryptedPackage)
        
        // Apply the decrypted pixel data back to the blurred image
        let reconstructedImage = try applyDecryptedPixelData(
            to: package.blurredImage, 
            boundingBoxes: decryptedBoundingBoxes
        )
        
        print("✅ Bob: Successfully reconstructed original image with \(decryptedBoundingBoxes.count) PII regions")
        return reconstructedImage
    }
    
    /// Bob: Reconstruct original image from separate components
    func reconstructOriginalImage(blurredImage: UIImage, 
                                encryptedPackage: SecureMetadataPackage) throws -> UIImage {
        
        let package = BlurredImagePackage(
            blurredImage: blurredImage,
            encryptedPackage: encryptedPackage,
            originalImageSize: blurredImage.size
        )
        
        return try reconstructOriginalImage(from: package)
    }
    
    // MARK: - Image Blurring Methods
    
    private func applyBlurToPIIRegions(image: UIImage, 
                                     bboxResult: BboxMetadataResult,
                                     method: BlurMethod) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw ImageProcessorError.invalidImage("Cannot get CGImage from UIImage")
        }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            throw ImageProcessorError.contextCreationFailed("Failed to create graphics context")
        }
        
        // Draw original image
        context.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))
        
        // Apply blur to PII regions
        for piiBbox in bboxResult.piiBoundingBoxes {
            let rect = piiBbox.coordinates.pixelRect
            try applyBlur(to: context, rect: rect, method: method)
        }
        
        guard let blurredImage = UIGraphicsGetImageFromCurrentImageContext() else {
            throw ImageProcessorError.imageCreationFailed("Failed to create blurred image")
        }
        
        print("🔒 Applied \(method.description) to \(bboxResult.piiBoundingBoxes.count) PII regions")
        return blurredImage
    }
    
    private func applyBlur(to context: CGContext, rect: CGRect, method: BlurMethod) throws {
        switch method {
        case .gaussian:
            // For now, use solid gray - Gaussian blur would require Core Image
            context.setFillColor(UIColor.systemGray3.cgColor)
            context.fill(rect)
            
        case .pixelate:
            // Create pixelated effect
            let pixelSize: CGFloat = 10
            context.setFillColor(UIColor.systemGray3.cgColor)
            
            let rows = Int(rect.height / pixelSize)
            let cols = Int(rect.width / pixelSize)
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let pixelRect = CGRect(
                        x: rect.origin.x + CGFloat(col) * pixelSize,
                        y: rect.origin.y + CGFloat(row) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(pixelRect)
                }
            }
            
        case .solid:
            context.setFillColor(UIColor.systemGray.cgColor)
            context.fill(rect)
            
        case .blackout:
            context.setFillColor(UIColor.black.cgColor)
            context.fill(rect)
        }
    }
    
    // MARK: - Image Reconstruction Methods
    
    private func applyDecryptedPixelData(to blurredImage: UIImage, 
                                       boundingBoxes: [PIIBoundingBox]) throws -> UIImage {
        guard let cgImage = blurredImage.cgImage else {
            throw ImageProcessorError.invalidImage("Invalid blurred image")
        }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            throw ImageProcessorError.contextCreationFailed("Failed to create graphics context")
        }
        
        // Draw blurred image as base
        context.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))
        
        // Restore original pixel data to PII regions
        for piiBbox in boundingBoxes {
            try restorePixelDataToRegion(context: context, piiBoundingBox: piiBbox)
        }
        
        guard let reconstructedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            throw ImageProcessorError.imageCreationFailed("Failed to reconstruct image")
        }
        
        return reconstructedImage
    }
    
    private func restorePixelDataToRegion(context: CGContext, piiBoundingBox: PIIBoundingBox) throws {
        let rect = piiBoundingBox.coordinates.pixelRect
        let pixelData = piiBoundingBox.pixelData
        
        // Create CGImage from pixel data
        guard let dataProvider = CGDataProvider(data: Data(pixelData.rgba) as CFData),
              let restoredImage = CGImage(
                width: pixelData.width,
                height: pixelData.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: pixelData.bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: dataProvider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw ImageProcessorError.pixelDataRestoration("Failed to create image from pixel data")
        }
        
        // Draw the restored pixels back to the context
        context.draw(restoredImage, in: rect)
    }
    
    // MARK: - Utility Methods
    
    /// Validate image dimensions and format
    func validateImage(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        return cgImage.width > 0 && cgImage.height > 0
    }
    
    /// Get image processing statistics
    func getProcessingInfo(for package: BlurredImagePackage) -> String {
        let originalSize = package.originalImageSize
        let blurredSize = package.blurredImage.size
        let piiCount = package.encryptedPackage.encryptedBoundingBoxes.count
        
        return """
        Image Processing Info:
        - Original Size: \(Int(originalSize.width))x\(Int(originalSize.height))
        - Blurred Size: \(Int(blurredSize.width))x\(Int(blurredSize.height))
        - PII Regions: \(piiCount)
        - Blur Method: \(package.blurMethod.description)
        - Processed: \(package.packagedAt)
        """
    }
}

// MARK: - Image Processor Errors

enum ImageProcessorError: LocalizedError {
    case invalidImage(String)
    case contextCreationFailed(String)
    case imageCreationFailed(String)
    case pixelDataRestoration(String)
    case unsupportedBlurMethod
    
    var errorDescription: String? {
        switch self {
        case .invalidImage(let message):
            return "Invalid image: \(message)"
        case .contextCreationFailed(let message):
            return "Context creation failed: \(message)"
        case .imageCreationFailed(let message):
            return "Image creation failed: \(message)"
        case .pixelDataRestoration(let message):
            return "Pixel data restoration failed: \(message)"
        case .unsupportedBlurMethod:
            return "Unsupported blur method"
        }
    }
}

// MARK: - Debug Extensions

extension BlurredImagePackage {
    var debugDescription: String {
        return """
        BlurredImagePackage:
        - Asset ID: \(encryptedPackage.assetIdentifier)
        - Original Size: \(Int(originalImageSize.width))x\(Int(originalImageSize.height))
        - Blurred Size: \(Int(blurredImage.size.width))x\(Int(blurredImage.size.height))
        - PII Regions: \(encryptedPackage.encryptedBoundingBoxes.count)
        - Blur Method: \(blurMethod.description)
        - Image Key ID: \(encryptedPackage.imageKeyIdentifier)
        - Packaged: \(packagedAt)
        """
    }
}
