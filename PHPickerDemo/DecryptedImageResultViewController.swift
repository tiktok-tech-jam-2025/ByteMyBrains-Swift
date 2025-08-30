//
//  DecryptedImageResultViewController.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 30/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

import UIKit

class DecryptedImageResultViewController: UIViewController {
    
    // Programmatically created UI elements
    private var scrollView: UIScrollView!
    private var imageView: UIImageView!
    private var segmentedControl: UISegmentedControl!
    private var infoLabel: UILabel!
    private var exportButton: UIBarButtonItem!
    private var controlsContainerView: UIView!
    private var successBannerView: UIView!
    
    var originalImage: UIImage?
    var encryptedImage: UIImage?
    
    private var isShowingOriginal = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        displayCurrentImage()
        showSuccessBanner()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "🔓 Decryption Successful"
        
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
        
        // Setup success banner
        setupSuccessBanner()
        
        // Setup controls container
        setupControlsContainer()
        
        // Setup segmented control
        setupSegmentedControl()
        
        // Setup info label
        setupInfoLabel()
        
        // Setup scroll view and image view
        setupScrollView()
        
        // Setup layout
        setupLayout()
        
        // Update info
        updateInfoLabel()
    }
    
    private func setupSuccessBanner() {
        successBannerView = UIView()
        successBannerView.translatesAutoresizingMaskIntoConstraints = false
        successBannerView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.1)
        successBannerView.layer.cornerRadius = 12
        successBannerView.alpha = 0
        
        let iconImageView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.tintColor = .systemGreen
        iconImageView.contentMode = .scaleAspectFit
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Decryption Successful!"
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .systemGreen
        
        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Original image restored with PII data"
        subtitleLabel.font = UIFont.systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
        
        successBannerView.addSubview(iconImageView)
        successBannerView.addSubview(titleLabel)
        successBannerView.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: successBannerView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: successBannerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 30),
            iconImageView.heightAnchor.constraint(equalToConstant: 30),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: successBannerView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: successBannerView.trailingAnchor, constant: -16),
            
            subtitleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: successBannerView.trailingAnchor, constant: -16),
            subtitleLabel.bottomAnchor.constraint(equalTo: successBannerView.bottomAnchor, constant: -12)
        ])
    }
    
    private func setupControlsContainer() {
        controlsContainerView = UIView()
        controlsContainerView.translatesAutoresizingMaskIntoConstraints = false
        controlsContainerView.backgroundColor = .secondarySystemBackground
        controlsContainerView.layer.cornerRadius = 12
    }
    
    private func setupSegmentedControl() {
        segmentedControl = UISegmentedControl(items: ["🔓 Decrypted", "🔒 Encrypted"])
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentedControlChanged(_:)), for: .valueChanged)
        
        // Style the segmented control
        segmentedControl.backgroundColor = .systemBackground
        segmentedControl.selectedSegmentTintColor = .systemGreen
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
        
        view.addSubview(successBannerView)
        view.addSubview(controlsContainerView)
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            // Success banner
            successBannerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            successBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            successBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Controls container
            controlsContainerView.topAnchor.constraint(equalTo: successBannerView.bottomAnchor, constant: 16),
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
            infoLabel.bottomAnchor.constraint(equalTo: controlsContainerView.bottomAnchor, constant: -16),
            
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
    
    private func showSuccessBanner() {
        UIView.animate(withDuration: 0.5, delay: 0.3, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3) {
            self.successBannerView.alpha = 1.0
        }
        
        // Auto-hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UIView.animate(withDuration: 0.3) {
                self.successBannerView.alpha = 0.0
            }
        }
    }
    
    @objc private func dismissView() {
        dismiss(animated: true)
    }
    
    @objc private func exportImage() {
        guard let currentImage = isShowingOriginal ? originalImage : encryptedImage else {
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
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Animate the transition
        UIView.transition(with: imageView, duration: 0.3, options: .transitionCrossDissolve) {
            self.displayCurrentImage()
        }
    }
    
    private func displayCurrentImage() {
        let imageToShow = isShowingOriginal ? originalImage : encryptedImage
        imageView.image = imageToShow
        
        if let image = imageToShow {
            scrollView.zoomScale = 1.0
            imageView.frame.size = image.size
            scrollView.contentSize = image.size
        }
    }
    
    private func updateInfoLabel() {
        let status = isShowingOriginal ? "Decrypted Original" : "Encrypted Version"
        let description = isShowingOriginal ? "PII data restored" : "PII data protected"
        
        infoLabel.text = """
        📸 Viewing: \(status)
        🔐 Status: \(description)
        """
    }
}

// MARK: - UIScrollViewDelegate
extension DecryptedImageResultViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}
