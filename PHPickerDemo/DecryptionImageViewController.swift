//
//  DecryptionImageViewController.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 30/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//


import UIKit

class DecryptedImageViewController: UIViewController {
    
    // Programmatically created UI elements
    private var scrollView: UIScrollView!
    private var imageView: UIImageView!
    private var segmentedControl: UISegmentedControl!
    private var infoLabel: UILabel!
    private var exportButton: UIBarButtonItem!
    private var controlsContainerView: UIView!
    private var statisticsStackView: UIStackView!
    
    var originalImage: UIImage?
    var blurredImage: UIImage?
    var assetIdentifier: String = ""
    var piiRegionsCount: Int = 0
    
    private var isShowingOriginal = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        displayCurrentImage()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "🔓 Decrypted Image"
        
        // Navigation items
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissView)
        )
        
        exportButton = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(exportImage)
        )
        navigationItem.rightBarButtonItem = exportButton
        
        // Setup controls container
        setupControlsContainer()
        
        // Setup segmented control
        setupSegmentedControl()
        
        // Setup info label
        setupInfoLabel()
        
        // Setup statistics
        setupStatistics()
        
        // Setup scroll view and image view
        setupScrollView()
        
        // Setup layout
        setupLayout()
        
        // Update info
        updateInfoLabel()
    }
    
    private func setupControlsContainer() {
        controlsContainerView = UIView()
        controlsContainerView.translatesAutoresizingMaskIntoConstraints = false
        controlsContainerView.backgroundColor = .secondarySystemBackground
        controlsContainerView.layer.cornerRadius = 12
    }
    
    private func setupSegmentedControl() {
        segmentedControl = UISegmentedControl(items: ["🔓 Original", "🔒 Blurred"])
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentedControlChanged(_:)), for: .valueChanged)
        
        // Style the segmented control
        segmentedControl.backgroundColor = .systemBackground
        segmentedControl.selectedSegmentTintColor = .systemBlue
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
    }
    
    private func setupInfoLabel() {
        infoLabel = UILabel()
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 0
        infoLabel.textColor = .secondaryLabel
    }
    
    private func setupStatistics() {
        statisticsStackView = UIStackView()
        statisticsStackView.translatesAutoresizingMaskIntoConstraints = false
        statisticsStackView.axis = .horizontal
        statisticsStackView.distribution = .fillEqually
        statisticsStackView.spacing = 1
        
        // Create stat views
        let statusStatView = createCompactStatView(
            title: "Status",
            value: isShowingOriginal ? "Original" : "Blurred",
            icon: isShowingOriginal ? "eye.fill" : "eye.slash.fill",
            color: isShowingOriginal ? .systemGreen : .systemOrange
        )
        
        let regionsStatView = createCompactStatView(
            title: "PII Regions",
            value: "\(piiRegionsCount)",
            icon: "lock.shield.fill",
            color: .systemBlue
        )
        
        let sizeStatView = createCompactStatView(
            title: "Size",
            value: formatImageSize(),
            icon: "aspectratio.fill",
            color: .systemPurple
        )
        
        statisticsStackView.addArrangedSubview(statusStatView)
        statisticsStackView.addArrangedSubview(regionsStatView)
        statisticsStackView.addArrangedSubview(sizeStatView)
    }
    
    private func createCompactStatView(title: String, value: String, icon: String, color: UIColor) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 6
        
        let iconImageView = UIImageView(image: UIImage(systemName: icon))
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.tintColor = color
        iconImageView.contentMode = .scaleAspectFit
        
        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = value
        valueLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        
        containerView.addSubview(iconImageView)
        containerView.addSubview(valueLabel)
        containerView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 6),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),
            
            valueLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 2),
            valueLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -2),
            
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 2),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -2),
            titleLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -6)
        ])
        
        return containerView
    }
    
    private func setupScrollView() {
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.1
        scrollView.maximumZoomScale = 5.0
        scrollView.zoomScale = 1.0
        scrollView.backgroundColor = .systemGray6
        scrollView.layer.cornerRadius = 12
        scrollView.clipsToBounds = true
        
        imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        
        scrollView.addSubview(imageView)
    }
    
    private func setupLayout() {
        controlsContainerView.addSubview(segmentedControl)
        controlsContainerView.addSubview(infoLabel)
        controlsContainerView.addSubview(statisticsStackView)
        
        view.addSubview(controlsContainerView)
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            // Controls container
            controlsContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            controlsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            controlsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Segmented control
            segmentedControl.topAnchor.constraint(equalTo: controlsContainerView.topAnchor, constant: 16),
            segmentedControl.leadingAnchor.constraint(equalTo: controlsContainerView.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: controlsContainerView.trailingAnchor, constant: -16),
            
            // Info label
            infoLabel.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            infoLabel.leadingAnchor.constraint(equalTo: controlsContainerView.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: controlsContainerView.trailingAnchor, constant: -16),
            
            // Statistics stack view
            statisticsStackView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 12),
            statisticsStackView.leadingAnchor.constraint(equalTo: controlsContainerView.leadingAnchor, constant: 16),
            statisticsStackView.trailingAnchor.constraint(equalTo: controlsContainerView.trailingAnchor, constant: -16),
            statisticsStackView.bottomAnchor.constraint(equalTo: controlsContainerView.bottomAnchor, constant: -16),
            statisticsStackView.heightAnchor.constraint(equalToConstant: 60),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: controlsContainerView.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            
            // Image view
            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }
    
    @objc private func dismissView() {
        dismiss(animated: true)
    }
    
    @objc private func exportImage() {
        guard let currentImage = isShowingOriginal ? originalImage : blurredImage else {
            return
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        let activityVC = UIActivityViewController(activityItems: [currentImage], applicationActivities: nil)
        activityVC.popoverPresentationController?.barButtonItem = exportButton
        present(activityVC, animated: true)
    }
    
    @objc private func segmentedControlChanged(_ sender: UISegmentedControl) {
        isShowingOriginal = sender.selectedSegmentIndex == 0
        displayCurrentImage()
        updateInfoLabel()
        updateStatistics()
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Animate the transition
        UIView.transition(with: imageView, duration: 0.3, options: .transitionCrossDissolve) {
            self.displayCurrentImage()
        }
    }
    
    private func displayCurrentImage() {
        let imageToShow = isShowingOriginal ? originalImage : blurredImage
        imageView.image = imageToShow
        
        if let image = imageToShow {
            scrollView.zoomScale = 1.0
            imageView.frame.size = image.size
            scrollView.contentSize = image.size
        }
    }
    
    private func updateInfoLabel() {
        let status = isShowingOriginal ? "Original (Decrypted)" : "Blurred (Encrypted)"
        let shortAssetId = String(assetIdentifier.prefix(8))
        
        infoLabel.text = """
        📸 Viewing: \(status)
        🆔 Asset: \(shortAssetId)... | 🔐 PII Regions: \(piiRegionsCount)
        """
    }
    
    private func updateStatistics() {
        // Remove old statistics
        statisticsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Create new statistics
        let statusStatView = createCompactStatView(
            title: "Status",
            value: isShowingOriginal ? "Original" : "Blurred",
            icon: isShowingOriginal ? "eye.fill" : "eye.slash.fill",
            color: isShowingOriginal ? .systemGreen : .systemOrange
        )
        
        let regionsStatView = createCompactStatView(
            title: "PII Regions",
            value: "\(piiRegionsCount)",
            icon: "lock.shield.fill",
            color: .systemBlue
        )
        
        let sizeStatView = createCompactStatView(
            title: "Size",
            value: formatImageSize(),
            icon: "aspectratio.fill",
            color: .systemPurple
        )
        
        statisticsStackView.addArrangedSubview(statusStatView)
        statisticsStackView.addArrangedSubview(regionsStatView)
        statisticsStackView.addArrangedSubview(sizeStatView)
    }
    
    private func formatImageSize() -> String {
        let imageSize = isShowingOriginal ? originalImage?.size : blurredImage?.size
        if let size = imageSize {
            return "\(Int(size.width))×\(Int(size.height))"
        }
        return "N/A"
    }
}

// MARK: - UIScrollViewDelegate
extension DecryptedImageViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}
