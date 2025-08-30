//
//  DecryptionViewController.swift
//  PHPickerDemo
//
//  Created by GitHub Copilot on 30/8/25.
//

import UIKit
import PhotosUI

class DecryptionViewController: UIViewController {
    
    // Programmatically created UI elements
    private var tableView: UITableView!
    private var infoLabel: UILabel!
    private var headerView: UIView!
    private var statisticsView: UIView!
    
    var alicePackages: [AlicePackage] = []
    var bobKeyPair: KeyPair?
    
    // 🔐 Add SecurePIIManager reference
    private let securePIIManager = SecurePIIManager.shared
    private let imageProcessor = ImageProcessor.shared
    private let cryptoManager = CryptographyManager.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadPackageInfo()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "🔓 PII Decryption Center"
        
        // Navigation items
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissView)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showInfoAlert)
        )
        
        // Create header view
        setupHeaderView()
        
        // Create info label
        setupInfoLabel()
        
        // Create statistics view
        setupStatisticsView()
        
        // Create table view
        setupTableView()
        
        // Setup layout
        setupLayout()
    }
    
    private func setupHeaderView() {
        headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        headerView.layer.cornerRadius = 12
        
        let iconImageView = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.tintColor = .systemBlue
        iconImageView.contentMode = .scaleAspectFit
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Encrypted PII Packages"
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label
        
        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Tap any package to decrypt and view original image"
        subtitleLabel.font = UIFont.systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
        
        headerView.addSubview(iconImageView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 40),
            iconImageView.heightAnchor.constraint(equalToConstant: 40),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            
            subtitleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            subtitleLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -16)
        ])
    }
    
    private func setupInfoLabel() {
        infoLabel = UILabel()
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 0
        infoLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        infoLabel.textColor = .secondaryLabel
    }
    
    private func setupStatisticsView() {
        statisticsView = UIView()
        statisticsView.translatesAutoresizingMaskIntoConstraints = false
        statisticsView.backgroundColor = .secondarySystemBackground
        statisticsView.layer.cornerRadius = 12
        
        // Create statistics stack view
        let statsStackView = UIStackView()
        statsStackView.translatesAutoresizingMaskIntoConstraints = false
        statsStackView.axis = .horizontal
        statsStackView.distribution = .fillEqually
        statsStackView.spacing = 1
        
        // Packages stat
        let packagesStatView = createStatView(title: "Packages", value: "\(alicePackages.count)", icon: "shippingbox.fill", color: .systemBlue)
        
        // PII regions stat
        let totalRegions = alicePackages.reduce(0) { total, package in
            return total + package.blurredImagePackage.encryptedPackage.encryptedBoundingBoxes.count
        }
        let regionsStatView = createStatView(title: "PII Regions", value: "\(totalRegions)", icon: "eye.slash.fill", color: .systemOrange)
        
        // Encryption stat
        let encryptionStatView = createStatView(title: "Encryption", value: "AES-256", icon: "checkmark.shield.fill", color: .systemGreen)
        
        statsStackView.addArrangedSubview(packagesStatView)
        statsStackView.addArrangedSubview(regionsStatView)
        statsStackView.addArrangedSubview(encryptionStatView)
        
        statisticsView.addSubview(statsStackView)
        
        NSLayoutConstraint.activate([
            statsStackView.topAnchor.constraint(equalTo: statisticsView.topAnchor, constant: 16),
            statsStackView.leadingAnchor.constraint(equalTo: statisticsView.leadingAnchor, constant: 16),
            statsStackView.trailingAnchor.constraint(equalTo: statisticsView.trailingAnchor, constant: -16),
            statsStackView.bottomAnchor.constraint(equalTo: statisticsView.bottomAnchor, constant: -16)
        ])
    }
    
    private func createStatView(title: String, value: String, icon: String, color: UIColor) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 8
        
        let iconImageView = UIImageView(image: UIImage(systemName: icon))
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.tintColor = color
        iconImageView.contentMode = .scaleAspectFit
        
        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = value
        valueLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        
        containerView.addSubview(iconImageView)
        containerView.addSubview(valueLabel)
        containerView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),
            
            valueLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 8),
            valueLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
            valueLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            titleLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
        
        return containerView
    }
    
    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(DecryptionTableViewCell.self, forCellReuseIdentifier: "DecryptionCell")
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
    }
    
    private func setupLayout() {
        view.addSubview(headerView)
        view.addSubview(statisticsView)
        view.addSubview(infoLabel)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            // Header view
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Statistics view
            statisticsView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            statisticsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statisticsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Info label
            infoLabel.topAnchor.constraint(equalTo: statisticsView.bottomAnchor, constant: 16),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadPackageInfo() {
        let packagesCount = alicePackages.count
        
        if packagesCount == 0 {
            infoLabel.text = "No encrypted packages available"
        } else {
            infoLabel.text = "🔐 Secure PII Packages Ready for Decryption"
        }
    }
    
    @objc private func dismissView() {
        dismiss(animated: true)
    }
    
    @objc private func showInfoAlert() {
        let message = """
        This is the PII Decryption Center where you can decrypt and view original images that have been processed with the Alice-Bob encryption protocol.
        
        🔐 Each package contains:
        • Blurred image (safe to view)
        • Encrypted PII metadata
        • AES-256 encrypted pixel data
        
        🔓 Decryption Process:
        • Uses Bob's private key
        • Reconstructs original PII regions
        • Shows before/after comparison
        """
        
        let alert = UIAlertController(title: "About PII Decryption", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Got it", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate
extension DecryptionViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return alicePackages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DecryptionCell", for: indexPath) as! DecryptionTableViewCell
        
        let package = alicePackages[indexPath.row]
        cell.configure(with: package, index: indexPath.row + 1)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let bobKeyPair = self.bobKeyPair else {
            showAlert(title: "Error", message: "Bob's keys not available")
            return
        }
        
        let package = alicePackages[indexPath.row]
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Show loading
        let loadingAlert = createLoadingAlert()
        present(loadingAlert, animated: true)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                // Create transmission package (simulate network transmission)
                let transmissionPackage = try self?.createTransmissionPackage(from: package)
                
                guard let transmissionPackage = transmissionPackage else {
                    throw SecurePIIError.processingFailed("Failed to create transmission package")
                }
                
                // 🔐 Bob decrypts the package using SecurePIIManager
                let originalImage = try self?.securePIIManager.bobProcessTransmissionPackage(
                    transmissionPackage,
                    usingPrivateKey: bobKeyPair.privateKey
                )
                
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        if let originalImage = originalImage {
                            // Success haptic feedback
                            let successFeedback = UINotificationFeedbackGenerator()
                            successFeedback.notificationOccurred(.success)
                            
                            self?.showDecryptedImage(originalImage, for: package)
                        } else {
                            // Error haptic feedback
                            let errorFeedback = UINotificationFeedbackGenerator()
                            errorFeedback.notificationOccurred(.error)
                            
                            self?.showAlert(title: "Error", message: "Failed to decrypt image")
                        }
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        // Error haptic feedback
                        let errorFeedback = UINotificationFeedbackGenerator()
                        errorFeedback.notificationOccurred(.error)
                        
                        self?.showAlert(title: "Decryption Error", message: error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private func createLoadingAlert() -> UIAlertController {
        let alert = UIAlertController(title: "🔓 Decrypting", message: "Processing encrypted PII data...", preferredStyle: .alert)
        
        // Add activity indicator
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        
        alert.view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            activityIndicator.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -50)
        ])
        
        return alert
    }
    
    private func createTransmissionPackage(from alicePackage: AlicePackage) throws -> TransmissionPackage {
        // Convert blurred image to data
        guard let blurredImageData = alicePackage.blurredImagePackage.blurredImage.pngData() else {
            throw SecurePIIError.imageConversionFailed
        }
        
        // Serialize encrypted metadata
        let encryptedMetadata = try JSONEncoder().encode(alicePackage.blurredImagePackage.encryptedPackage)
        
        return TransmissionPackage(
            blurredImageData: blurredImageData,
            encryptedMetadata: encryptedMetadata,
            encryptedImageKey: alicePackage.encryptedImageKey,
            assetIdentifier: alicePackage.blurredImagePackage.encryptedPackage.assetIdentifier
        )
    }
    
    private func showDecryptedImage(_ image: UIImage, for package: AlicePackage) {
        let imageVC = DecryptedImageViewController()
        imageVC.originalImage = image
        imageVC.blurredImage = package.blurredImagePackage.blurredImage
        imageVC.assetIdentifier = package.blurredImagePackage.encryptedPackage.assetIdentifier
        imageVC.piiRegionsCount = package.blurredImagePackage.encryptedPackage.encryptedBoundingBoxes.count
        
        let navController = UINavigationController(rootViewController: imageVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - DecryptionTableViewCell
class DecryptionTableViewCell: UITableViewCell {
    
    private let containerView = UIView()
    private let packageImageView = UIImageView()
    private let titleLabel = UILabel()
    private let detailsLabel = UILabel()
    private let statusLabel = UILabel()
    private let accessoryImageView = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        // Container view
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 12
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowOpacity = 0.1
        containerView.layer.shadowRadius = 4
        
        // Package image view
        packageImageView.translatesAutoresizingMaskIntoConstraints = false
        packageImageView.contentMode = .scaleAspectFill
        packageImageView.clipsToBounds = true
        packageImageView.layer.cornerRadius = 8
        packageImageView.backgroundColor = .systemGray5
        
        // Title label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        
        // Details label
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        detailsLabel.font = UIFont.systemFont(ofSize: 14)
        detailsLabel.textColor = .secondaryLabel
        detailsLabel.numberOfLines = 0
        
        // Status label
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .systemGreen
        statusLabel.text = "🔐 Encrypted"
        statusLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.1)
        statusLabel.layer.cornerRadius = 8
        statusLabel.layer.masksToBounds = true
        statusLabel.textAlignment = .center
        
        // Accessory image view
        accessoryImageView.translatesAutoresizingMaskIntoConstraints = false
        accessoryImageView.image = UIImage(systemName: "chevron.right")
        accessoryImageView.tintColor = .tertiaryLabel
        accessoryImageView.contentMode = .scaleAspectFit
        
        contentView.addSubview(containerView)
        containerView.addSubview(packageImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(detailsLabel)
        containerView.addSubview(statusLabel)
        containerView.addSubview(accessoryImageView)
        
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            // Package image view
            packageImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            packageImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            packageImageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            packageImageView.widthAnchor.constraint(equalToConstant: 70),
            packageImageView.heightAnchor.constraint(equalToConstant: 70),
            
            // Title label
            titleLabel.leadingAnchor.constraint(equalTo: packageImageView.trailingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -8),
            
            // Details label
            detailsLabel.leadingAnchor.constraint(equalTo: packageImageView.trailingAnchor, constant: 16),
            detailsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            detailsLabel.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -8),
            detailsLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -16),
            
            // Status label
            statusLabel.trailingAnchor.constraint(equalTo: accessoryImageView.leadingAnchor, constant: -8),
            statusLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            statusLabel.widthAnchor.constraint(equalToConstant: 80),
            statusLabel.heightAnchor.constraint(equalToConstant: 28),
            
            // Accessory image view
            accessoryImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            accessoryImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            accessoryImageView.widthAnchor.constraint(equalToConstant: 12),
            accessoryImageView.heightAnchor.constraint(equalToConstant: 12)
        ])
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        
        UIView.animate(withDuration: 0.2) {
            self.containerView.transform = highlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            self.containerView.alpha = highlighted ? 0.8 : 1.0
        }
    }
    
    func configure(with package: AlicePackage, index: Int) {
        titleLabel.text = "📦 Package \(index)"
        
        let piiCount = package.blurredImagePackage.encryptedPackage.encryptedBoundingBoxes.count
        let imageSize = package.blurredImagePackage.blurredImage.size
        let assetId = String(package.blurredImagePackage.encryptedPackage.assetIdentifier.prefix(8))
        
        detailsLabel.text = """
        Asset ID: \(assetId)...
        PII Regions: \(piiCount) encrypted
        Size: \(Int(imageSize.width))×\(Int(imageSize.height))
        Method: \(package.blurredImagePackage.blurMethod.description)
        """
        
        // Set blurred image as thumbnail
        packageImageView.image = package.blurredImagePackage.blurredImage
    }
}
