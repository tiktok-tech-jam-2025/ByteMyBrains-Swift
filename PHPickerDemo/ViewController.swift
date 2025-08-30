/*
See the LICENSE.txt file for this sample's licensing information.

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
    
    // Store OCRProcessor as a property
    private var ocrProcessor: OCRProcessor?
    
    // Store ObjectDetectionProcessor as a property
    private var objectDetectionProcessor: ObjectDetectionProcessor?
    
    // Combined results storage
    private var combinedResults: [(ocrResult: OCRResult, objectResult: ObjectDetectionResult?)] = []
    private var completedProcessors = 0
    private let totalProcessors = 2
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Debug: Check if OCR button is connected
        if ocrButton != nil {
            print("✅ OCR Button is connected")
            ocrButton.isHidden = false  // Initially hide it until images are selected
        } else {
            print("❌ OCR Button is NOT connected - check storyboard connection")
        }
        
        // Debug: Check if the text classification model is working
        testTextClassification()
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
        
        print("✅ Images found, starting OCR and Object Detection processing...")
        
        ocrButton.isEnabled = false
        ocrButton.setTitle("Processing...", for: .disabled)
        print("🔄 Button disabled and title changed")
        
        // Reset combined results and processor counter
        combinedResults = []
        completedProcessors = 0
        
        // Start OCR processing
        ocrProcessor = OCRProcessor()
        ocrProcessor?.delegate = self
        print("🏭 OCR Processor created, delegate set")
        
        // Start Object Detection processing
        objectDetectionProcessor = ObjectDetectionProcessor()
        objectDetectionProcessor?.delegate = self
        print("🤖 Object Detection Processor created, delegate set")
        
        print("🚀 About to call processImages for both processors...")
        ocrProcessor?.processImages(from: selection)
        objectDetectionProcessor?.processImages(from: selection)
        print("📤 Both processImages called")
    }
    
    private func testTextClassification() {
        let manager = TextClassificationManager()
        
        print("\n🧪 Testing Text Classification")
        print(String(repeating: "=", count: 50))
        
        // Print model status
        let status = manager.getModelStatus()
        print("📊 Model Status:")
        for (key, value) in status {
            print("   \(key): \(value)")
        }
        
        // Test classification with sample texts
        let testTexts = [
            "S1234567A",
            "T9876543B",
            "john.doe@email.com",
            "user@gmail.com",
            "1234-5678-9012-3456",
            "+65 9123 4567",
            "91234567",
            "01/01/1990",
            "15-Mar-1985",
            "123 Main Street Singapore 123456",
            "Block 123 Toa Payoh Central",
            "Hello world",
            "This is just regular text"
        ]
        
        print("\n🔍 Classification Results:")
        print(String(repeating: "-", count: 50))
        
        for text in testTexts {
            let result = manager.classify(text: text)
            let emoji = result.isSensitive ? "🔴" : "🟢"
            print("\(emoji) '\(text)'")
            print("   → \(result.predictedClass.uppercased()) (confidence: \(String(format: "%.2f", result.confidence)), \(result.method), \(String(format: "%.1f", result.processingTime * 1000))ms)")
        }
        
        print("\n" + String(repeating: "=", count: 50))
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
        
        // Set the filter type according to the user's selection.
        configuration.filter = filter
        // Set the mode to avoid transcoding, if possible, if your app supports arbitrary image/video encodings.
        configuration.preferredAssetRepresentationMode = .current
        // Set the selection behavior to respect the user's selection order.
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
extension ViewController: OCRProcessorDelegate {
    
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
        
        // Store OCR results and check if both processors are complete
        handleOCRCompletion(with: results)
    }
    
    func ocrProcessor(_ processor: OCRProcessor, didFailWithError error: Error) {
        print("❌ OCR DELEGATE: didFailWithError called - \(error.localizedDescription)")
        DispatchQueue.main.async {
            print("❌ OCR DELEGATE: On main thread - handling error")
            self.progressView.isHidden = true
            self.showAlert(title: "OCR Error", message: error.localizedDescription)
            self.enableOCRButton()
            
            // Clear processors when error occurs
            self.ocrProcessor = nil
            self.objectDetectionProcessor = nil
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
    
    private func showAlert(title: String, message: String) {
        print("🚨 Showing alert: \(title) - \(message)")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Object Detection Integration Extension
extension ViewController: ObjectDetectionProcessorDelegate {
    
    func objectDetectionProcessor(_ processor: ObjectDetectionProcessor, didStartProcessing totalImages: Int) {
        print("🤖 OBJECT DETECTION DELEGATE: didStartProcessing called with \(totalImages) images")
        // Progress is already handled by OCR delegate
    }
    
    func objectDetectionProcessor(_ processor: ObjectDetectionProcessor, didProcessImage at: Int, of total: Int) {
        print("🤖 OBJECT DETECTION DELEGATE: didProcessImage called - \(at) of \(total)")
        // Progress updates handled by OCR for simplicity
    }
    
    func objectDetectionProcessor(_ processor: ObjectDetectionProcessor, didCompleteWithResults results: [ObjectDetectionResult]) {
        print("✅ OBJECT DETECTION DELEGATE: didCompleteWithResults called with \(results.count) results")
        
        // Store Object Detection results and check if both processors are complete
        handleObjectDetectionCompletion(with: results)
    }
    
    func objectDetectionProcessor(_ processor: ObjectDetectionProcessor, didFailWithError error: Error) {
        print("❌ OBJECT DETECTION DELEGATE: didFailWithError called - \(error.localizedDescription)")
        DispatchQueue.main.async {
            print("❌ OBJECT DETECTION DELEGATE: On main thread - handling error")
            self.showAlert(title: "Object Detection Error", message: error.localizedDescription)
            
            // Continue with just OCR results if object detection fails
            self.handleObjectDetectionCompletion(with: [])
        }
    }
}

// MARK: - Combined Results Handling
extension ViewController {
    
    private func handleOCRCompletion(with ocrResults: [OCRResult]) {
        // Store OCR results in combined structure
        for ocrResult in ocrResults {
            if let existingIndex = combinedResults.firstIndex(where: { $0.ocrResult.assetIdentifier == ocrResult.assetIdentifier }) {
                combinedResults[existingIndex] = (ocrResult, combinedResults[existingIndex].objectResult)
            } else {
                combinedResults.append((ocrResult, nil))
            }
        }
        
        completedProcessors += 1
        checkBothProcessorsComplete()
    }
    
    private func handleObjectDetectionCompletion(with objectResults: [ObjectDetectionResult]) {
        // Store Object Detection results in combined structure
        for objectResult in objectResults {
            if let existingIndex = combinedResults.firstIndex(where: { $0.ocrResult.assetIdentifier == objectResult.assetIdentifier }) {
                combinedResults[existingIndex] = (combinedResults[existingIndex].ocrResult, objectResult)
            } else {
                // Create placeholder OCR result if object detection completes first
                let placeholderOCR = OCRResult(assetIdentifier: objectResult.assetIdentifier, textBoxes: [], processingTime: 0, classificationTime: 0, error: nil)
                combinedResults.append((placeholderOCR, objectResult))
            }
        }
        
        completedProcessors += 1
        checkBothProcessorsComplete()
    }
    
    private func checkBothProcessorsComplete() {
        guard completedProcessors >= totalProcessors else { return }
        
        DispatchQueue.main.async {
            print("🎉 Both processors completed!")
            self.progressView.isHidden = true
            self.handleCombinedResults()
            self.enableOCRButton()
            
            // Clear processors when done
            self.ocrProcessor = nil
            self.objectDetectionProcessor = nil
            print("✅ All processing complete, button re-enabled")
        }
    }
    
    private func handleCombinedResults() {
        print("📊 Handling combined OCR and Object Detection results - \(combinedResults.count) results")
        
        var totalTextBoxes = 0
        var totalObjectBoxes = 0
        var totalOCRTime: TimeInterval = 0
        var totalObjectDetectionTime: TimeInterval = 0
        var errorCount = 0
        var totalSensitiveText = 0
        var totalSensitiveObjects = 0
        
        for (index, combinedResult) in combinedResults.enumerated() {
            let ocrResult = combinedResult.ocrResult
            let objectResult = combinedResult.objectResult
            
            print("📋 Processing combined result \(index + 1)/\(combinedResults.count) for asset: \(ocrResult.assetIdentifier)")
            
            // Process OCR results
            if let error = ocrResult.error {
                print("❌ OCR error for \(ocrResult.assetIdentifier): \(error.localizedDescription)")
                errorCount += 1
            } else {
                totalTextBoxes += ocrResult.textBoxes.count
                totalOCRTime += ocrResult.totalProcessingTime
                totalSensitiveText += ocrResult.sensitiveTextCount
                
                print("✅ OCR completed for \(ocrResult.assetIdentifier):")
                print("   📝 Found \(ocrResult.textBoxes.count) text regions (\(ocrResult.sensitiveTextCount) sensitive)")
                print("   ⏱️ Processing time: \(String(format: "%.2f", ocrResult.totalProcessingTime))s")
            }
            
            // Process Object Detection results
            if let objectResult = objectResult {
                if let error = objectResult.error {
                    print("❌ Object Detection error for \(objectResult.assetIdentifier): \(error.localizedDescription)")
                    errorCount += 1
                } else {
                    totalObjectBoxes += objectResult.totalObjectCount
                    totalObjectDetectionTime += objectResult.processingTime
                    totalSensitiveObjects += objectResult.sensitiveObjectCount
                    
                    print("✅ Object Detection completed for \(objectResult.assetIdentifier):")
                    print("   🎯 Found \(objectResult.totalObjectCount) objects (\(objectResult.sensitiveObjectCount) sensitive)")
                    print("   ⏱️ Processing time: \(String(format: "%.2f", objectResult.processingTime))s")
                }
            }
        }
        
        let message = """
        Processing Complete!
        
        Images processed: \(combinedResults.count)
        
        OCR Results:
        • Text regions: \(totalTextBoxes) (\(totalSensitiveText) sensitive)
        • Processing time: \(String(format: "%.2f", totalOCRTime))s
        
        Object Detection Results:
        • Objects detected: \(totalObjectBoxes) (\(totalSensitiveObjects) sensitive)
        • Processing time: \(String(format: "%.2f", totalObjectDetectionTime))s
        
        Total errors: \(errorCount)
        """
        
        print("🎉 Final Combined Summary:")
        print(message)
        
        // Show results alert with option to view visualization
        let alert = UIAlertController(title: "Processing Results", message: message, preferredStyle: .alert)
       
        alert.addAction(UIAlertAction(title: "View Visualization", style: .default) { _ in
            self.showCombinedVisualization()
        })
       
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        present(alert, animated: true)
    }
    
    private func showCombinedVisualization() {
        let visualizationVC = OCRVisualizationViewController()
        
        // Pass OCR results (existing)
        visualizationVC.ocrResults = combinedResults.map { $0.ocrResult }
        
        // Pass Object Detection results
        visualizationVC.objectDetectionResults = combinedResults.compactMap { $0.objectResult }
        
        visualizationVC.selection = selection
        
        let navController = UINavigationController(rootViewController: visualizationVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
}
