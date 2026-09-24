import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var rootURL: URL?
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
        progress.records.values.filter { $0.status == .completed }.count
    }

    var failedCount: Int {
        progress.records.values.filter { $0.status == .failed }.count
    }

    var isClassificationComplete: Bool {
        !items.isEmpty && classifiedCount == totalCount
    }

    var canUndo: Bool {
        !history.isEmpty
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the main assets folder"
        panel.prompt = "Use Assets Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url)
        }
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
                    let stored = try ProgressStore.load(rootURL: url)
                    return (scanned, stored)
                }.value

                applyLoadedFolder(
                    url: url,
                    scannedItems: result.0,
                    storedProgress: result.1
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

        let record = AssetProgressRecord(
            relativePath: item.relativePath,
            classification: classification,
            status: .pending,
            revision: revision,
            outputRelativePath: nil,
            error: nil,
            fileSize: item.fileSize,
            modificationTime: item.modificationTime,
            updatedAt: Date()
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
            let url = rootURL.appendingPathComponent(output)
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
        guard let rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([rootURL])
    }

    func resetGeneratedOutputsAndProgress() {
        guard activeProcessingCount == 0,
              let rootURL
        else {
            errorMessage = "Wait for the current background processing to finish before resetting."
            return
        }

        do {
            try removeGeneratedWebPFolders(rootURL: rootURL)
            try ProgressStore.reset(rootURL: rootURL)

            history.removeAll()
            processingQueue.removeAll()
            queuedPaths.removeAll()
            activePaths.removeAll()
            progress = ProgressDocument(rootFolderName: rootURL.lastPathComponent)
            refreshQueueCounts()

            message = "Generated WebP folders and saved classification progress were cleared. Original images were not touched."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyLoadedFolder(
        url: URL,
        scannedItems: [AssetItem],
        storedProgress: ProgressDocument
    ) {
        rootURL = url
        items = scannedItems
        history.removeAll()
        processingQueue.removeAll()
        queuedPaths.removeAll()
        activePaths.removeAll()

        var reconciled = storedProgress
        reconciled.rootFolderName = url.lastPathComponent

        let itemByPath = Dictionary(
            uniqueKeysWithValues: scannedItems.map { ($0.relativePath, $0) }
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

        progress = reconciled
        isLoading = false
        saveProgress()

        for item in scannedItems {
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

        message = storedProgress.records.isEmpty
            ? "Ready. Classification progress is saved after every click."
            : "Previous progress loaded. Resuming from the first unclassified image."
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

        processingQueue.append(
            ProcessingJob(
                sourceURL: item.sourceURL,
                rootURL: rootURL,
                relativePath: item.relativePath,
                outputStem: item.outputStem,
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
              !processingQueue.isEmpty {
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
        guard let rootURL else { return }

        do {
            try ProgressStore.save(progress, rootURL: rootURL)
        } catch {
            errorMessage = "Could not save progress: \(error.localizedDescription)"
        }
    }

    private func refreshQueueCounts() {
        activeProcessingCount = activePaths.count
        queuedProcessingCount = processingQueue.count
    }

    private func removeGeneratedWebPFolders(rootURL: URL) throws {
        let fileManager = FileManager.default

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
