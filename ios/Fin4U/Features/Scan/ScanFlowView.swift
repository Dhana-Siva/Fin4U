import SwiftUI
import SwiftData
import PhotosUI

/// Choose a source -> read the receipt -> review and save. Also offers
/// manual entry, both as an escape hatch when a scan can't be read and for
/// receipts the user simply wants to type in.
struct ScanFlowView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case choose
        case processing
        case review(ExpenseDraft)
        case failed(String)
        case statement(ParsedStatement, [StatementLine])
    }

    @State private var phase: Phase = .choose
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var task: Task<Void, Never>?
    /// The last photo sent, kept so a "not a receipt" can be retried as a
    /// card statement without picking it again.
    @State private var lastJPEG: Data?
    @Query private var expenses: [Expense]

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .choose:
                    chooseView
                case .processing:
                    processingView
                case .review(let draft):
                    ReviewView(draft: draft, onClose: { dismiss() })
                case .failed(let message):
                    failedView(message)
                case .statement(let statement, let lines):
                    StatementReviewView(statement: statement, lines: lines, onDone: { dismiss() })
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentScannerView(
                onScan: { image, pages in
                    showCamera = false
                    let note = pages > 1 ? "Only the first of \(pages) scanned pages was read. Scan a long receipt as one page." : nil
                    start({ image }, note: note)
                },
                onCancel: { showCamera = false },
                onError: { error in
                    showCamera = false
                    phase = .failed("The camera couldn't scan that. \(error.localizedDescription)")
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            start({
                guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
                return UIImage(data: data)
            }, note: nil)
        }
    }

    // MARK: Phases

    private var chooseView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Scan a receipt")
                .font(.title2.bold())
            Text("Fin4U reads the items and prices for you. You'll check everything before it's saved.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Lay the receipt flat, in good light.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()

            if DocumentScannerView.isSupported {
                Button { showCamera = true } label: {
                    Label("Scan with camera", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button("Enter manually instead") {
                phase = .review(ExpenseDraft())
            }
            .font(.subheadline)
            .padding(.top, 4)
        }
        .padding(24)
        .navigationTitle("New expense")
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
            Text("Reading your receipt…")
                .font(.headline)
            Text("This usually takes a few seconds.")
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
            // People often scan a statement page here by mistake.
            if lastJPEG != nil {
                Button { retryAsStatement() } label: {
                    Label("Read it as a card statement", systemImage: "creditcard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Button { phase = .choose } label: {
                Text("Try again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Enter manually instead") {
                phase = .review(ExpenseDraft())
            }
            .font(.subheadline)
        }
        .padding(24)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: Work

    /// Runs `loadImage`, then uploads and parses the result. Switches to the
    /// processing screen immediately; every outcome lands on review or
    /// failed (or nowhere, if cancelled).
    private func retryAsStatement() {
        guard let jpeg = lastJPEG else { return }
        phase = .processing
        task = Task {
            do {
                let statement = try await ReceiptAPI.shared.parseStatement(pages: [jpeg])
                if Task.isCancelled { return }
                let lines = StatementImport.lines(for: statement, existing: StatementImport.existing(from: expenses))
                phase = lines.isEmpty
                    ? .failed("No purchases were found on that statement.")
                    : .statement(statement, lines)
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func start(_ loadImage: @escaping () async -> UIImage?, note: String?) {
        phase = .processing
        task = Task {
            guard let image = await loadImage(),
                  let jpeg = ImagePrep.jpeg(from: image)
            else {
                if !Task.isCancelled { phase = .failed("Couldn't open that image.") }
                return
            }
            do {
                lastJPEG = jpeg
                let parsed = try await ReceiptAPI.shared.parse(jpeg: jpeg)
                if Task.isCancelled { return }
                let draft = ExpenseDraft(parsed: parsed, image: jpeg)
                if let note { draft.notes.append(note) }
                phase = .review(draft)
            } catch is CancellationError {
                // The user backed out; nothing to show.
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
