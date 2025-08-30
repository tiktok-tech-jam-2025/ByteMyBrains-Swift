//
//  SecurePIIManager.swift
//  PHPickerDemo
//
//  Created by GitHub Copilot on 30/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

/*
SecurePIIManager.swift
High-level manager that orchestrates the complete Alice-Bob workflow for secure PII handling.
Provides easy-to-use APIs for both sender (Alice) and receiver (Bob) operations.
*/

import UIKit
import PhotosUI

// MARK: - Secure PII Models

struct AlicePackage {
    let blurredImagePackage: BlurredImagePackage
    let encryptedImageKey: Data
    let senderKeyPairTag: String
    let receiverPublicKeyTag: String
    
    init(blurredImagePackage: BlurredImagePackage, encryptedImageKey: Data, senderKeyPairTag: String, receiverPublicKeyTag: String) {
        self.blurredImagePackage = blurredImagePackage
        self.encryptedImageKey = encryptedImageKey
        self.senderKeyPairTag = senderKeyPairTag
        self.receiverPublicKeyTag = receiverPublicKeyTag
    }
}

struct TransmissionPackage: Codable {
    let blurredImageData: Data
    let encryptedMetadata: Data
    let encryptedImageKey: Data
    let assetIdentifier: String
    let encryptionScheme: String
    let transmissionDate: Date
    
    init(blurredImageData: Data, encryptedMetadata: Data, encryptedImageKey: Data, assetIdentifier: String) {
        self.blurredImageData = blurredImageData
        self.encryptedMetadata = encryptedMetadata
        self.encryptedImageKey = encryptedImageKey
        self.assetIdentifier = assetIdentifier
        self.encryptionScheme = "RSA-2048+AES-GCM-256"
        self.transmissionDate = Date()
    }
}

// MARK: - Secure PII Manager Delegate

protocol SecurePIIManagerDelegate: AnyObject {
    func securePIIManager(_ manager: SecurePIIManager, didStartProcessing operation: SecurePIIOperation)
    func securePIIManager(_ manager: SecurePIIManager, didComplete operation: SecurePIIOperation, result: Any)
    func securePIIManager(_ manager: SecurePIIManager, didFail operation: SecurePIIOperation, error: Error)
    func securePIIManager(_ manager: SecurePIIManager, didUpdateProgress operation: SecurePIIOperation, progress: Float)
}

enum SecurePIIOperation {
    case aliceProcessing
    case bobDecryption
    case keyGeneration
    case imageReconstruction
    
    var description: String {
        switch self {
        case .aliceProcessing: return "Alice: Processing and encrypting PII"
        case .bobDecryption: return "Bob: Decrypting and reconstructing"
        case .keyGeneration: return "Generating cryptographic keys"
        case .imageReconstruction: return "Reconstructing original image"
        }
    }
}

// MARK: - Secure PII Manager

class SecurePIIManager {
    
    static let shared = SecurePIIManager()
    
    weak var delegate: SecurePIIManagerDelegate?
    
    private let cryptoManager = CryptographyManager.shared
    private let imageProcessor = ImageProcessor.shared
    private let bboxProcessor = BboxMetadataProcessor()
    private let ocrProcessor = OCRProcessor()
    
    private var isProcessing = false
    private var pendingProcessingParams: (receiverPublicKey: SecKey, blurMethod: BlurMethod)?
    
    private init() {
        bboxProcessor.delegate = self
    }
    
    // MARK: - Alice (Sender) Operations
    
    /// Alice: Complete workflow - OCR, encrypt, and prepare for transmission
    func aliceProcessImages(_ selection: [String: PHPickerResult], 
                          receiverPublicKey: SecKey,
                          blurMethod: BlurMethod = .gaussian) {
        
        guard !isProcessing else {
            delegate?.securePIIManager(self, didFail: .aliceProcessing, error: SecurePIIError.operationInProgress)
            return
        }
        
        isProcessing = true
        delegate?.securePIIManager(self, didStartProcessing: .aliceProcessing)
        
        print("🚀 Alice: Starting secure PII processing for \(selection.count) images")
        
        // Set up OCR processor delegate to handle results
        ocrProcessor.delegate = self
        
        // Start OCR processing
        ocrProcessor.processImages(from: selection)
        
        // Store the processing parameters for later use in delegate callback
        self.pendingProcessingParams = (receiverPublicKey, blurMethod)
    }
    
    /// Alice: Process OCR results and create secure packages
    private func processOCRResults(_ ocrResults: [OCRResult], 
                                 receiverPublicKey: SecKey,
                                 blurMethod: BlurMethod) throws -> [AlicePackage] {
        
        var alicePackages: [AlicePackage] = []
        
        // Generate Alice's key pair if not exists
        let aliceKeyPair = try cryptoManager.generateRSAKeyPair(tag: "alice-keypair")
        
        for ocrResult in ocrResults {
            // Generate unique image key for this image
            let imageKey = cryptoManager.generateImageKey()
            
            // Create mock BboxMetadataResult from OCR (in real implementation, this would come from BboxMetadataProcessor)
            let bboxResult = createBboxResultFromOCR(ocrResult)
            
            // Create blurred image package
            guard let originalImage = try? loadImageFromOCRResult(ocrResult) else {
                print("⚠️ Failed to load image for \(ocrResult.assetIdentifier)")
                continue
            }
            
            let blurredPackage = try imageProcessor.createBlurredImagePackage(
                originalImage: originalImage,
                bboxResult: bboxResult,
                imageKey: imageKey,
                blurMethod: blurMethod
            )
            
            // Encrypt image key for Bob
            let encryptedImageKey = try cryptoManager.encryptImageKeyForTransmission(
                imageKey,
                usingPublicKey: receiverPublicKey
            )
            
            let alicePackage = AlicePackage(
                blurredImagePackage: blurredPackage,
                encryptedImageKey: encryptedImageKey,
                senderKeyPairTag: "alice-keypair",
                receiverPublicKeyTag: "receiver-public"
            )
            
            alicePackages.append(alicePackage)
        }
        
        print("📦 Alice: Created \(alicePackages.count) secure packages for transmission")
        return alicePackages
    }
    
    /// Alice: Create transmission package for network sending
    func createTransmissionPackage(from alicePackage: AlicePackage) throws -> TransmissionPackage {
        
        // Convert blurred image to data
        guard let blurredImageData = alicePackage.blurredImagePackage.blurredImage.pngData() else {
            throw SecurePIIError.imageConversionFailed
        }
        
        // Serialize encrypted metadata
        let encryptedMetadata = try JSONEncoder().encode(alicePackage.blurredImagePackage.encryptedPackage)
        
        let transmissionPackage = TransmissionPackage(
            blurredImageData: blurredImageData,
            encryptedMetadata: encryptedMetadata,
            encryptedImageKey: alicePackage.encryptedImageKey,
            assetIdentifier: alicePackage.blurredImagePackage.encryptedPackage.assetIdentifier
        )
        
        print("📡 Alice: Created transmission package (\(transmissionPackage.blurredImageData.count + transmissionPackage.encryptedMetadata.count + transmissionPackage.encryptedImageKey.count) bytes)")
        return transmissionPackage
    }
    
    // MARK: - Bob (Receiver) Operations
    
    /// Bob: Decrypt transmission package and reconstruct original image
    func bobProcessTransmissionPackage(_ transmissionPackage: TransmissionPackage, 
                                     usingPrivateKey bobPrivateKey: SecKey) throws -> UIImage {
        
        delegate?.securePIIManager(self, didStartProcessing: .bobDecryption)
        
        print("🔓 Bob: Processing transmission package for \(transmissionPackage.assetIdentifier)")
        
        // Decrypt image key
        let imageKey = try cryptoManager.decryptImageKeyFromTransmission(
            transmissionPackage.encryptedImageKey,
            usingPrivateKey: bobPrivateKey
        )
        
        // Reconstruct blurred image
        guard let blurredImage = UIImage(data: transmissionPackage.blurredImageData) else {
            throw SecurePIIError.imageConversionFailed
        }
        
        // Deserialize encrypted metadata
        let encryptedPackage = try JSONDecoder().decode(SecureMetadataPackage.self, from: transmissionPackage.encryptedMetadata)
        
        // Reconstruct original image
        delegate?.securePIIManager(self, didStartProcessing: .imageReconstruction)
        
        let originalImage = try imageProcessor.reconstructOriginalImage(
            blurredImage: blurredImage,
            encryptedPackage: encryptedPackage
        )
        
        delegate?.securePIIManager(self, didComplete: .bobDecryption, result: originalImage)
        
        print("✅ Bob: Successfully reconstructed original image")
        return originalImage
    }
    
    // MARK: - Key Management
    
    /// Generate Bob's key pair for receiving encrypted data
    func generateBobKeyPair() throws -> KeyPair {
        delegate?.securePIIManager(self, didStartProcessing: .keyGeneration)
        
        let bobKeyPair = try cryptoManager.generateRSAKeyPair(tag: "bob-keypair")
        
        delegate?.securePIIManager(self, didComplete: .keyGeneration, result: bobKeyPair)
        return bobKeyPair
    }
    
    /// Get Bob's public key for sharing with Alice
    func getBobPublicKey() throws -> Data {
        guard let bobKeyPair = cryptoManager.getKeyPair(tag: "bob-keypair") else {
            throw SecurePIIError.keyNotFound("Bob's key pair not found")
        }
        return bobKeyPair.publicKeyData
    }
    
    /// Import Alice's public key (for future use)
    func importAlicePublicKey(_ publicKeyData: Data) throws -> SecKey {
        return try cryptoManager.importPublicKey(from: publicKeyData, tag: "alice-public")
    }
    
    // MARK: - Utility Methods
    
    func clearAllData() {
        cryptoManager.clearAllKeys()
        isProcessing = false
        pendingProcessingParams = nil
        print("🗑️ Cleared all secure PII data")
    }
    
    func getProcessingStatistics() -> String {
        let keyStats = cryptoManager.getKeyStatistics()
        
        return """
        Secure PII Manager Statistics:
        - Image Keys: \(keyStats.imageKeyCount)
        - Key Pairs: \(keyStats.keyPairCount)
        - Total Memory: \(keyStats.totalMemorySize) bytes
        - Processing: \(isProcessing ? "Active" : "Idle")
        """
    }
    
    // MARK: - Private Helper Methods
    
    private func createBboxResultFromOCR(_ ocrResult: OCRResult) -> BboxMetadataResult {
        // Convert OCR text boxes to PII bounding boxes
        var piiBoundingBoxes: [PIIBoundingBox] = []
        
        for textBox in ocrResult.textBoxes {
            if textBox.classification?.isSensitive == true {
                // Create mock pixel data (in real implementation, this would come from actual image processing)
                let mockPixelData = PixelData(
                    rgba: Array(repeating: 128, count: Int(textBox.boundingBox.width * textBox.boundingBox.height * 4)),
                    width: Int(textBox.boundingBox.width * 100), // Scale up for mock
                    height: Int(textBox.boundingBox.height * 100),
                    bytesPerPixel: 4,
                    bytesPerRow: Int(textBox.boundingBox.width * 100 * 4)
                )
                
                let coordinates = BoundingBoxCoordinates(
                    normalizedRect: textBox.boundingBox,
                    imageSize: CGSize(width: 1000, height: 1000) // Mock image size
                )
                
                let piiBbox = PIIBoundingBox(
                    coordinates: coordinates,
                    pixelData: mockPixelData,
                    assetIdentifier: ocrResult.assetIdentifier,
                    text: textBox.text
                )
                
                piiBoundingBoxes.append(piiBbox)
            }
        }
        
        return BboxMetadataResult(
            assetIdentifier: ocrResult.assetIdentifier,
            piiBoundingBoxes: piiBoundingBoxes,
            processingTime: 0.1,
            originalImageSize: CGSize(width: 1000, height: 1000),
            error: nil
        )
    }
    
    private func loadImageFromOCRResult(_ ocrResult: OCRResult) throws -> UIImage {
        // Mock implementation - in real app, this would load the actual image
        // For now, create a simple colored image
        let size = CGSize(width: 300, height: 200)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        UIColor.systemBlue.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            throw SecurePIIError.imageConversionFailed
        }
        
        return image
    }
}

// MARK: - BboxMetadataProcessor Delegate

extension SecurePIIManager: BboxMetadataProcessorDelegate {
    func bboxProcessor(_ processor: BboxMetadataProcessor, didStartProcessing totalImages: Int) {
        delegate?.securePIIManager(self, didUpdateProgress: .aliceProcessing, progress: 0.0)
    }
    
    func bboxProcessor(_ processor: BboxMetadataProcessor, didProcessImage at: Int, of: Int) {
        let progress = Float(at) / Float(of)
        delegate?.securePIIManager(self, didUpdateProgress: .aliceProcessing, progress: progress)
    }
    
    func bboxProcessor(_ processor: BboxMetadataProcessor, didCompleteWithResults results: [BboxMetadataResult]) {
        // Results handled in main processing flow
    }
    
    func bboxProcessor(_ processor: BboxMetadataProcessor, didFailWithError error: Error) {
        delegate?.securePIIManager(self, didFail: .aliceProcessing, error: error)
    }
}

// MARK: - OCRProcessor Delegate

extension SecurePIIManager: OCRProcessorDelegate {
    func ocrProcessor(_ processor: OCRProcessor, didStartProcessing totalImages: Int) {
        delegate?.securePIIManager(self, didUpdateProgress: .aliceProcessing, progress: 0.0)
    }
    
    func ocrProcessor(_ processor: OCRProcessor, didProcessImage at: Int, of: Int) {
        let progress = Float(at) / Float(of) * 0.5 // OCR is first half of processing
        delegate?.securePIIManager(self, didUpdateProgress: .aliceProcessing, progress: progress)
    }
    
    func ocrProcessor(_ processor: OCRProcessor, didCompleteWithResults results: [OCRResult]) {
        guard let params = pendingProcessingParams else {
            delegate?.securePIIManager(self, didFail: .aliceProcessing, error: SecurePIIError.processingFailed("Missing processing parameters"))
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let alicePackages = try self.processOCRResults(results, receiverPublicKey: params.receiverPublicKey, blurMethod: params.blurMethod)
                self.isProcessing = false
                self.pendingProcessingParams = nil
                self.delegate?.securePIIManager(self, didComplete: .aliceProcessing, result: alicePackages)
            } catch {
                self.isProcessing = false
                self.pendingProcessingParams = nil
                self.delegate?.securePIIManager(self, didFail: .aliceProcessing, error: error)
            }
        }
    }
    
    func ocrProcessor(_ processor: OCRProcessor, didFailWithError error: Error) {
        isProcessing = false
        pendingProcessingParams = nil
        delegate?.securePIIManager(self, didFail: .aliceProcessing, error: error)
    }
}

// MARK: - Secure PII Errors

enum SecurePIIError: LocalizedError {
    case operationInProgress
    case keyNotFound(String)
    case imageConversionFailed
    case invalidTransmissionPackage
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            return "Another secure PII operation is already in progress"
        case .keyNotFound(let message):
            return "Key not found: \(message)"
        case .imageConversionFailed:
            return "Failed to convert image data"
        case .invalidTransmissionPackage:
            return "Invalid transmission package format"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        }
    }
}

// MARK: - Convenience Extensions

// Note: Codable conformance for SecureMetadataPackage and EncryptedMetadata 
// is implemented in CryptographyProcessor.swift where the structs are defined
