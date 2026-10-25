import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import VisionKit

/// Import a credit card statement -> read it -> review the transactions ->
/// save the ticked ones as expenses. Mirrors ScanFlowView's phases.
struct StatementFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [Expense]

    private enum Phase {
        case choose
        case processing
        case review(ParsedStatement, [StatementLine])
        case failed(String)
    }

    @State private var phase: Phase = .choose
    @State private var showImporter = false
    @State private var showCamera = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .choose:
                    chooseView
                case .processing:
                    processingView
                case .review(let statement, let lines):
                    StatementReviewView(statement: statement, lines: lines, onDone: { dismiss() })
                case .failed(let message):
                    failedView(message)
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                start { try Self.readPDF(at: url) }
            case .failure(let error):
                phase = .failed("Couldn't open that file. \(error.localizedDescription)")
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            MultiPageScannerView(
                onScan: { images in
                    showCamera = false
                    startPages(images)
                },
                onCancel: { showCamera = false },
                onError: { error in
                    showCamera = false
                    phase = .failed("The camera couldn't scan that. \(error.localizedDescription)")
                }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: Phases

    private var chooseView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Import a card statement")
                .font(.title2.bold())
            Text("Fin4U reads every transaction and sorts it into a category. You'll check them before anything is saved.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Charges you already scanned as receipts are spotted and left out, and card payments are skipped.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()

            Button { showImporter = true } label: {
                Label("Choose statement PDF", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if DocumentScannerView.isSupported {
                Button { showCamera = true } label: {
                    Label("Scan paper statement", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            // Existing users accepted the receipt-only disclosure, so the
            // statement-specific privacy note is shown here, every time.
            Label("Your statement is sent to Fin4U's server and Anthropic's Claude to read the transactions, and isn't stored there. Only the last 4 card digits are kept.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Tip: in your bank's app, download the statement, then tap Share → Save to Files.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(24)
        .navigationTitle("Card statement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Reading your statement…")
                .font(.headline)
            Text("A full statement can take a minute or two.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    task?.cancel()
                    dismiss()
                }
            }
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("That didn't work")
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button { phase = .choose } label: {
                Text("Try again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: Work

    /// Files picked from iCloud Drive / Files are security-scoped.
    private static func readPDF(at url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private func start(_ loadPDF: @escaping () throws -> Data) {
        phase = .processing
        task = Task {
            do {
                let pdf = try loadPDF()
                await finish { try await ReceiptAPI.shared.parseStatement(pdf: pdf) }
            } catch {
                phase = .failed("Couldn't open that file.")
            }
        }
    }

    private func startPages(_ images: [UIImage]) {
        phase = .processing
        task = Task {
            let pages = images.compactMap { ImagePrep.jpeg(from: $0) }
            guard !pages.isEmpty else {
                phase = .failed("Couldn't open those pages.")
                return
            }
            await finish { try await ReceiptAPI.shared.parseStatement(pages: pages) }
        }
    }

    private func finish(_ call: () async throws -> ParsedStatement) async {
        do {
            let statement = try await call()
            if Task.isCancelled { return }
            let lines = StatementImport.lines(for: statement, existing: StatementImport.existing(from: expenses))
            if lines.isEmpty {
                phase = .failed("No purchases were found on that statement.")
            } else {
                phase = .review(statement, lines)
            }
        } catch is CancellationError {
            // The user backed out; nothing to show.
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// Apple's document camera, returning every scanned page (the receipt
/// scanner only keeps the first).
struct MultiPageScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
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
        let parent: MultiPageScannerView
        init(parent: MultiPageScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { parent.onCancel(); return }
            parent.onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError(error)
        }
    }
}
