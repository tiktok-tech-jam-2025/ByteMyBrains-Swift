//
//  ImageEncryptionManager.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 30/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

import UIKit
import CryptoKit
import Foundation

// MARK: - Encryption Models

struct EncryptedImageData: Codable {
    let version: String = "1.0"
    let timestamp: Date
    let metadata: EncryptionMetadata
    let encryptedRegions: [EncryptedRegion]
    
    struct EncryptionMetadata: Codable {
        let originalImageSize: CGSize
        let totalRegions: Int
        let encryptionMethod: String
        let imageIdentifier: String // To match with blurred image
    }
    
    struct EncryptedRegion: Codable {
        let id: String
        let boundingBox: CGRect
        let encryptedPixelData: Data
        let regionType: String // "text" or "object"
        let sensitivityReason: String?
    }
}

struct DecryptionResult {
    let success: Bool
    let originalImage: UIImage?
    let error: String?
    let regionsDecrypted: Int
}

// MARK: - Image Encryption Manager

class ImageEncryptionManager {
    
    static let shared = ImageEncryptionManager()
    
    // Hardcoded encryption key - same for all encryptions/decryptions
    private let hardcodedPassword = "MySecretKey2025!"
    private let hardcodedSalt = Data([
        0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0,
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
        0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00,
        0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF
    ])
    
    private init() {}
    
    // MARK: - Encryption
    
    func encryptSensitiveRegions(
        originalImage: UIImage,
        ocrResult: OCRResult,
        objectResult: ObjectDetectionResult?
    ) -> (blurredImage: UIImage, encryptedData: Data)? {
        
        print("🔐 Starting encryption process with hardcoded key...")
        
        guard let cgImage = originalImage.cgImage else {
            print("❌ Could not get CGImage from original image")
            return nil
        }
        
        let imageSize = originalImage.size
        var encryptedRegions: [EncryptedImageData.EncryptedRegion] = []
        
        // Use hardcoded key
        guard let encryptionKey = deriveKey() else {
            print("❌ Failed to derive encryption key")
            return nil
        }
        
        // Create blurred image renderer
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        
        let blurredImage = renderer.image { context in
            let cgContext = context.cgContext
            
            // Draw original image as base
            originalImage.draw(at: .zero)
            
            // Process sensitive text regions
            for (index, textBox) in ocrResult.textBoxes.enumerated() {
                if textBox.classification?.isSensitive == true {
                    let rect = VisionCoordinateConverter.convertBoundingBox(textBox.boundingBox, to: imageSize)
                    
                    // Extract and encrypt original pixels
                    if let originalPixels = extractPixels(from: cgImage, rect: rect),
                       let encryptedPixels = encrypt(data: originalPixels, key: encryptionKey) {
                        
                        let encryptedRegion = EncryptedImageData.EncryptedRegion(
                            id: "text_\(index)",
                            boundingBox: textBox.boundingBox, // Keep normalized coordinates
                            encryptedPixelData: encryptedPixels,
                            regionType: "text",
                            sensitivityReason: textBox.classification?.predictedClass
                        )
                        encryptedRegions.append(encryptedRegion)
                    }
                    
                    // Draw blur effect
                    drawBlurEffect(context: cgContext, rect: rect, imageSize: imageSize)
                }
            }
            
            // Process sensitive object regions
            if let objectResult = objectResult {
                for (index, objectBox) in objectResult.objectBoxes.enumerated() {
                    if objectBox.isSensitive {
                        let rect = VisionCoordinateConverter.convertBoundingBox(objectBox.boundingBox, to: imageSize)
                        
                        // Extract and encrypt original pixels
                        if let originalPixels = extractPixels(from: cgImage, rect: rect),
                           let encryptedPixels = encrypt(data: originalPixels, key: encryptionKey) {
                            
                            let encryptedRegion = EncryptedImageData.EncryptedRegion(
                                id: "object_\(index)",
                                boundingBox: objectBox.boundingBox, // Keep normalized coordinates
                                encryptedPixelData: encryptedPixels,
                                regionType: "object",
                                sensitivityReason: objectBox.sensitivityReason
                            )
                            encryptedRegions.append(encryptedRegion)
                        }
                        
                        // Draw blur effect
                        drawBlurEffect(context: cgContext, rect: rect, imageSize: imageSize)
                    }
                }
            }
        }
        
        // Create encrypted data package
        let imageIdentifier = UUID().uuidString
        let encryptedImageData = EncryptedImageData(
            timestamp: Date(),
            metadata: EncryptedImageData.EncryptionMetadata(
                originalImageSize: imageSize,
                totalRegions: encryptedRegions.count,
                encryptionMethod: "AES-GCM-Hardcoded",
                imageIdentifier: imageIdentifier
            ),
            encryptedRegions: encryptedRegions
        )
        
        // Convert to JSON data
        do {
            let jsonData = try JSONEncoder().encode(encryptedImageData)
            print("✅ Encryption complete: \(encryptedRegions.count) regions encrypted")
            return (blurredImage, jsonData)
        } catch {
            print("❌ Failed to encode encrypted data: \(error)")
            return nil
        }
    }
    
    // MARK: - Decryption
    
    func decryptImage(
        blurredImage: UIImage,
        encryptedData: Data
    ) -> DecryptionResult {
        
        print("🔓 Starting decryption process with hardcoded key...")
        
        // Decode encrypted data
        guard let encryptedImageData = try? JSONDecoder().decode(EncryptedImageData.self, from: encryptedData) else {
            return DecryptionResult(success: false, originalImage: nil, error: "Invalid encrypted data format", regionsDecrypted: 0)
        }
        
        // Use hardcoded key
        guard let decryptionKey = deriveKey() else {
            return DecryptionResult(success: false, originalImage: nil, error: "Failed to derive decryption key", regionsDecrypted: 0)
        }
        
        guard let cgImage = blurredImage.cgImage else {
            return DecryptionResult(success: false, originalImage: nil, error: "Invalid blurred image", regionsDecrypted: 0)
        }
        
        let imageSize = encryptedImageData.metadata.originalImageSize
        var decryptedRegions = 0
        
        // Create mutable image context
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        
        let restoredImage = renderer.image { context in
            let cgContext = context.cgContext
            
            // Draw blurred image as base
            blurredImage.draw(at: .zero)
            
            // Decrypt and restore each region
            for region in encryptedImageData.encryptedRegions {
                if let decryptedPixels = decrypt(data: region.encryptedPixelData, key: decryptionKey) {
                    let rect = VisionCoordinateConverter.convertBoundingBox(region.boundingBox, to: imageSize)
                    
                    if restorePixels(decryptedPixels, to: cgContext, rect: rect, imageSize: imageSize) {
                        decryptedRegions += 1
                        print("✅ Decrypted region: \(region.id) (\(region.regionType))")
                    } else {
                        print("❌ Failed to restore pixels for region: \(region.id)")
                    }
                } else {
                    print("❌ Failed to decrypt region: \(region.id)")
                }
            }
        }
        
        let success = decryptedRegions == encryptedImageData.encryptedRegions.count
        
        if success {
            print("🎉 Decryption complete: \(decryptedRegions)/\(encryptedImageData.encryptedRegions.count) regions restored")
        } else {
            print("⚠️ Partial decryption: \(decryptedRegions)/\(encryptedImageData.encryptedRegions.count) regions restored")
        }
        
        return DecryptionResult(
            success: success,
            originalImage: restoredImage,
            error: success ? nil : "Some regions could not be decrypted",
            regionsDecrypted: decryptedRegions
        )
    }
    
    // MARK: - Helper Methods
    
    private func deriveKey() -> SymmetricKey? {
        guard let passwordData = hardcodedPassword.data(using: .utf8) else { return nil }
        
        let inputKeyMaterial = SymmetricKey(data: passwordData)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: hardcodedSalt,
            info: Data("ImageEncryption".utf8),
            outputByteCount: 32
        )
        
        return derivedKey
    }
    
    private func encrypt(data: Data, key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            print("❌ Encryption failed: \(error)")
            return nil
        }
    }
    
    private func decrypt(data: Data, key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            print("❌ Decryption failed: \(error)")
            return nil
        }
    }
    
    private func extractPixels(from cgImage: CGImage, rect: CGRect) -> Data? {
        let expandedRect = rect.insetBy(dx: -2, dy: -2)
        
        guard expandedRect.origin.x >= 0,
              expandedRect.origin.y >= 0,
              expandedRect.maxX <= CGFloat(cgImage.width),
              expandedRect.maxY <= CGFloat(cgImage.height) else {
            let clampedRect = CGRect(
                x: max(0, rect.origin.x),
                y: max(0, rect.origin.y),
                width: min(rect.width, CGFloat(cgImage.width) - max(0, rect.origin.x)),
                height: min(rect.height, CGFloat(cgImage.height) - max(0, rect.origin.y))
            )
            return extractPixels(from: cgImage, rect: clampedRect)
        }
        
        let intRect = CGRect(
            x: Int(expandedRect.origin.x),
            y: Int(expandedRect.origin.y),
            width: Int(expandedRect.width),
            height: Int(expandedRect.height)
        )
        
        guard let croppedImage = cgImage.cropping(to: intRect) else {
            print("❌ Failed to crop image")
            return nil
        }
        
        let width = croppedImage.width
        let height = croppedImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var pixelData = Data(count: totalBytes)
        
        let success = pixelData.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return false }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return false }
            
            context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        
        return success ? pixelData : nil
    }
    
    private func restorePixels(_ pixelData: Data, to context: CGContext, rect: CGRect, imageSize: CGSize) -> Bool {
        let expandedRect = rect.insetBy(dx: -2, dy: -2)
        
        let width = Int(expandedRect.width)
        let height = Int(expandedRect.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        guard pixelData.count >= height * bytesPerRow else {
            print("❌ Pixel data size mismatch")
            return false
        }
        
        return pixelData.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return false }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            
            guard let pixelContext = CGContext(
                data: UnsafeMutableRawPointer(mutating: baseAddress),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ),
            let restoredImage = pixelContext.makeImage() else { return false }
            
            context.draw(restoredImage, in: expandedRect)
            return true
        }
    }
    
    private func drawBlurEffect(context: CGContext, rect: CGRect, imageSize: CGSize) {
        let pixelSize: CGFloat = 8.0
        let expandedRect = rect.insetBy(dx: -2, dy: -2)
        
        context.saveGState()
        
        let rows = Int(expandedRect.height / pixelSize) + 1
        let cols = Int(expandedRect.width / pixelSize) + 1
        
        for row in 0..<rows {
            for col in 0..<cols {
                let pixelRect = CGRect(
                    x: expandedRect.origin.x + CGFloat(col) * pixelSize,
                    y: expandedRect.origin.y + CGFloat(row) * pixelSize,
                    width: pixelSize,
                    height: pixelSize
                )
                
                let grayValue = CGFloat.random(in: 0.7...0.9)
                context.setFillColor(UIColor(white: grayValue, alpha: 0.9).cgColor)
                context.fill(pixelRect)
            }
        }
        
        context.restoreGState()
    }
}
