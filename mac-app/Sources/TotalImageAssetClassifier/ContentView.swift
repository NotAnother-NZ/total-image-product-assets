import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    @State private var isDropTargeted = false
    @State private var showResetConfirmation = false

    var body: some View {
        Group {
            if model.rootURL == nil {
                emptyState
            } else {
                classifier
            }
        }
        .frame(minWidth: 980, minHeight: 700)
        .alert(
            "Something needs attention",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "Clear generated WebPs and saved progress?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear generated outputs & progress", role: .destructive) {
                model.resetGeneratedOutputsAndProgress()
            }
        } message: {
            Text("This removes nested webp folders and the classifier progress file. Original source images are not touched.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)

            Text("Total Image Asset Classifier")
                .font(.largeTitle.bold())

            Text("Drop the main assets folder here.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Classify each image as Model or Product. Conversion continues in the background and progress is saved immediately.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620)

            Button("Choose Assets Folder…") {
                model.chooseFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if model.magickPath == nil {
                Label(
                    "ImageMagick is required: brew install imagemagick",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                )
                .padding(24)
        )
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isDropTargeted,
            perform: handleDrop
        )
    }

    private var classifier: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if model.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Scanning assets…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let item = model.currentItem {
                HStack(spacing: 0) {
                    previewPanel(item)

                    Divider()

                    classificationPanel(item)
                        .frame(width: 330)
                }

            } else {
                completedState
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.rootURL?.lastPathComponent ?? "Assets")
                        .font(.headline)

                    Text(model.rootURL?.path ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Choose Folder…") {
                    model.chooseFolder()
                }

                Button("Reveal") {
                    model.revealOutputFolder()
                }

                Menu {
                    Button(
                        "Clear generated outputs & progress…",
                        role: .destructive
                    ) {
                        showResetConfirmation = true
                    }
                    .disabled(model.activeProcessingCount > 0)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            HStack(spacing: 14) {
                ProgressView(
                    value: Double(model.classifiedCount),
                    total: Double(max(model.totalCount, 1))
                )

                Text("\(model.classifiedCount) / \(model.totalCount) classified")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Label(
                    "\(model.activeProcessingCount) processing",
                    systemImage: "gearshape.2"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("\(model.queuedProcessingCount) queued")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if model.failedCount > 0 {
                    Text("\(model.failedCount) failed")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.red)
                }
            }

            if let message = model.message {
                HStack {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(16)
    }

    private func previewPanel(_ item: AssetItem) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if let image = NSImage(contentsOf: item.sourceURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(28)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)

                        Text("Preview unavailable")
                            .foregroundStyle(.secondary)

                        Text("The file can still be processed by ImageMagick.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(spacing: 4) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func classificationPanel(_ item: AssetItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What is this?")
                .font(.title2.bold())

            Text("Classification is saved immediately. Processing is queued in the background, so you can keep going.")
                .foregroundStyle(.secondary)

            Button {
                model.classify(.model)
            } label: {
                classificationButtonLabel(
                    title: "Model",
                    subtitle: "Preserve composition and aspect ratio",
                    systemImage: "person.crop.rectangle"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("m", modifiers: [])

            Button {
                model.classify(.product)
            } label: {
                classificationButtonLabel(
                    title: "Product",
                    subtitle: "Normalize onto a consistent 3:4 white canvas",
                    systemImage: "tshirt"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut("p", modifiers: [])

            Divider()

            Button("Undo Last Classification") {
                model.undoLastClassification()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!model.canUndo)

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("Keyboard")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Text("M  Model")
                Text("P  Product")
                Text("⌘Z  Undo")
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func classificationButtonLabel(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 54)
    }

    private var completedState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: model.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 58))
                .foregroundStyle(model.failedCount == 0 ? .green : .orange)

            Text("Classification complete")
                .font(.largeTitle.bold())

            if model.activeProcessingCount > 0 || model.queuedProcessingCount > 0 {
                Text("Background processing is still finishing.")
                    .foregroundStyle(.secondary)

                ProgressView()
            } else if model.failedCount > 0 {
                Text("\(model.failedCount) image(s) failed to process. Their classifications are saved and they will be retried when you reopen this folder.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560)
            } else {
                Text("All \(model.totalCount) images are classified and processed.")
                    .foregroundStyle(.secondary)
            }

            Button("Reveal Assets Folder") {
                model.revealOutputFolder()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            return false
        }

        provider.loadItem(
            forTypeIdentifier: UTType.fileURL.identifier,
            options: nil
        ) { item, _ in
            let url: URL?

            if let droppedURL = item as? URL {
                url = droppedURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }

            guard let url else { return }

            DispatchQueue.main.async {
                var isDirectory: ObjCBool = false

                guard FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue
                else {
                    model.errorMessage = "Please drop the main assets folder, not an individual file."
                    return
                }

                model.openFolder(url)
            }
        }

        return true
    }
}
