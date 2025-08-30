//
//  OCRVisualizationViewController.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 29/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

import UIKit
import PhotosUI

class OCRVisualizationViewController: UIViewController {
    
    private var scrollView: UIScrollView!
    private var imageView: UIImageView!
    private var segmentedControl: UISegmentedControl!
    private var infoLabel: UILabel!
    private var textDetailsView: UITextView!
    private var controlView: UIView!
    
    var ocrResults: [OCRResult] = []
    var objectDetectionResults: [ObjectDetectionResult] = []
    var selection: [String: PHPickerResult] = [:]
    
    private var currentImageIndex = 0
    private var loadedImages: [String: UIImage] = [:]
    
    // Separate blur states for text and objects
    private var textBlurStates: [String: Bool] = [:]
    private var objectBlurStates: [String: Bool] = [:]
    
    // Button references
    private var textBlurButtons: [String: UIButton] = [:]
    private var objectBlurButtons: [String: UIButton] = [:]
    private var downloadButtons: [String: UIButton] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadAllImages()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "OCR & Object Detection Visualization"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissView)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Export",
            style: .plain,
            target: self,
            action: #selector(exportCurrentImage)
        )
        
        // Create segmented control
        segmentedControl = UISegmentedControl()
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup segmented control with image identifiers
        for (index, _) in ocrResults.enumerated() {
            segmentedControl.insertSegment(withTitle: "Image \(index + 1)", at: index, animated: false)
        }
        
        if !ocrResults.isEmpty {
            segmentedControl.selectedSegmentIndex = 0
        }
        
        segmentedControl.addTarget(self, action: #selector(segmentedControlChanged(_:)), for: .valueChanged)
        
        // Create info label
        infoLabel = UILabel()
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.font = UIFont.systemFont(ofSize: 14)
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 0
        
        // Create scroll view
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.1
        scrollView.maximumZoomScale = 5.0
        scrollView.zoomScale = 1.0
        scrollView.backgroundColor = .systemGray6
        
        // Create image view
        imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        
        // Create control view for blur/download buttons - increased height for 3 buttons
        controlView = UIView()
        controlView.translatesAutoresizingMaskIntoConstraints = false
        controlView.backgroundColor = .systemGray6
        controlView.layer.cornerRadius = 12
        
        // Create text details view
        textDetailsView = UITextView()
        textDetailsView.translatesAutoresizingMaskIntoConstraints = false
        textDetailsView.isEditable = false
        textDetailsView.font = UIFont.systemFont(ofSize: 12)
        textDetailsView.layer.borderColor = UIColor.systemGray4.cgColor
        textDetailsView.layer.borderWidth = 1
        textDetailsView.layer.cornerRadius = 8
        textDetailsView.backgroundColor = .systemBackground
        
        // Add subviews
        view.addSubview(segmentedControl)
        view.addSubview(infoLabel)
        view.addSubview(scrollView)
        view.addSubview(controlView)
        view.addSubview(textDetailsView)
        scrollView.addSubview(imageView)
        
        // Setup constraints - increased control view height for 3 buttons
        NSLayoutConstraint.activate([
            // Segmented control
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Info label
            infoLabel.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: controlView.topAnchor, constant: -8),
            
            // Image view
            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            
            // Control view - increased height for 3 buttons
            controlView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            controlView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            controlView.bottomAnchor.constraint(equalTo: textDetailsView.topAnchor, constant: -8),
            controlView.heightAnchor.constraint(equalToConstant: 140), // Increased from 60 to 140
            
            // Text details view
            textDetailsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textDetailsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textDetailsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            textDetailsView.heightAnchor.constraint(equalToConstant: 150)
        ])
    }
    
    @objc private func dismissView() {
        dismiss(animated: true)
    }
    
    @objc private func exportCurrentImage() {
        guard currentImageIndex < ocrResults.count,
              let image = createVisualizationImage(for: ocrResults[currentImageIndex]) else {
            showAlert(title: "Export Error", message: "Could not create visualization image")
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activityVC, animated: true)
    }
    
    @objc private func segmentedControlChanged(_ sender: UISegmentedControl) {
        currentImageIndex = sender.selectedSegmentIndex
        displayCurrentImage()
    }
    
    private func loadAllImages() {
        let group = DispatchGroup()
        
        for result in ocrResults {
            guard let pickerResult = selection[result.assetIdentifier] else { continue }
            
            group.enter()
            loadImage(from: pickerResult, identifier: result.assetIdentifier) { [weak self] image in
                if let image = image {
                    self?.loadedImages[result.assetIdentifier] = image
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.displayCurrentImage()
        }
    }
    
    private func loadImage(from pickerResult: PHPickerResult, identifier: String, completion: @escaping (UIImage?) -> Void) {
        let itemProvider = pickerResult.itemProvider
        
        guard itemProvider.canLoadObject(ofClass: UIImage.self) else {
            completion(nil)
            return
        }
        
        itemProvider.loadObject(ofClass: UIImage.self) { image, error in
            DispatchQueue.main.async {
                completion(image as? UIImage)
            }
        }
    }
    
    private func displayCurrentImage() {
        guard currentImageIndex < ocrResults.count else { return }
        
        let result = ocrResults[currentImageIndex]
        
        // Update info label
        updateInfoLabel(for: result)
        
        // Update control view
        updateControlView(for: result)
        
        // Update text details
        updateTextDetails(for: result)
        
        // Create and display visualization
        if let visualizationImage = createVisualizationImage(for: result) {
            imageView.image = visualizationImage
            scrollView.zoomScale = 1.0
            
            // Update image view size to match image
            imageView.frame.size = visualizationImage.size
            scrollView.contentSize = visualizationImage.size
        }
    }
    
    private func updateInfoLabel(for result: OCRResult) {
        let textCount = result.textBoxes.count
        let ocrProcessingTime = String(format: "%.2f", result.processingTime)
        
        // Get corresponding object detection result
        let objectResult = objectDetectionResults.first { $0.assetIdentifier == result.assetIdentifier }
        let objectCount = objectResult?.totalObjectCount ?? 0
        let objectProcessingTime = String(format: "%.2f", objectResult?.processingTime ?? 0)
        
        if let error = result.error {
            infoLabel.text = "❌ Error: \(error.localizedDescription)"
            infoLabel.textColor = .systemRed
        } else {
            // Show both text and object counts
            infoLabel.text = "✅ Text: \(textCount) regions (\(ocrProcessingTime)s) • Objects: \(objectCount) detected (\(objectProcessingTime)s)"
            infoLabel.textColor = .label
        }
    }
    
    // Update control view with separate buttons for text, objects, and download
    private func updateControlView(for result: OCRResult) {
        // Clear existing subviews
        controlView.subviews.forEach { $0.removeFromSuperview() }
        
        // Check for sensitive content
        let hasSensitiveText = result.textBoxes.contains { $0.classification?.isSensitive == true }
        let objectResult = objectDetectionResults.first { $0.assetIdentifier == result.assetIdentifier }
        let hasSensitiveObjects = objectResult?.hasSensitiveObjects ?? false
        
        if hasSensitiveText || hasSensitiveObjects {
            setupSensitiveContentButtons(for: result, hasSensitiveText: hasSensitiveText, hasSensitiveObjects: hasSensitiveObjects)
        } else {
            setupAllGoodLabel()
        }
    }
    
    private func setupSensitiveContentButtons(for result: OCRResult, hasSensitiveText: Bool, hasSensitiveObjects: Bool) {
        let buttonHeight: CGFloat = 32
        let buttonWidth: CGFloat = 220
        
        // Create a vertical stack view
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center  // This ensures all buttons are centered
        stackView.distribution = .equalSpacing
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Text blur button (only if there's sensitive text)
        if hasSensitiveText {
            let textBlurButton = createTextBlurButton(for: result)
            textBlurButtons[result.assetIdentifier] = textBlurButton
            
            // Set button size
            textBlurButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textBlurButton.widthAnchor.constraint(equalToConstant: buttonWidth),
                textBlurButton.heightAnchor.constraint(equalToConstant: buttonHeight)
            ])
            
            stackView.addArrangedSubview(textBlurButton)
        }
        
        // Object blur button (only if there are sensitive objects)
        if hasSensitiveObjects {
            let objectBlurButton = createObjectBlurButton(for: result)
            objectBlurButtons[result.assetIdentifier] = objectBlurButton
            
            // Set button size
            objectBlurButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                objectBlurButton.widthAnchor.constraint(equalToConstant: buttonWidth),
                objectBlurButton.heightAnchor.constraint(equalToConstant: buttonHeight)
            ])
            
            stackView.addArrangedSubview(objectBlurButton)
        }
        
        // Download button (always present when there's sensitive content)
        let downloadButton = createDownloadButton(for: result)
        downloadButtons[result.assetIdentifier] = downloadButton
        
        // Set button size
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            downloadButton.widthAnchor.constraint(equalToConstant: buttonWidth),
            downloadButton.heightAnchor.constraint(equalToConstant: buttonHeight)
        ])
        
        stackView.addArrangedSubview(downloadButton)
        
        // Add stack view to control view and center it
        controlView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: controlView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: controlView.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: controlView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: controlView.trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: controlView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: controlView.bottomAnchor, constant: -8)
        ])
    }
    
    private func setupAllGoodLabel() {
        let label = UILabel()
        label.text = "✅ All's Good - No Sensitive Content"
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = UIColor.systemGreen
        label.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.1)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        
        controlView.addSubview(label)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: controlView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: controlView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 280),
            label.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    
    // Create text blur button
    private func createTextBlurButton(for result: OCRResult) -> UIButton {
        let button = UIButton(type: .system)
        updateTextBlurButtonAppearance(button: button, isBlurred: textBlurStates[result.assetIdentifier] ?? false)
        
        button.addTarget(self, action: #selector(textBlurTapped(_:)), for: .touchUpInside)
        button.layer.cornerRadius = 20
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        
        // Add shadow
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.1
        button.layer.shadowRadius = 4
        
        return button
    }
    
    // Create object blur button
    private func createObjectBlurButton(for result: OCRResult) -> UIButton {
        let button = UIButton(type: .system)
        updateObjectBlurButtonAppearance(button: button, isBlurred: objectBlurStates[result.assetIdentifier] ?? false)
        
        button.addTarget(self, action: #selector(objectBlurTapped(_:)), for: .touchUpInside)
        button.layer.cornerRadius = 20
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        
        // Add shadow
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.1
        button.layer.shadowRadius = 4
        
        return button
    }
    
    // Create download button
    private func createDownloadButton(for result: OCRResult) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("📥 Download Blurred Image", for: .normal)
        button.backgroundColor = UIColor.systemGreen
        button.setTitleColor(.white, for: .normal)
        
        button.addTarget(self, action: #selector(downloadBlurredImage(_:)), for: .touchUpInside)
        button.layer.cornerRadius = 20
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        
        // Add shadow
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.1
        button.layer.shadowRadius = 4
        
        return button
    }
    
    private func updateTextBlurButtonAppearance(button: UIButton, isBlurred: Bool) {
        if isBlurred {
            button.setTitle("📝 Text Blur: ON", for: .normal)
            button.backgroundColor = UIColor.systemBlue
            button.setTitleColor(.white, for: .normal)
        } else {
            button.setTitle("📝 Text Blur: OFF", for: .normal)
            button.backgroundColor = UIColor.systemGray4
            button.setTitleColor(.label, for: .normal)
        }
    }
    
    private func updateObjectBlurButtonAppearance(button: UIButton, isBlurred: Bool) {
        if isBlurred {
            button.setTitle("🎯 Object Blur: ON", for: .normal)
            button.backgroundColor = UIColor.systemOrange
            button.setTitleColor(.white, for: .normal)
        } else {
            button.setTitle("🎯 Object Blur: OFF", for: .normal)
            button.backgroundColor = UIColor.systemGray4
            button.setTitleColor(.label, for: .normal)
        }
    }
    
    // Text blur button action
    @objc private func textBlurTapped(_ sender: UIButton) {
        let result = ocrResults[currentImageIndex]
        let assetId = result.assetIdentifier
        
        // Toggle text blur state
        let currentState = textBlurStates[assetId] ?? false
        textBlurStates[assetId] = !currentState
        
        // Update button appearance
        updateTextBlurButtonAppearance(button: sender, isBlurred: !currentState)
        
        // Re-render image
        if let visualizationImage = createVisualizationImage(for: result) {
            imageView.image = visualizationImage
            scrollView.zoomScale = 1.0
            imageView.frame.size = visualizationImage.size
            scrollView.contentSize = visualizationImage.size
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        print("📝 Text blur toggled: \(!currentState) for image \(currentImageIndex + 1)")
    }
    
    // Object blur button action
    @objc private func objectBlurTapped(_ sender: UIButton) {
        let result = ocrResults[currentImageIndex]
        let assetId = result.assetIdentifier
        
        // Toggle object blur state
        let currentState = objectBlurStates[assetId] ?? false
        objectBlurStates[assetId] = !currentState
        
        // Update button appearance
        updateObjectBlurButtonAppearance(button: sender, isBlurred: !currentState)
        
        // Re-render image
        if let visualizationImage = createVisualizationImage(for: result) {
            imageView.image = visualizationImage
            scrollView.zoomScale = 1.0
            imageView.frame.size = visualizationImage.size
            scrollView.contentSize = visualizationImage.size
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        print("🎯 Object blur toggled: \(!currentState) for image \(currentImageIndex + 1)")
    }
    
    // Download button action
    @objc private func downloadBlurredImage(_ sender: UIButton) {
        let result = ocrResults[currentImageIndex]
        
        guard let originalImage = loadedImages[result.assetIdentifier] else {
            showAlert(title: "Error", message: "Could not access original image")
            return
        }
        
        // Create image with only the selected blur types applied
        let blurredImage = createFinalBlurredImage(for: result)
        
        // Save to photo library
        UIImageWriteToSavedPhotosAlbum(blurredImage, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
        
        // Haptic feedback
        let successFeedback = UINotificationFeedbackGenerator()
        successFeedback.notificationOccurred(.success)
        
        let textBlurEnabled = textBlurStates[result.assetIdentifier] ?? false
        let objectBlurEnabled = objectBlurStates[result.assetIdentifier] ?? false
        
        print("📥 Downloaded image \(currentImageIndex + 1) - Text blur: \(textBlurEnabled), Object blur: \(objectBlurEnabled)")
    }
    
    // Create final blurred image for download (no bounding boxes, only selected blur types)
    private func createFinalBlurredImage(for result: OCRResult) -> UIImage {
        guard let originalImage = loadedImages[result.assetIdentifier] else { return UIImage() }
        
        let imageSize = originalImage.size
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // Draw original image
            originalImage.draw(at: .zero)
            
            let assetId = result.assetIdentifier
            let textBlurEnabled = textBlurStates[assetId] ?? false
            let objectBlurEnabled = objectBlurStates[assetId] ?? false
            
            // Apply text blur if enabled
            if textBlurEnabled {
                for textBox in result.textBoxes {
                    if textBox.classification?.isSensitive == true {
                        let rect = VisionCoordinateConverter.convertBoundingBox(textBox.boundingBox, to: imageSize)
                        drawBlurEffect(context: cgContext, rect: rect, imageSize: imageSize)
                    }
                }
            }
            
            // Apply object blur if enabled
            if objectBlurEnabled {
                let objectResult = objectDetectionResults.first { $0.assetIdentifier == result.assetIdentifier }
                if let objectResult = objectResult {
                    for objectBox in objectResult.objectBoxes {
                        if objectBox.isSensitive {
                            let rect = VisionCoordinateConverter.convertBoundingBox(objectBox.boundingBox, to: imageSize)
                            drawBlurEffect(context: cgContext, rect: rect, imageSize: imageSize)
                        }
                    }
                }
            }
        }
    }
    
    // Handle save completion
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async {
            if let error = error {
                self.showAlert(title: "Save Error", message: "Failed to save image: \(error.localizedDescription)")
            } else {
                self.showAlert(title: "Success", message: "Blurred image saved to Photos!")
            }
        }
    }
    
    private func updateTextDetails(for result: OCRResult) {
        var details = ""
        
        // Object Detection details first
        let objectResult = objectDetectionResults.first { $0.assetIdentifier == result.assetIdentifier }
        
        if let objectResult = objectResult, !objectResult.objectBoxes.isEmpty {
            details += "🎯 DETECTED OBJECTS:\n\n"
            for (index, objectBox) in objectResult.objectBoxes.enumerated() {
                let confidence = String(format: "%.2f", objectBox.confidence)
                let sensitiveEmoji = objectBox.isSensitive ? "🔴" : "🟢"
                details += "\(sensitiveEmoji) \(index + 1). \(objectBox.displayName)\n"
                details += "   Confidence: \(confidence)\n"
                if objectBox.isSensitive, let reason = objectBox.sensitivityReason {
                    details += "   Reason: \(reason)\n"
                }
                details += "   Bounds: x=\(String(format: "%.3f", objectBox.boundingBox.origin.x)), "
                details += "y=\(String(format: "%.3f", objectBox.boundingBox.origin.y)), "
                details += "w=\(String(format: "%.3f", objectBox.boundingBox.width)), "
                details += "h=\(String(format: "%.3f", objectBox.boundingBox.height))\n\n"
            }
            details += "\n"
        }
        
        // Text details
        if result.textBoxes.isEmpty {
            details += "📝 DETECTED TEXT:\n\nNo text detected in this image."
        } else {
            details += "📝 DETECTED TEXT:\n\n"
            for (index, textBox) in result.textBoxes.enumerated() {
                let confidence = String(format: "%.2f", textBox.confidence)
                let sensitiveEmoji = textBox.classification?.isSensitive == true ? "🔴" : "🟢"
                details += "\(sensitiveEmoji) \(index + 1). \"\(textBox.text)\"\n"
                details += "   Confidence: \(confidence)\n"
                if let classification = textBox.classification, classification.isSensitive {
                    details += "   Type: \(classification.predictedClass.uppercased())\n"
                }
                details += "   Bounds: x=\(String(format: "%.3f", textBox.boundingBox.origin.x)), "
                details += "y=\(String(format: "%.3f", textBox.boundingBox.origin.y)), "
                details += "w=\(String(format: "%.3f", textBox.boundingBox.width)), "
                details += "h=\(String(format: "%.3f", textBox.boundingBox.height))\n\n"
            }
        }
        
        textDetailsView.text = details
    }
    
    private func createVisualizationImage(for result: OCRResult) -> UIImage? {
        guard let originalImage = loadedImages[result.assetIdentifier] else {
            print("❌ No loaded image found for \(result.assetIdentifier)")
            return nil
        }
        
        // Create graphics context
        UIGraphicsBeginImageContextWithOptions(originalImage.size, false, originalImage.scale)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        // Draw original image
        originalImage.draw(at: .zero)
        
        // Draw text bounding boxes
        for (index, textBox) in result.textBoxes.enumerated() {
            drawBoundingBox(context: context,
                          textBox: textBox,
                          imageSize: originalImage.size,
                          index: index,
                          result: result)
        }
        
        // Draw object detection bounding boxes
        let objectResult = objectDetectionResults.first { $0.assetIdentifier == result.assetIdentifier }
        if let objectResult = objectResult {
            for (index, objectBox) in objectResult.objectBoxes.enumerated() {
                drawObjectBoundingBox(context: context,
                                    objectBox: objectBox,
                                    imageSize: originalImage.size,
                                    index: index,
                                    result: result)
            }
        }
        
        let visualizationImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return visualizationImage
    }
    
    private func drawBoundingBox(context: CGContext, textBox: TextBoundingBox, imageSize: CGSize, index: Int, result: OCRResult) {
        let rect = VisionCoordinateConverter.convertBoundingBox(textBox.boundingBox, to: imageSize)
        
        // Check if this text should be blurred (both sensitive AND text blur enabled)
        let isSensitive = textBox.classification?.isSensitive ?? false
        let shouldBlur = isSensitive && (textBlurStates[result.assetIdentifier] ?? false)
        
        // Draw blur effect for sensitive text if enabled
        if shouldBlur {
            drawBlurEffect(context: context, rect: rect, imageSize: imageSize)
        }
        
        // Default color for text bounding box
        let boxColor = UIColor.systemBlue
        
        // Draw bounding box
        context.setLineWidth(2.0)
        context.setStrokeColor(boxColor.cgColor)
        context.setFillColor(boxColor.withAlphaComponent(0.1).cgColor)
        
        context.fill(rect)
        context.stroke(rect)
        
        // Draw index label
        drawIndexLabel(context: context, index: index + 1, rect: rect, imageSize: imageSize)
        
        // Draw red dot if sensitive (always shown regardless of blur state)
        if isSensitive {
            drawSensitiveDot(context: context, rect: rect, imageSize: imageSize)
        }
    }
    
    // Draw object bounding box
    private func drawObjectBoundingBox(context: CGContext, objectBox: ObjectBoundingBox, imageSize: CGSize, index: Int, result: OCRResult) {
        let rect = VisionCoordinateConverter.convertBoundingBox(objectBox.boundingBox, to: imageSize)
        
        // Check if this object should be blurred (both sensitive AND object blur enabled)
        let shouldBlur = objectBox.isSensitive && (objectBlurStates[result.assetIdentifier] ?? false)
        
        // Draw blur effect for sensitive objects if enabled
        if shouldBlur {
            drawBlurEffect(context: context, rect: rect, imageSize: imageSize)
        }
        
        // Use different color for object boxes (green instead of blue)
        let boxColor = UIColor.systemGreen
        
        // Draw bounding box
        context.setLineWidth(2.0)
        context.setStrokeColor(boxColor.cgColor)
        context.setFillColor(boxColor.withAlphaComponent(0.1).cgColor)
        
        context.fill(rect)
        context.stroke(rect)
        
        // Draw square index label for objects (different from circular text labels)
        drawObjectIndexLabel(context: context, index: index + 1, rect: rect, imageSize: imageSize)
        
        // Draw red dot if sensitive
        if objectBox.isSensitive {
            drawSensitiveDot(context: context, rect: rect, imageSize: imageSize)
        }
    }
    
    // Draw blur effect
    private func drawBlurEffect(context: CGContext, rect: CGRect, imageSize: CGSize) {
        // Create a pixelated/mosaic effect for sensitive areas
        let pixelSize: CGFloat = 8.0
        let expandedRect = rect.insetBy(dx: -2, dy: -2)
        
        context.saveGState()
        
        // Create a mosaic/pixelated effect
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
                
                // Use random gray colors to simulate pixelation
                let grayValue = CGFloat.random(in: 0.7...0.9)
                context.setFillColor(UIColor(white: grayValue, alpha: 0.9).cgColor)
                context.fill(pixelRect)
            }
        }
        
        context.restoreGState()
    }

    private func drawIndexLabel(context: CGContext, index: Int, rect: CGRect, imageSize: CGSize) {
        let fontSize = max(min(imageSize.width, imageSize.height) * 0.03, 16.0)
        let padding: CGFloat = 4
        
        let indexText = "\(index)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: UIColor.white
        ]
        
        let attributedString = NSAttributedString(string: indexText, attributes: attributes)
        let textSize = attributedString.size()
        
        let labelWidth = textSize.width + padding * 2
        let labelHeight = textSize.height + padding * 2
        
        // Position at top-right of bounding box
        let labelRect = CGRect(
            x: rect.origin.x + rect.width - labelWidth,
            y: rect.origin.y - labelHeight / 2,
            width: labelWidth,
            height: labelHeight
        )
        
        // Draw circular background
        context.setFillColor(UIColor.systemBlue.cgColor)
        context.fillEllipse(in: labelRect)
        
        // Draw text
        let textRect = CGRect(
            x: labelRect.origin.x + padding,
            y: labelRect.origin.y + padding,
            width: textSize.width,
            height: textSize.height
        )
        indexText.draw(in: textRect, withAttributes: attributes)
    }
    
    // Draw object index label (square shape)
    private func drawObjectIndexLabel(context: CGContext, index: Int, rect: CGRect, imageSize: CGSize) {
        let fontSize = max(min(imageSize.width, imageSize.height) * 0.03, 16.0)
        let padding: CGFloat = 4
        
        let indexText = "\(index)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: UIColor.white
        ]
        
        let attributedString = NSAttributedString(string: indexText, attributes: attributes)
        let textSize = attributedString.size()
        
        let labelWidth = textSize.width + padding * 2
        let labelHeight = textSize.height + padding * 2
        
        // Position at top-left of bounding box (different from text labels)
        let labelRect = CGRect(
            x: rect.origin.x - labelWidth / 2,
            y: rect.origin.y - labelHeight / 2,
            width: labelWidth,
            height: labelHeight
        )
        
        // Draw square background (different from circular text labels)
        context.setFillColor(UIColor.systemGreen.cgColor)
        context.fill(labelRect)
        
        // Draw text
        let textRect = CGRect(
            x: labelRect.origin.x + padding,
            y: labelRect.origin.y + padding,
            width: textSize.width,
            height: textSize.height
        )
        indexText.draw(in: textRect, withAttributes: attributes)
    }

    private func drawSensitiveDot(context: CGContext, rect: CGRect, imageSize: CGSize) {
        // Calculate dot size based on image size
        let dotSize = max(min(imageSize.width, imageSize.height) * 0.04, 20.0)
        
        // Position at top-left of bounding box
        let dotRect = CGRect(
            x: rect.origin.x - dotSize / 2,
            y: rect.origin.y - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        
        // Draw red dot with white border
        context.setFillColor(UIColor.systemRed.cgColor)
        context.fillEllipse(in: dotRect)
        
        // Add white border to make it more visible
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(3.0)
        context.strokeEllipse(in: dotRect)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UIScrollViewDelegate

extension OCRVisualizationViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}

// MARK: - Vision Coordinate Converter

struct VisionCoordinateConverter {
    static func convertBoundingBox(_ visionBox: CGRect, to imageSize: CGSize) -> CGRect {
        // Vision uses normalized coordinates with origin at bottom-left
        // UIKit uses coordinates with origin at top-left
        
        let x = visionBox.origin.x * imageSize.width
        let y = (1 - visionBox.origin.y - visionBox.height) * imageSize.height
        let width = visionBox.width * imageSize.width
        let height = visionBox.height * imageSize.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
