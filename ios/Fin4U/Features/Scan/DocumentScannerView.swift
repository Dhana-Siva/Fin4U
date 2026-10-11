import SwiftUI
import VisionKit

/// Apple's document camera: finds the receipt's edges, corrects perspective
/// and glare. Not available in the Simulator (no camera), so callers check
/// `isSupported` and fall back to the photo picker.
struct DocumentScannerView: UIViewControllerRepresentable {
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    /// Called with the first page and the total number of pages scanned.
    let onScan: (UIImage, Int) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { parent.onCancel(); return }
            parent.onScan(scan.imageOfPage(at: 0), scan.pageCount)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError(error)
        }
    }
}
