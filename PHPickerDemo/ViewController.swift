/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's main view controller object.
*/

import UIKit
import PhotosUI
import AVKit

class ViewController: UIViewController {
    
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var livePhotoView: PHLivePhotoView! {
        didSet {
            livePhotoView.contentMode = .scaleAspectFit
        }
    }
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var ocrButton: UIButton!
    private var playButtonVideoURL: URL?

    private var selection = [String: PHPickerResult]()
    private var selectedAssetIdentifiers = [String]()
    private var selectedAssetIdentifierIterator: IndexingIterator<[String]>?
    private var currentAssetIdentifier: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Debug: Check if OCR button is connected
        if ocrButton != nil {
            print("✅ OCR Button is connected")
            ocrButton.isHidden = false  // Initially hide it until images are selected
        } else {
            print("❌ OCR Button is NOT connected - check storyboard connection")
        }
    }
    
    @IBAction func runOCROnSelectedImages(_ sender: UIButton) {
        print("🔘 OCR Button clicked!")
        print("📸 Selection count: \(selection.count)")
        print("📋 Selection contents: \(Array(selection.keys))")
        
        guard !selection.isEmpty else {
            print("❌ No images selected, showing alert")
            showAlert(title: "No Images", message: "Please select at least one image before running OCR.")
            return
        }
        
        print("✅ Images found, starting OCR processing...")
        
        ocrButton.isEnabled = false
        ocrButton.setTitle("Processing...", for: .disabled)
        print("🔄 Button disabled and title changed")
        
        let processor = OCRProcessor()
        processor.delegate = self
        print("🏭 OCR Processor created, delegate set")
        
        print("🚀 About to call processImages...")
        processor.processImages(from: selection)
        print("📤 processImages called")
    }

    @IBAction func presentPickerForImagesAndVideos(_ sender: Any) {
        presentPicker(filter: nil)
    }
    
    @IBAction func presentPickerForImagesIncludingLivePhotos(_ sender: Any) {
        presentPicker(filter: PHPickerFilter.images)
    }

    @IBAction func presentPickerForLivePhotosOnly(_ sender: Any) {
        presentPicker(filter: PHPickerFilter.livePhotos)
    }
    
    private func presentPicker(filter: PHPickerFilter?) {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        
        // Set the filter type according to the user’s selection.
        configuration.filter = filter
        // Set the mode to avoid transcoding, if possible, if your app supports arbitrary image/video encodings.
        configuration.preferredAssetRepresentationMode = .current
        // Set the selection behavior to respect the user’s selection order.
        configuration.selection = .ordered
        // Set the selection limit to enable multiselection.
        configuration.selectionLimit = 0
        // Set the preselected asset identifiers with the identifiers that the app tracks.
        configuration.preselectedAssetIdentifiers = selectedAssetIdentifiers
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        displayNext()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let viewController = segue.destination as? AVPlayerViewController, let videoURL = playButtonVideoURL {
            viewController.player = AVPlayer(url: videoURL)
            viewController.player?.play()
        }
    }
}

private extension ViewController {
    
    func displayNext() {
        guard let assetIdentifier = selectedAssetIdentifierIterator?.next() else { return }
        currentAssetIdentifier = assetIdentifier
        
        let progress: Progress?
        let itemProvider = selection[assetIdentifier]!.itemProvider
        if itemProvider.canLoadObject(ofClass: PHLivePhoto.self) {
            progress = itemProvider.loadObject(ofClass: PHLivePhoto.self) { [weak self] livePhoto, error in
                DispatchQueue.main.async {
                    self?.handleCompletion(assetIdentifier: assetIdentifier, object: livePhoto, error: error)
                }
            }
        }
        else if itemProvider.canLoadObject(ofClass: UIImage.self) {
            progress = itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                DispatchQueue.main.async {
                    self?.handleCompletion(assetIdentifier: assetIdentifier, object: image, error: error)
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            progress = itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                do {
                    guard let url = url, error == nil else {
                        throw error ?? NSError(domain: NSFileProviderErrorDomain, code: -1, userInfo: nil)
                    }
                    let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: localURL)
                    try FileManager.default.copyItem(at: url, to: localURL)
                    DispatchQueue.main.async {
                        self?.handleCompletion(assetIdentifier: assetIdentifier, object: localURL)
                    }
                } catch let catchedError {
                    DispatchQueue.main.async {
                        self?.handleCompletion(assetIdentifier: assetIdentifier, object: nil, error: catchedError)
                    }
                }
            }
        } else {
            progress = nil
        }
        
        displayProgress(progress)
    }
    
    func handleCompletion(assetIdentifier: String, object: Any?, error: Error? = nil) {
        guard currentAssetIdentifier == assetIdentifier else { return }
        if let livePhoto = object as? PHLivePhoto {
            displayLivePhoto(livePhoto)
        } else if let image = object as? UIImage {
            displayImage(image)
        } else if let url = object as? URL {
            displayVideoPlayButton(forURL: url)
        } else if let error = error {
            print("Couldn't display \(assetIdentifier) with error: \(error)")
            displayErrorImage()
        } else {
            displayUnknownImage()
        }
    }
    
}

private extension ViewController {
    
    func displayEmptyImage() {
        displayImage(UIImage(systemName: "photo.on.rectangle.angled"))
    }
    
    func displayErrorImage() {
        displayImage(UIImage(systemName: "exclamationmark.circle"))
    }
    
    func displayUnknownImage() {
        displayImage(UIImage(systemName: "questionmark.circle"))
    }
    
    func displayProgress(_ progress: Progress?) {
        imageView.image = nil
        imageView.isHidden = true
        livePhotoView.livePhoto = nil
        livePhotoView.isHidden = true
        playButtonVideoURL = nil
        playButton.isHidden = true
        progressView.observedProgress = progress
        progressView.isHidden = progress == nil
    }
    
    func displayVideoPlayButton(forURL videoURL: URL?) {
        imageView.image = nil
        imageView.isHidden = true
        livePhotoView.livePhoto = nil
        livePhotoView.isHidden = true
        playButtonVideoURL = videoURL
        playButton.isHidden = videoURL == nil
        progressView.observedProgress = nil
        progressView.isHidden = true
    }
    
    func displayLivePhoto(_ livePhoto: PHLivePhoto?) {
        imageView.image = nil
        imageView.isHidden = true
        livePhotoView.livePhoto = livePhoto
        livePhotoView.isHidden = livePhoto == nil
        playButtonVideoURL = nil
        playButton.isHidden = true
        progressView.observedProgress = nil
        progressView.isHidden = true
    }
    
    func displayImage(_ image: UIImage?) {
        imageView.image = image
        imageView.isHidden = image == nil
        livePhotoView.livePhoto = nil
        livePhotoView.isHidden = true
        playButtonVideoURL = nil
        playButton.isHidden = true
        progressView.observedProgress = nil
        progressView.isHidden = true
    }
        
}

extension ViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        
        let existingSelection = self.selection
        var newSelection = [String: PHPickerResult]()
        for result in results {
            let identifier = result.assetIdentifier!
            newSelection[identifier] = existingSelection[identifier] ?? result
        }
        
        // Track the selection in case the user deselects it later.
        selection = newSelection
        selectedAssetIdentifiers = results.map(\.assetIdentifier!)
        selectedAssetIdentifierIterator = selectedAssetIdentifiers.makeIterator()
        
        if selection.isEmpty {
            displayEmptyImage()
        } else {
            displayNext()
        }
    }
}

// MARK: - OCR Integration Extension
// Add this to the end of your ViewController.swift file

extension ViewController: OCRProcessorDelegate {
    
    private var ocrProcessor: OCRProcessor {
        return OCRProcessor()
    }
    
    // MARK: - OCRProcessorDelegate Methods
    
    func ocrProcessor(_ processor: OCRProcessor, didStartProcessing totalImages: Int) {
        print("🎬 OCR DELEGATE: didStartProcessing called with \(totalImages) images")
        DispatchQueue.main.async {
            print("🎬 OCR DELEGATE: On main thread - starting processing UI update")
            self.progressView.isHidden = false
            self.progressView.progress = 0.0
            print("🎬 OCR DELEGATE: Progress view shown and reset")
        }
    }
    
    func ocrProcessor(_ processor: OCRProcessor, didProcessImage at: Int, of total: Int) {
        print("📊 OCR DELEGATE: didProcessImage called - \(at) of \(total)")
        DispatchQueue.main.async {
            self.progressView.progress = Float(at) / Float(total)
            print("📊 OCR DELEGATE: Progress updated to \(Float(at) / Float(total))")
        }
    }
    
    func ocrProcessor(_ processor: OCRProcessor, didCompleteWithResults results: [OCRResult]) {
        print("✅ OCR DELEGATE: didCompleteWithResults called with \(results.count) results")
        DispatchQueue.main.async {
            print("✅ OCR DELEGATE: On main thread - completing processing")
            self.progressView.isHidden = true
            self.handleOCRResults(results)
            self.enableOCRButton()
            print("✅ OCR DELEGATE: Processing complete, button re-enabled")
        }
    }
    
    func ocrProcessor(_ processor: OCRProcessor, didFailWithError error: Error) {
        print("❌ OCR DELEGATE: didFailWithError called - \(error.localizedDescription)")
        DispatchQueue.main.async {
            print("❌ OCR DELEGATE: On main thread - handling error")
            self.progressView.isHidden = true
            self.showAlert(title: "OCR Error", message: error.localizedDescription)
            self.enableOCRButton()
            print("❌ OCR DELEGATE: Error handled, button re-enabled")
        }
    }
    
    // MARK: - Helper Methods
    
    private func enableOCRButton() {
        print("🔄 Enabling OCR button")
        ocrButton.isEnabled = true
        ocrButton.setTitle("Run OCR", for: .normal)
        print("🔄 OCR button enabled and title reset")
    }
    
    private func handleOCRResults(_ results: [OCRResult]) {
        print("📊 Handling OCR results - \(results.count) results")
        
        var allTextBoxes: [TextBoundingBox] = []
        var totalProcessingTime: TimeInterval = 0
        var errorCount = 0
        var totalTextFound = 0
        
        for (index, result) in results.enumerated() {
            print("📋 Processing result \(index + 1)/\(results.count) for asset: \(result.assetIdentifier)")
            
            if let error = result.error {
                print("❌ OCR error for \(result.assetIdentifier): \(error.localizedDescription)")
                errorCount += 1
            } else {
                allTextBoxes.append(contentsOf: result.textBoxes)
                totalProcessingTime += result.processingTime
                totalTextFound += result.textBoxes.count
                
                print("✅ OCR completed for \(result.assetIdentifier):")
                print("   📝 Found \(result.textBoxes.count) text regions")
                print("   ⏱️ Processing time: \(String(format: "%.2f", result.processingTime))s")
                
                for (textIndex, textBox) in result.textBoxes.enumerated() {
                    print("   📄 Text \(textIndex + 1): '\(textBox.text)' (confidence: \(String(format: "%.2f", textBox.confidence)))")
                    print("   📍 Bounding box: \(textBox.boundingBox)")
                }
            }
        }
        
        let message = """
        OCR Processing Complete!
        
        Images processed: \(results.count)
        Text regions found: \(totalTextFound)
        Total processing time: \(String(format: "%.2f", totalProcessingTime))s
        Average time per image: \(String(format: "%.2f", totalProcessingTime / Double(results.count)))s
        Errors: \(errorCount)
        """
        
        print("🎉 Final OCR Summary:")
        print(message)
        
        showAlert(title: "OCR Results", message: message)
        
        // Optional: Display detailed results
        displayDetailedOCRResults(allTextBoxes)
    }
    
    private func displayDetailedOCRResults(_ textBoxes: [TextBoundingBox]) {
        // Print all extracted text for debugging
        print("\n=== ALL EXTRACTED TEXT ===")
        for (index, textBox) in textBoxes.enumerated() {
            print("\(index + 1). \"\(textBox.text)\" (confidence: \(String(format: "%.2f", textBox.confidence)))")
        }
        print("========================\n")
    }
    
    private func showAlert(title: String, message: String) {
        print("🚨 Showing alert: \(title) - \(message)")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
