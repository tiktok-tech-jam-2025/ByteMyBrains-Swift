//
//  Cryptography.swift
//  PHPickerDemo
//
//  Created by GitHub Copilot on 30/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

/*
Cryptography.swift
Handles cryptographic operations including key generation, AES-GCM encryption/decryption
for secure handling of image metadata and PII data.
*/

import Foundation
import CryptoKit
import Security

// MARK: - Cryptographic Models

struct KeyPair {
    let publicKey: SecKey
    let privateKey: SecKey
    let publicKeyData: Data
    let privateKeyData: Data
    
    init(publicKey: SecKey, privateKey: SecKey) throws {
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.publicKeyData = try CryptographyManager.exportKey(publicKey)
        self.privateKeyData = try CryptographyManager.exportKey(privateKey)
    }
}

struct ImageKey {
    let symmetricKey: SymmetricKey
    let keyData: Data
    let identifier: String
    let createdAt: Date
    
    init() {
        self.symmetricKey = SymmetricKey(size: .bits256)
        self.keyData = self.symmetricKey.withUnsafeBytes { Data($0) }
        self.identifier = UUID().uuidString
        self.createdAt = Date()
    }
    
    init(keyData: Data, identifier: String = UUID().uuidString) throws {
        guard keyData.count == 32 else {
            throw CryptographyError.invalidKeySize
        }
        self.symmetricKey = SymmetricKey(data: keyData)
        self.keyData = keyData
        self.identifier = identifier
        self.createdAt = Date()
    }
}

struct EncryptedMetadata: Codable {
    let encryptedData: Data
    let nonce: Data
    let tag: Data
    let imageKeyIdentifier: String
    let encryptedAt: Date
    
    var combinedData: Data {
        var combined = Data()
        combined.append(nonce)
        combined.append(tag)
        combined.append(encryptedData)
        return combined
    }
    
    init(encryptedData: Data, nonce: Data, tag: Data, imageKeyIdentifier: String) {
        self.encryptedData = encryptedData
        self.nonce = nonce
        self.tag = tag
        self.imageKeyIdentifier = imageKeyIdentifier
        self.encryptedAt = Date()
    }
    
    init(combinedData: Data, imageKeyIdentifier: String) throws {
        guard combinedData.count >= 28 else { // 12 (nonce) + 16 (tag) + data
            throw CryptographyError.invalidEncryptedData
        }
        
        let nonce = combinedData.subdata(in: 0..<12)
        let tag = combinedData.subdata(in: 12..<28)
        let encryptedData = combinedData.subdata(in: 28..<combinedData.count)
        
        self.nonce = nonce
        self.tag = tag
        self.encryptedData = encryptedData
        self.imageKeyIdentifier = imageKeyIdentifier
        self.encryptedAt = Date()
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case encryptedData
        case nonce
        case tag
        case imageKeyIdentifier
        case encryptedAt
    }
}

struct SecureMetadataPackage: Codable {
    let assetIdentifier: String
    let encryptedBoundingBoxes: [EncryptedMetadata]
    let imageKeyIdentifier: String
    let encryptionScheme: String
    let packagedAt: Date
    
    init(assetIdentifier: String, encryptedBoundingBoxes: [EncryptedMetadata], imageKeyIdentifier: String) {
        self.assetIdentifier = assetIdentifier
        self.encryptedBoundingBoxes = encryptedBoundingBoxes
        self.imageKeyIdentifier = imageKeyIdentifier
        self.encryptionScheme = "AES-GCM-256"
        self.packagedAt = Date()
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case assetIdentifier
        case encryptedBoundingBoxes
        case imageKeyIdentifier
        case encryptionScheme
        case packagedAt
    }
}

// MARK: - Cryptography Manager

class CryptographyManager {
    
    static let shared = CryptographyManager()
    private var imageKeys: [String: ImageKey] = [:]
    private var keyPairs: [String: KeyPair] = [:]
    
    private init() {}
    
    // MARK: - Key Pair Generation
    
    /// Generate a new RSA key pair for asymmetric encryption
    func generateRSAKeyPair(keySize: Int = 2048, tag: String = UUID().uuidString) throws -> KeyPair {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: keySize,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false,
                kSecAttrApplicationTag as String: tag.data(using: .utf8)!
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw CryptographyError.keyGenerationFailed(CFErrorCopyDescription(error) as String)
            }
            throw CryptographyError.keyGenerationFailed("Unknown error")
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CryptographyError.keyGenerationFailed("Failed to extract public key")
        }
        
        let keyPair = try KeyPair(publicKey: publicKey, privateKey: privateKey)
        keyPairs[tag] = keyPair
        
        print("🔐 Generated RSA key pair (ID: \(tag), Size: \(keySize) bits)")
        return keyPair
    }
    
    /// Generate a new P256 key pair for elliptic curve cryptography
    func generateP256KeyPair(tag: String = UUID().uuidString) throws -> (P256.KeyAgreement.PrivateKey, String) {
        let privateKey = P256.KeyAgreement.PrivateKey()
        let keyData = privateKey.rawRepresentation
        
        print("🔐 Generated P256 key pair (ID: \(tag))")
        return (privateKey, tag)
    }
    
    // MARK: - Image Key Generation
    
    /// Generate a new AES-256 symmetric key for image metadata encryption
    func generateImageKey(identifier: String? = nil) -> ImageKey {
        let imageKey = ImageKey()
        let keyId = identifier ?? imageKey.identifier
        imageKeys[keyId] = imageKey
        
        print("🔑 Generated image key (ID: \(keyId))")
        return imageKey
    }
    
    /// Retrieve an existing image key by identifier
    func getImageKey(identifier: String) -> ImageKey? {
        return imageKeys[identifier]
    }
    
    /// Store an image key with a specific identifier
    func storeImageKey(_ imageKey: ImageKey, identifier: String) {
        imageKeys[identifier] = imageKey
        print("💾 Stored image key (ID: \(identifier))")
    }
    
    // MARK: - AES-GCM Encryption/Decryption
    
    /// Encrypt PII bounding box metadata using AES-GCM
    func encryptPIIMetadata(_ piiBoundingBox: PIIBoundingBox, using imageKey: ImageKey) throws -> EncryptedMetadata {
        // Serialize the PII bounding box to JSON
        let jsonData = try serializePIIBoundingBox(piiBoundingBox)
        
        // Generate a random nonce
        let nonce = AES.GCM.Nonce()
        
        // Encrypt the data
        let sealedBox = try AES.GCM.seal(jsonData, using: imageKey.symmetricKey, nonce: nonce)
        
        let ciphertext = sealedBox.ciphertext
        let tag = sealedBox.tag
        
        let encryptedMetadata = EncryptedMetadata(
            encryptedData: ciphertext,
            nonce: nonce.withUnsafeBytes { Data($0) },
            tag: tag,
            imageKeyIdentifier: imageKey.identifier
        )
        
        print("🔒 Encrypted PII metadata (\(jsonData.count) bytes → \(ciphertext.count) bytes)")
        return encryptedMetadata
    }
    
    /// Decrypt PII bounding box metadata using AES-GCM
    func decryptPIIMetadata(_ encryptedMetadata: EncryptedMetadata, using imageKey: ImageKey) throws -> PIIBoundingBox {
        // Reconstruct the nonce
        guard let nonce = try? AES.GCM.Nonce(data: encryptedMetadata.nonce) else {
            throw CryptographyError.decryptionFailed("Invalid nonce")
        }
        
        // Create sealed box from components
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encryptedMetadata.encryptedData,
            tag: encryptedMetadata.tag
        )
        
        // Decrypt the data
        let decryptedData = try AES.GCM.open(sealedBox, using: imageKey.symmetricKey)
        
        // Deserialize back to PIIBoundingBox
        let piiBoundingBox = try deserializePIIBoundingBox(from: decryptedData)
        
        print("🔓 Decrypted PII metadata (\(encryptedMetadata.encryptedData.count) bytes → \(decryptedData.count) bytes)")
        return piiBoundingBox
    }
    
    /// Encrypt multiple PII bounding boxes for a single image
    func encryptImageMetadata(_ bboxResult: BboxMetadataResult, using imageKey: ImageKey) throws -> SecureMetadataPackage {
        var encryptedBoundingBoxes: [EncryptedMetadata] = []
        
        for piiBbox in bboxResult.piiBoundingBoxes {
            let encryptedMetadata = try encryptPIIMetadata(piiBbox, using: imageKey)
            encryptedBoundingBoxes.append(encryptedMetadata)
        }
        
        let securePackage = SecureMetadataPackage(
            assetIdentifier: bboxResult.assetIdentifier,
            encryptedBoundingBoxes: encryptedBoundingBoxes,
            imageKeyIdentifier: imageKey.identifier
        )
        
        print("📦 Encrypted image metadata package with \(encryptedBoundingBoxes.count) PII regions")
        return securePackage
    }
    
    /// Decrypt a secure metadata package
    func decryptImageMetadata(_ securePackage: SecureMetadataPackage) throws -> [PIIBoundingBox] {
        guard let imageKey = getImageKey(identifier: securePackage.imageKeyIdentifier) else {
            throw CryptographyError.keyNotFound("Image key not found: \(securePackage.imageKeyIdentifier)")
        }
        
        var decryptedBoundingBoxes: [PIIBoundingBox] = []
        
        for encryptedMetadata in securePackage.encryptedBoundingBoxes {
            let piiBbox = try decryptPIIMetadata(encryptedMetadata, using: imageKey)
            decryptedBoundingBoxes.append(piiBbox)
        }
        
        print("📦 Decrypted image metadata package with \(decryptedBoundingBoxes.count) PII regions")
        return decryptedBoundingBoxes
    }
    
    // MARK: - Alice-Bob Key Exchange
    
    /// Alice: Encrypt image key using Bob's public key for secure transmission
    func encryptImageKeyForTransmission(_ imageKey: ImageKey, usingPublicKey bobPublicKey: SecKey) throws -> Data {
        let keyData = imageKey.keyData
        
        var error: Unmanaged<CFError>?
        guard let encryptedKeyData = SecKeyCreateEncryptedData(
            bobPublicKey,
            .rsaEncryptionOAEPSHA256,
            keyData as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() {
                throw CryptographyError.encryptionFailed(CFErrorCopyDescription(error) as String)
            }
            throw CryptographyError.encryptionFailed("Failed to encrypt image key")
        }
        
        print("🔐 Alice: Encrypted image key for transmission (\(keyData.count) bytes → \(encryptedKeyData.count) bytes)")
        return encryptedKeyData
    }
    
    /// Bob: Decrypt image key using his private key
    func decryptImageKeyFromTransmission(_ encryptedKeyData: Data, usingPrivateKey bobPrivateKey: SecKey) throws -> ImageKey {
        var error: Unmanaged<CFError>?
        guard let decryptedKeyData = SecKeyCreateDecryptedData(
            bobPrivateKey,
            .rsaEncryptionOAEPSHA256,
            encryptedKeyData as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() {
                throw CryptographyError.decryptionFailed(CFErrorCopyDescription(error) as String)
            }
            throw CryptographyError.decryptionFailed("Failed to decrypt image key")
        }
        
        let imageKey = try ImageKey(keyData: decryptedKeyData)
        
        // Store the decrypted key
        storeImageKey(imageKey, identifier: imageKey.identifier)
        
        print("🔓 Bob: Decrypted image key from transmission (\(encryptedKeyData.count) bytes → \(decryptedKeyData.count) bytes)")
        return imageKey
    }
    
    /// Retrieve stored key pair by tag
    func getKeyPair(tag: String) -> KeyPair? {
        return keyPairs[tag]
    }
    
    /// Import public key from data (for receiving Bob's public key)
    func importPublicKey(from keyData: Data, tag: String) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw CryptographyError.keyGenerationFailed(CFErrorCopyDescription(error) as String)
            }
            throw CryptographyError.keyGenerationFailed("Failed to import public key")
        }
        
        print("📥 Imported public key (ID: \(tag))")
        return publicKey
    }
    
    // MARK: - Key Management
    
    /// Export a SecKey to Data
    static func exportKey(_ key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            if let error = error?.takeRetainedValue() {
                throw CryptographyError.keyExportFailed(CFErrorCopyDescription(error) as String)
            }
            throw CryptographyError.keyExportFailed("Unknown error")
        }
        return keyData
    }
    
    /// Clear all stored keys (for security)
    func clearAllKeys() {
        imageKeys.removeAll()
        keyPairs.removeAll()
        print("🗑️ Cleared all cryptographic keys from memory")
    }
    
    /// Get memory usage statistics
    func getKeyStatistics() -> (imageKeyCount: Int, keyPairCount: Int, totalMemorySize: Int) {
        let imageKeyMemory = imageKeys.values.reduce(0) { $0 + $1.keyData.count }
        let keyPairMemory = keyPairs.values.reduce(0) { $0 + $1.publicKeyData.count + $1.privateKeyData.count }
        
        return (
            imageKeyCount: imageKeys.count,
            keyPairCount: keyPairs.count,
            totalMemorySize: imageKeyMemory + keyPairMemory
        )
    }
    
    // MARK: - Private Serialization Methods
    
    private func serializePIIBoundingBox(_ piiBoundingBox: PIIBoundingBox) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let serializable = SerializablePIIBoundingBox(
            normalizedRect: piiBoundingBox.coordinates.normalizedRect,
            pixelRect: piiBoundingBox.coordinates.pixelRect,
            imageSize: piiBoundingBox.coordinates.imageSize,
            pixelData: piiBoundingBox.pixelData.rgba,
            pixelWidth: piiBoundingBox.pixelData.width,
            pixelHeight: piiBoundingBox.pixelData.height,
            bytesPerPixel: piiBoundingBox.pixelData.bytesPerPixel,
            bytesPerRow: piiBoundingBox.pixelData.bytesPerRow,
            assetIdentifier: piiBoundingBox.assetIdentifier,
            text: piiBoundingBox.text
        )
        
        return try encoder.encode(serializable)
    }
    
    private func deserializePIIBoundingBox(from data: Data) throws -> PIIBoundingBox {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let serializable = try decoder.decode(SerializablePIIBoundingBox.self, from: data)
        
        let coordinates = BoundingBoxCoordinates(
            normalizedRect: serializable.normalizedRect,
            imageSize: serializable.imageSize
        )
        
        let pixelData = PixelData(
            rgba: serializable.pixelData,
            width: serializable.pixelWidth,
            height: serializable.pixelHeight,
            bytesPerPixel: serializable.bytesPerPixel,
            bytesPerRow: serializable.bytesPerRow
        )
        
        return PIIBoundingBox(
            coordinates: coordinates,
            pixelData: pixelData,
            assetIdentifier: serializable.assetIdentifier,
            text: serializable.text
        )
    }
}

// MARK: - Serializable Models

private struct SerializablePIIBoundingBox: Codable {
    let normalizedRect: CGRect
    let pixelRect: CGRect
    let imageSize: CGSize
    let pixelData: [UInt8]
    let pixelWidth: Int
    let pixelHeight: Int
    let bytesPerPixel: Int
    let bytesPerRow: Int
    let assetIdentifier: String
    let text: String?
}

// MARK: - Cryptography Errors

enum CryptographyError: LocalizedError {
    case keyGenerationFailed(String)
    case keyExportFailed(String)
    case keyNotFound(String)
    case invalidKeySize
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidEncryptedData
    case serializationFailed
    case deserializationFailed
    
    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let message):
            return "Key generation failed: \(message)"
        case .keyExportFailed(let message):
            return "Key export failed: \(message)"
        case .keyNotFound(let message):
            return "Key not found: \(message)"
        case .invalidKeySize:
            return "Invalid key size provided"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .invalidEncryptedData:
            return "Invalid encrypted data format"
        case .serializationFailed:
            return "Failed to serialize data for encryption"
        case .deserializationFailed:
            return "Failed to deserialize decrypted data"
        }
    }
}

// MARK: - Utility Extensions



// MARK: - Debug Extensions

extension ImageKey {
    var debugDescription: String {
        return """
        ImageKey:
        - ID: \(identifier)
        - Size: \(keyData.count) bytes
        - Created: \(createdAt)
        """
    }
}

extension EncryptedMetadata {
    var debugDescription: String {
        return """
        EncryptedMetadata:
        - Key ID: \(imageKeyIdentifier)
        - Nonce: \(nonce.count) bytes
        - Tag: \(tag.count) bytes  
        - Data: \(encryptedData.count) bytes
        - Total: \(combinedData.count) bytes
        - Encrypted: \(encryptedAt)
        """
    }
}
