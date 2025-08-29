//
//  OCRVisualizationViewController.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 29/8/25.
//  Copyright © 2025 Apple. All rights reserved.
//

//
//  OCRVisualizationViewController.swift
//  PHPickerDemo
//
//  Created by Yeo Meng Han on 29/8/25.
//

import UIKit
import PhotosUI

class OCRVisualizationViewController: UIViewController {
    
    private var scrollView: UIScrollView!
    private var imageView: UIImageView!
    private var segmentedControl: UISegmentedControl!
    private var infoLabel: UILabel!
    private var textDetailsView: UITextView!
    
    var ocrResults: [OCRResult] = []
    var selection: [String: PHPickerResult] = [:]
    
    private var currentImageIndex = 0
    private var loadedImages: [String: UIImage] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadAllImages()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "OCR Visualization"
        
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
        
        // Create text details view
        textDetailsView = UITextView()
        textDetailsView.translatesAutoresizingMaskIntoConstraints = false
        textDetailsView.isEditable = false
        textDetailsView.font = UIFont.systemFont(ofSize: 14)
        textDetailsView.layer.borderColor = UIColor.systemGray4.cgColor
        textDetailsView.layer.borderWidth = 1
        textDetailsView.layer.cornerRadius = 8
        textDetailsView.backgroundColor = .systemBackground
        
        // Add subviews
        view.addSubview(segmentedControl)
        view.addSubview(infoLabel)
        view.addSubview(scrollView)
        view.addSubview(textDetailsView)
        scrollView.addSubview(imageView)
        
        // Setup constraints
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
            scrollView.bottomAnchor.constraint(equalTo: textDetailsView.topAnchor, constant: -8),
            
            // Image view
            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            
            // Text details view
            textDetailsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textDetailsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textDetailsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            textDetailsView.heightAnchor.constraint(equalToConstant: 200)
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
        let processingTime = String(format: "%.2f", result.processingTime)
        
        if let error = result.error {
            infoLabel.text = "❌ Error: \(error.localizedDescription)"
            infoLabel.textColor = .systemRed
        } else {
            infoLabel.text = "✅ Found \(textCount) text regions • Processing time: \(processingTime)s"
            infoLabel.textColor = .label
        }
    }
    
    private func updateTextDetails(for result: OCRResult) {
        if result.textBoxes.isEmpty {
            textDetailsView.text = "No text detected in this image."
        } else {
            var details = "Detected Text:\n\n"
            for (index, textBox) in result.textBoxes.enumerated() {
                let confidence = String(format: "%.2f", textBox.confidence)
                details += "\(index + 1). \"\(textBox.text)\"\n"
                details += "   Confidence: \(confidence)\n"
                details += "   Bounds: x=\(String(format: "%.3f", textBox.boundingBox.origin.x)), "
                details += "y=\(String(format: "%.3f", textBox.boundingBox.origin.y)), "
                details += "w=\(String(format: "%.3f", textBox.boundingBox.width)), "
                details += "h=\(String(format: "%.3f", textBox.boundingBox.height))\n\n"
            }
            textDetailsView.text = details
        }
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
        
        // Draw bounding boxes
        for (index, textBox) in result.textBoxes.enumerated() {
            drawBoundingBox(context: context,
                          textBox: textBox,
                          imageSize: originalImage.size,
                          index: index)
        }
        
        let visualizationImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return visualizationImage
    }
    
    private func drawBoundingBox(context: CGContext, textBox: TextBoundingBox, imageSize: CGSize, index: Int) {
        // Convert Vision coordinates to UIKit coordinates
        let rect = VisionCoordinateConverter.convertBoundingBox(textBox.boundingBox, to: imageSize)
        
        // Set up drawing properties
        context.setLineWidth(3.0)
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.2).cgColor)
        
        // Draw filled rectangle
        context.fill(rect)
        
        // Draw border
        context.stroke(rect)
        
        // Draw index number
        drawIndexLabel(context: context, index: index + 1, rect: rect, imageSize: imageSize)
    }
    
    private func drawIndexLabel(context: CGContext, index: Int, rect: CGRect, imageSize: CGSize) {
        let fontSize = max(min(imageSize.width, imageSize.height) * 0.03, 16.0)
        
        let text = "\(index)"
        let textColor = UIColor.white
        let backgroundColor = UIColor.systemRed
        
        // Calculate text size
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: textColor
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        // Position label at top-left of bounding box, with some padding
        let padding: CGFloat = 4
        let labelRect = CGRect(
            x: rect.origin.x,
            y: max(0, rect.origin.y - textSize.height - padding * 2),
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        
        // Draw background rectangle for the label
        context.setFillColor(backgroundColor.cgColor)
        context.fill(labelRect)
        
        // Draw text using NSString drawing (simpler than Core Graphics text)
        let textRect = CGRect(
            x: labelRect.origin.x + padding,
            y: labelRect.origin.y + padding,
            width: textSize.width,
            height: textSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
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
