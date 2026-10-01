import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var destinationURL: URL?
    @Published private(set) var comparisonSourceSelection: URL?
    @Published private(set) var comparisonDestinationSelection: URL?
    @Published private(set) var comparisonSummary: ComparisonSummary?
    @Published private(set) var scanMode: AssetScanMode?
    @Published private(set) var productFolderCount = 0
    @Published private(set) var items: [AssetItem] = []
    @Published private(set) var progress = ProgressDocument(rootFolderName: "")
    @Published private(set) var isLoading = false
    @Published private(set) var activeProcessingCount = 0
    @Published private(set) var queuedProcessingCount = 0
    @Published var message: String?
    @Published var errorMessage: String?

    private var history: [String] = []
    private var processingQueue: [ProcessingJob] = []
    private var queuedPaths: Set<String> = []
    private var activePaths: Set<String> = []
    private var parentLibraryURL: URL?
    private var progressRootURL: URL?
    private var comparisonProductFolderMap: [String: String] = [:]
    private var comparisonSourceScanMode: AssetScanMode?

    private let maxConcurrentProcessors = 2

    let magickPath: String? = ImageProcessor.locateMagick()

    var currentItem: AssetItem? {
        items.first { progress.records[$0.relativePath] == nil }
    }

    var totalCount: Int {
        items.count
    }

    var classifiedCount: Int {
        items.reduce(0) { count, item in
            count + (progress.records[item.relativePath] == nil ? 0 : 1)
        }
    }

    var completedCount: Int {
        items.reduce(0) { count, item in
            count + (progress.records[item.relativePath]?.status == .completed ? 1 : 0)
        }
    }

    var failedCount: Int {
        items.reduce(0) { count, item in
            count + (progress.records[item.relativePath]?.status == .failed ? 1 : 0)
        }
    }

    var isClassificationComplete: Bool {
        !items.isEmpty && classifiedCount == totalCount
    }

    var canUndo: Bool {
        !history.isEmpty
    }

    var isComparisonMode: Bool {
        scanMode == .comparison
    }

    var manualRemainingCount: Int {
        max(totalCount - classifiedCount, 0)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose ALL_PRODUCT_ASSETS or a single SKU folder"
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url)
        }
    }

    func chooseComparisonSourceFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose source ALL_PRODUCT_ASSETS"
        panel.prompt = "Use as Source"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            setComparisonSourceFolder(url)
        }
    }

    func chooseComparisonDestinationFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose finalized destination assets folder"
        panel.prompt = "Use as Destination"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            setComparisonDestinationFolder(url)
        }
    }

    func setComparisonSourceFolder(_ url: URL) {
        comparisonSourceSelection = url.standardizedFileURL
        tryOpenComparisonIfReady()
    }

    func setComparisonDestinationFolder(_ url: URL) {
        comparisonDestinationSelection = url.standardizedFileURL
        tryOpenComparisonIfReady()
    }

    private func tryOpenComparisonIfReady() {
        guard let source = comparisonSourceSelection,
              let destination = comparisonDestinationSelection
        else {
            return
        }

        guard source.path != destination.path else {
            errorMessage =
                "Source and destination must be two different folders."
            return
        }

        openComparison(
            sourceURL: source,
            destinationURL: destination
        )
    }

    func openFolder(_ url: URL) {
        guard magickPath != nil else {
            errorMessage = "ImageMagick was not found. Install it with: brew install imagemagick"
            return
        }

        isLoading = true
        errorMessage = nil
        message = nil

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let scanned = try AssetScanner.scan(rootURL: url)
                    let localProgress = try ProgressStore.load(rootURL: url)

                    let parentURL: URL?
                    let parentProgress: ProgressDocument?

                    if scanned.mode == .singleSKU {
                        let candidate = url.deletingLastPathComponent()
                        parentURL = candidate
                        parentProgress = ProgressStore.exists(rootURL: candidate)
                            ? try ProgressStore.load(rootURL: candidate)
                            : nil
                    } else {
                        parentURL = nil
                        parentProgress = nil
                    }

                    return (scanned, localProgress, parentURL, parentProgress)
                }.value

                applyLoadedFolder(
                    url: url,
                    scanResult: result.0,
                    storedProgress: result.1,
                    parentURL: result.2,
                    parentProgress: result.3
                )
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func openComparison(
        sourceURL: URL,
        destinationURL: URL
    ) {
        guard magickPath != nil else {
            errorMessage =
                "ImageMagick was not found. Install it with: brew install imagemagick"
            return
        }

        let source = sourceURL.standardizedFileURL
        let destination = destinationURL.standardizedFileURL

        guard source.path != destination.path else {
            errorMessage =
                "Source and destination must be two different folders."
            return
        }

        isLoading = true
        errorMessage = nil
        message = nil

        Task {
            do {
                let result = try await Task.detached(
                    priority: .userInitiated
                ) {
                    let scanned = try AssetScanner.scan(
                        rootURL: source
                    )
                    let destinationSnapshot =
                        try DestinationScanner.scan(
                            rootURL: destination
                        )
                    let storedProgress = try ProgressStore.load(
                        rootURL: destination
                    )
                    let plan = ComparisonPlanner.makePlan(
                        items: scanned.items,
                        sourceScanMode: scanned.mode,
                        sourceRootFolderName:
                            source.lastPathComponent,
                        destinationRootFolderName:
                            destination.lastPathComponent,
                        destination: destinationSnapshot,
                        storedProgress: storedProgress
                    )

                    return (scanned, plan)
                }.value

                applyLoadedComparison(
                    sourceURL: source,
                    destinationURL: destination,
                    scanResult: result.0,
                    plan: result.1
                )
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func classify(_ classification: AssetClassification) {
        guard let item = currentItem,
              let rootURL
        else {
            return
        }

        let revision = UUID().uuidString

        let destinationProductFolderName: String? = {
            guard scanMode == .comparison,
                  let comparisonSourceScanMode,
                  let rootURL
            else {
                return nil
            }

            let sourceProduct =
                ComparisonPlanner.sourceProductFolderName(
                    for: item,
                    sourceScanMode: comparisonSourceScanMode,
                    sourceRootFolderName:
                        rootURL.lastPathComponent
                )

            return comparisonProductFolderMap[sourceProduct]
                ?? sourceProduct
        }()

        let record = AssetProgressRecord(
            relativePath: item.relativePath,
            classification: classification,
            status: .pending,
            revision: revision,
            outputRelativePath: nil,
            error: nil,
            fileSize: item.fileSize,
            modificationTime: item.modificationTime,
            updatedAt: Date(),
            destinationProductFolderName:
                destinationProductFolderName,
            outputStemOverride: nil
        )

        setRecord(record, for: item.relativePath)
        history.append(item.relativePath)
        saveProgress()

        enqueue(
            item: item,
            classification: classification,
            revision: revision,
            rootURL: rootURL
        )
    }

    func undoLastClassification() {
        guard let path = history.popLast(),
              let rootURL,
              let previous = progress.records[path]
        else {
            return
        }

        if let output = previous.outputRelativePath {
            let outputRoot = progressRootURL ?? rootURL
            let url = outputRoot.appendingPathComponent(output)
            try? FileManager.default.removeItem(at: url)
        }

        var document = progress
        document.records.removeValue(forKey: path)
        progress = document

        queuedPaths.remove(path)
        processingQueue.removeAll { $0.relativePath == path }

        saveProgress()
        refreshQueueCounts()
    }

    func revealOutputFolder() {
        guard let url = destinationURL ?? rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func resetGeneratedOutputsAndProgress() {
        guard activeProcessingCount == 0,
              let rootURL
        else {
            errorMessage = "Wait for the current background processing to finish before resetting."
            return
        }

        do {
            if scanMode == .comparison,
               let destinationURL
            {
                try ProgressStore.reset(rootURL: destinationURL)
                history.removeAll()
                processingQueue.removeAll()
                queuedPaths.removeAll()
                activePaths.removeAll()
                refreshQueueCounts()

                message =
                    "Saved comparison state was cleared. Finalized destination WebPs were preserved."

                openComparison(
                    sourceURL: rootURL,
                    destinationURL: destinationURL
                )
                return
            }

            try removeGeneratedWebPFolders(rootURL: rootURL)
            try ProgressStore.reset(rootURL: rootURL)

            history.removeAll()
            processingQueue.removeAll()
            queuedPaths.removeAll()
            activePaths.removeAll()
            progress = ProgressDocument(
                rootFolderName: rootURL.lastPathComponent
            )
            refreshQueueCounts()

            message = "Generated WebP folders and saved classification progress were cleared. Original images were not touched."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyLoadedFolder(
        url: URL,
        scanResult: AssetScanResult,
        storedProgress: ProgressDocument,
        parentURL: URL?,
        parentProgress: ProgressDocument?
    ) {
        rootURL = url
        destinationURL = nil
        scanMode = scanResult.mode
        productFolderCount = scanResult.productFolderCount
        items = scanResult.items
        parentLibraryURL = parentURL
        progressRootURL = url
        comparisonSummary = nil
        comparisonProductFolderMap.removeAll()
        comparisonSourceScanMode = nil
        comparisonSourceSelection = nil
        comparisonDestinationSelection = nil

        history.removeAll()
        processingQueue.removeAll()
        queuedPaths.removeAll()
        activePaths.removeAll()

        var reconciled = storedProgress
        reconciled.rootFolderName = url.lastPathComponent

        if scanResult.mode == .singleSKU, let parentProgress {
            importParentProgress(
                parentProgress,
                skuFolderName: url.lastPathComponent,
                into: &reconciled
            )
        }

        let itemByPath = Dictionary(
            uniqueKeysWithValues: scanResult.items.map { ($0.relativePath, $0) }
        )

        for (path, var record) in reconciled.records {
            guard let item = itemByPath[path] else {
                continue
            }

            let sourceChanged =
                record.fileSize != item.fileSize ||
                abs(record.modificationTime - item.modificationTime) > 0.5

            let outputMissing: Bool = {
                guard let output = record.outputRelativePath else { return true }
                return !FileManager.default.fileExists(
                    atPath: url.appendingPathComponent(output).path
                )
            }()

            if sourceChanged || outputMissing || record.status != .completed {
                record.fileSize = item.fileSize
                record.modificationTime = item.modificationTime
                record.status = .pending
                record.outputRelativePath = nil
                record.error = nil
                record.revision = UUID().uuidString
                record.updatedAt = Date()
                reconciled.records[path] = record
            }
        }

        if scanResult.mode == .singleSKU {
            inferExistingOutputClassifications(
                rootURL: url,
                items: scanResult.items,
                progress: &reconciled
            )
        }

        progress = reconciled
        isLoading = false
        saveProgress()

        for item in scanResult.items {
            guard let record = progress.records[item.relativePath],
                  record.status != .completed
            else {
                continue
            }

            enqueue(
                item: item,
                classification: record.classification,
                revision: record.revision,
                rootURL: url
            )
        }

        let inferredCount = scanResult.items.filter {
            progress.records[$0.relativePath] != nil
        }.count
        let remainingCount = scanResult.items.count - inferredCount

        switch scanResult.mode {
        case .library:
            message = storedProgress.records.isEmpty
                ? "Loaded \(scanResult.productFolderCount) SKU folders. Ready to classify the asset library."
                : "Asset-library progress loaded. Resuming from the first unclassified image."

        case .singleSKU:
            if remainingCount == 0 {
                message = "Single-SKU mode: existing classifications found. New or replaced root images are being refreshed automatically."
            } else {
                message = "Single-SKU mode: \(remainingCount) root image(s) need classification. Existing generated model/product folders are preserved."
            }
        }
    }

    private func applyLoadedComparison(
        sourceURL: URL,
        destinationURL: URL,
        scanResult: AssetScanResult,
        plan: ComparisonPlan
    ) {
        rootURL = sourceURL
        self.destinationURL = destinationURL
        comparisonSourceSelection = sourceURL
        comparisonDestinationSelection = destinationURL
        scanMode = .comparison
        productFolderCount = scanResult.productFolderCount
        items = scanResult.items
        progress = plan.progress
        progressRootURL = destinationURL
        parentLibraryURL = nil
        comparisonSummary = plan.summary
        comparisonProductFolderMap = plan.productFolderMap
        comparisonSourceScanMode = scanResult.mode

        history.removeAll()
        processingQueue.removeAll()
        queuedPaths.removeAll()
        activePaths.removeAll()

        isLoading = false
        saveProgress()

        for item in scanResult.items {
            guard let record = progress.records[item.relativePath],
                  record.status != .completed
            else {
                continue
            }

            enqueue(
                item: item,
                classification: record.classification,
                revision: record.revision,
                rootURL: sourceURL
            )
        }

        let summary = plan.summary
        message =
            "Smart comparison loaded: \(summary.alreadyCurrentCount) already current, " +
            "\(summary.automaticRefreshCount) refreshing automatically, " +
            "\(summary.manualClassificationCount) need manual classification. " +
            "\(summary.destinationOnlyOutputCount) destination-only output(s) are preserved."
    }

    private func importParentProgress(
        _ parent: ProgressDocument,
        skuFolderName: String,
        into local: inout ProgressDocument
    ) {
        let prefix = skuFolderName + "/"

        for (parentPath, parentRecord) in parent.records {
            guard parentPath.hasPrefix(prefix) else { continue }

            let localPath = String(parentPath.dropFirst(prefix.count))
            guard !localPath.contains("/") else { continue }
            guard local.records[localPath] == nil else { continue }

            var imported = parentRecord
            imported.relativePath = localPath

            if let output = imported.outputRelativePath,
               output.hasPrefix(prefix)
            {
                imported.outputRelativePath = String(output.dropFirst(prefix.count))
            }

            local.records[localPath] = imported
        }
    }

    private func inferExistingOutputClassifications(
        rootURL: URL,
        items: [AssetItem],
        progress: inout ProgressDocument
    ) {
        let fileManager = FileManager.default

        for item in items where progress.records[item.relativePath] == nil {
            var matches: [(AssetClassification, String)] = []

            for classification in AssetClassification.allCases {
                let relativeOutput = [
                    "webp",
                    classification.outputFolderName,
                    item.outputStem + ".webp"
                ].joined(separator: "/")

                if fileManager.fileExists(
                    atPath: rootURL.appendingPathComponent(relativeOutput).path
                ) {
                    matches.append((classification, relativeOutput))
                }
            }

            guard matches.count == 1, let match = matches.first else {
                continue
            }

            progress.records[item.relativePath] = AssetProgressRecord(
                relativePath: item.relativePath,
                classification: match.0,
                status: .pending,
                revision: UUID().uuidString,
                outputRelativePath: nil,
                error: nil,
                fileSize: item.fileSize,
                modificationTime: item.modificationTime,
                updatedAt: Date()
            )
        }
    }

    private func enqueue(
        item: AssetItem,
        classification: AssetClassification,
        revision: String,
        rootURL: URL
    ) {
        guard !queuedPaths.contains(item.relativePath),
              !activePaths.contains(item.relativePath)
        else {
            return
        }

        let record = progress.records[item.relativePath]
        let outputRootURL = destinationURL ?? rootURL
        let outputProductFolderURL: URL
        let outputStem = record?.outputStemOverride
            ?? item.outputStem

        if scanMode == .comparison {
            let sourceProduct =
                ComparisonPlanner.sourceProductFolderName(
                    for: item,
                    sourceScanMode:
                        comparisonSourceScanMode ?? .library,
                    sourceRootFolderName:
                        rootURL.lastPathComponent
                )
            let destinationProduct =
                record?.destinationProductFolderName
                ?? comparisonProductFolderMap[sourceProduct]
                ?? sourceProduct

            outputProductFolderURL = outputRootURL
                .appendingPathComponent(
                    destinationProduct,
                    isDirectory: true
                )
        } else {
            outputProductFolderURL =
                item.sourceURL.deletingLastPathComponent()
        }

        processingQueue.append(
            ProcessingJob(
                sourceURL: item.sourceURL,
                outputRootURL: outputRootURL,
                outputProductFolderURL:
                    outputProductFolderURL,
                relativePath: item.relativePath,
                outputStem: outputStem,
                classification: classification,
                revision: revision
            )
        )

        queuedPaths.insert(item.relativePath)
        refreshQueueCounts()
        pumpQueue()
    }

    private func pumpQueue() {
        guard let magickPath else { return }

        while activePaths.count < maxConcurrentProcessors,
              !processingQueue.isEmpty
        {
            let job = processingQueue.removeFirst()
            queuedPaths.remove(job.relativePath)

            guard let record = progress.records[job.relativePath],
                  record.revision == job.revision,
                  record.classification == job.classification
            else {
                continue
            }

            activePaths.insert(job.relativePath)
            updateStatus(
                path: job.relativePath,
                revision: job.revision,
                status: .processing,
                outputRelativePath: nil,
                error: nil
            )
            refreshQueueCounts()

            Task.detached(priority: .utility) {
                let result: Result<ProcessingResult, Error>

                do {
                    result = .success(
                        try ImageProcessor.process(
                            job: job,
                            magickPath: magickPath
                        )
                    )
                } catch {
                    result = .failure(error)
                }

                await MainActor.run {
                    self.finish(job: job, result: result)
                }
            }
        }

        refreshQueueCounts()
    }

    private func finish(
        job: ProcessingJob,
        result: Result<ProcessingResult, Error>
    ) {
        activePaths.remove(job.relativePath)

        guard let currentRecord = progress.records[job.relativePath],
              currentRecord.revision == job.revision,
              currentRecord.classification == job.classification
        else {
            if case .success(let staleResult) = result {
                try? FileManager.default.removeItem(at: staleResult.outputURL)
            }

            refreshQueueCounts()
            pumpQueue()
            return
        }

        switch result {
        case .success(let processed):
            updateStatus(
                path: job.relativePath,
                revision: job.revision,
                status: .completed,
                outputRelativePath: processed.outputRelativePath,
                error: nil
            )

        case .failure(let error):
            updateStatus(
                path: job.relativePath,
                revision: job.revision,
                status: .failed,
                outputRelativePath: nil,
                error: error.localizedDescription
            )
        }

        saveProgress()
        refreshQueueCounts()
        pumpQueue()
    }

    private func setRecord(
        _ record: AssetProgressRecord,
        for path: String
    ) {
        var document = progress
        document.records[path] = record
        progress = document
    }

    private func updateStatus(
        path: String,
        revision: String,
        status: ProcessingStatus,
        outputRelativePath: String?,
        error: String?
    ) {
        guard var record = progress.records[path],
              record.revision == revision
        else {
            return
        }

        record.status = status
        record.outputRelativePath = outputRelativePath
        record.error = error
        record.updatedAt = Date()
        setRecord(record, for: path)
    }

    private func saveProgress() {
        guard let rootURL,
              let saveRootURL = progressRootURL ?? self.rootURL
        else {
            return
        }

        do {
            try ProgressStore.save(
                progress,
                rootURL: saveRootURL
            )

            if scanMode == .singleSKU, let parentLibraryURL {
                try mirrorSingleSKUProgressToParent(
                    rootURL: rootURL,
                    parentURL: parentLibraryURL
                )
            }
        } catch {
            errorMessage = "Could not save progress: \(error.localizedDescription)"
        }
    }

    private func mirrorSingleSKUProgressToParent(
        rootURL: URL,
        parentURL: URL
    ) throws {
        guard ProgressStore.exists(rootURL: parentURL) else { return }

        var parent = try ProgressStore.load(rootURL: parentURL)
        let sku = rootURL.lastPathComponent
        let prefix = sku + "/"

        // Mirror root-level SKU records exactly, rather than only upserting them.
        // This keeps undo/removal behavior consistent between single-SKU mode
        // and the parent ALL_PRODUCT_ASSETS progress document.
        parent.records = parent.records.filter { path, _ in
            guard path.hasPrefix(prefix) else { return true }
            let suffix = String(path.dropFirst(prefix.count))
            return suffix.contains("/")
        }

        for (localPath, localRecord) in progress.records {
            guard !localPath.contains("/") else { continue }

            let parentPath = prefix + localPath
            var mirrored = localRecord
            mirrored.relativePath = parentPath

            if let output = mirrored.outputRelativePath {
                mirrored.outputRelativePath = prefix + output
            }

            parent.records[parentPath] = mirrored
        }

        try ProgressStore.save(parent, rootURL: parentURL)
    }

    private func refreshQueueCounts() {
        activeProcessingCount = activePaths.count
        queuedProcessingCount = processingQueue.count
    }

    private func removeGeneratedWebPFolders(rootURL: URL) throws {
        let fileManager = FileManager.default

        if scanMode == .comparison {
            return
        }

        if scanMode == .singleSKU {
            let webpFolder = rootURL.appendingPathComponent("webp", isDirectory: true)
            if fileManager.fileExists(atPath: webpFolder.path) {
                try fileManager.removeItem(at: webpFolder)
            }
            return
        }

        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            let webpFolder = child.appendingPathComponent("webp", isDirectory: true)

            if fileManager.fileExists(atPath: webpFolder.path) {
                try fileManager.removeItem(at: webpFolder)
            }
        }
    }
}
