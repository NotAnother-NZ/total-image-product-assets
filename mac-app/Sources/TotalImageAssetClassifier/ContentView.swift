import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var auditModel = AuditModel()

    @State private var workspace: WorkspaceMode = .home
    @State private var sourceDropTargeted = false
    @State private var destinationDropTargeted = false
    @State private var showResetConfirmation = false

    private enum WorkspaceMode {
        case home
        case classifier
        case audit
    }

    var body: some View {
        Group {
            switch workspace {
            case .home:
                homeView

            case .classifier:
                if model.rootURL == nil {
                    emptyState
                } else {
                    classifier
                }

            case .audit:
                AuditView(
                    model: auditModel,
                    onBack: {
                        workspace = .home
                    }
                )
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
            model.isComparisonMode
                ? "Clear saved comparison state?"
                : "Clear generated WebPs and saved progress?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                model.isComparisonMode
                    ? "Clear saved comparison state"
                    : "Clear generated outputs & progress",
                role: .destructive
            ) {
                model.resetGeneratedOutputsAndProgress()
            }
        } message: {
            Text(
                model.isComparisonMode
                    ? "This clears only the saved comparison state. Finalized destination WebPs are preserved."
                    : "This removes nested webp folders and the classifier progress file. Original source images are not touched."
            )
        }
    }

    private var homeView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)

            Text("Total Image Asset Tools")
                .font(.largeTitle.bold())

            Text(
                "Choose the workflow you need. Classification/sync remains unchanged; final-asset auditing is isolated in its own review mode."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 720)

            HStack(spacing: 20) {
                workspaceCard(
                    title: "Classify / Sync Assets",
                    subtitle:
                        "Classify source images, sync ALL_PRODUCT_ASSETS into the finalized destination, or update a single SKU.",
                    systemImage:
                        "arrow.triangle.2.circlepath"
                ) {
                    workspace = .classifier
                }

                workspaceCard(
                    title: "Audit Final Assets",
                    subtitle:
                        "Review destination-only files, pixel duplicates and naming issues visually before applying safe cleanup changes.",
                    systemImage:
                        "checklist.checked"
                ) {
                    workspace = .audit
                }
            }
            .frame(maxWidth: 920)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func workspaceCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                Spacer()

                Label(
                    "Open",
                    systemImage: "arrow.right.circle.fill"
                )
                .font(.headline)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.secondary.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
    }

    private enum ComparisonDropRole {
        case source
        case destination
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            HStack {
                Button {
                    workspace = .home
                } label: {
                    Label("Home", systemImage: "chevron.left")
                }
                Spacer()
            }

            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Total Image Asset Classifier")
                .font(.largeTitle.bold())

            Text("Smart source → destination comparison")
                .font(.title3.bold())

            Text(
                "Drop the current ALL_PRODUCT_ASSETS source and your finalized GitHub-synced assets destination. The app will reuse existing classifications, refresh known replacements automatically, and show only genuinely unresolved images for manual classification."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 760)

            HStack(spacing: 18) {
                comparisonDropZone(role: .source)

                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                comparisonDropZone(role: .destination)
            }
            .frame(maxWidth: 900)

            if model.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Comparing source and destination…")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .frame(maxWidth: 760)

            Button("Open one folder / single SKU instead…") {
                model.chooseFolder()
            }

            Text(
                "Classic mode remains available for the existing full-library or single-SKU workflow."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if model.magickPath == nil {
                Label(
                    "ImageMagick is required: brew install imagemagick",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func comparisonDropZone(
        role: ComparisonDropRole
    ) -> some View {
        let isSource = role == .source
        let selectedURL = isSource
            ? model.comparisonSourceSelection
            : model.comparisonDestinationSelection
        let isTargeted = isSource
            ? sourceDropTargeted
            : destinationDropTargeted

        return VStack(spacing: 12) {
            Image(
                systemName: isSource
                    ? "tray.and.arrow.down"
                    : "tray.and.arrow.up"
            )
            .font(.system(size: 30))
            .foregroundStyle(
                isTargeted ? Color.accentColor : Color.secondary
            )

            Text(isSource ? "Source" : "Destination")
                .font(.headline)

            Text(
                isSource
                    ? "ALL_PRODUCT_ASSETS"
                    : "final assets folder"
            )
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            if let selectedURL {
                Text(selectedURL.path)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("Drop folder here")
                    .foregroundStyle(.secondary)
            }

            Button(isSource ? "Choose Source…" : "Choose Destination…") {
                if isSource {
                    model.chooseComparisonSourceFolder()
                } else {
                    model.chooseComparisonDestinationFolder()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted
                        ? Color.accentColor
                        : Color.secondary.opacity(0.35),
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: [10, 8]
                    )
                )
        )
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: isSource
                ? $sourceDropTargeted
                : $destinationDropTargeted
        ) { providers in
            handleComparisonDrop(
                providers,
                role: role
            )
        }
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
                Button {
                    workspace = .home
                } label: {
                    Image(systemName: "house")
                }
                .help("Back to workflow selection")

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        model.isComparisonMode
                            ? "\(model.rootURL?.lastPathComponent ?? "Source") → \(model.destinationURL?.lastPathComponent ?? "Destination")"
                            : (model.rootURL?.lastPathComponent ?? "Assets")
                    )
                    .font(.headline)

                    HStack(spacing: 8) {
                        Text(model.scanMode?.label ?? "Assets")
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12))
                            .clipShape(Capsule())

                        if model.isComparisonMode {
                            Text(
                                "Source: \(model.rootURL?.path ?? "")"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                            Text("→")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Text(
                                "Destination: \(model.destinationURL?.path ?? "")"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        } else {
                            Text(model.rootURL?.path ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Spacer()

                if model.isComparisonMode {
                    Button("Source…") {
                        model.chooseComparisonSourceFolder()
                    }
                    .disabled(!model.canChangeComparisonFolders)

                    Button("Destination…") {
                        model.chooseComparisonDestinationFolder()
                    }
                    .disabled(!model.canChangeComparisonFolders)
                } else {
                    Button("Choose Folder…") {
                        model.chooseFolder()
                    }
                }

                Button("Reveal") {
                    model.revealOutputFolder()
                }

                Menu {
                    Button(
                        model.isComparisonMode
                            ? "Clear saved comparison state…"
                            : "Clear generated outputs & progress…",
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

                if model.isComparisonMode {
                    Text(
                        "\(model.manualRemainingCount) manual remaining"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

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
                Text(
                    model.isComparisonMode
                        ? "All source images are matched or classified, and finalized outputs have been written to the destination."
                        : "All \(model.totalCount) images are classified and processed."
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
            }

            Button(
                model.isComparisonMode
                    ? "Reveal Destination Folder"
                    : "Reveal Assets Folder"
            ) {
                model.revealOutputFolder()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func handleComparisonDrop(
        _ providers: [NSItemProvider],
        role: ComparisonDropRole
    ) -> Bool {
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
                url = URL(
                    dataRepresentation: data,
                    relativeTo: nil
                )
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
                    model.errorMessage =
                        "Please drop a folder, not an individual file."
                    return
                }

                switch role {
                case .source:
                    model.setComparisonSourceFolder(url)
                case .destination:
                    model.setComparisonDestinationFolder(url)
                }
            }
        }

        return true
    }

}
