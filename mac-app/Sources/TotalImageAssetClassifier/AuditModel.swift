import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AuditModel: ObservableObject {
    @Published private(set) var sourceSelection: URL?
    @Published private(set) var destinationSelection: URL?
    @Published private(set) var excelSelection: URL?

    @Published private(set) var scanResult: AuditScanResult?
    @Published private(set) var document =
        AuditDocument(destinationRootName: "")
    @Published private(set) var isScanning = false
    @Published private(set) var isApplying = false
    @Published private(set) var scanProgress = 0.0
    @Published private(set) var scanStage = ""
    @Published private(set) var currentIndex = 0
    @Published var filter: AuditQueueFilter = .unresolved {
        didSet {
            currentIndex = 0
            resetPreview()
        }
    }
    @Published var previewMode:
        AuditPreviewMode = .sideBySide
    @Published private(set) var differenceURL: URL?
    @Published private(set) var isGeneratingDifference = false
    @Published var renameDraft = ""
    @Published private(set) var renameValidation:
        RenameValidation?
    @Published var message: String?
    @Published var errorMessage: String?

    let magickPath: String? =
        ImageProcessor.locateMagick()

    var issues: [AuditIssue] {
        scanResult?.issues ?? []
    }

    var filteredIssues: [AuditIssue] {
        issues.filter { issue in
            switch filter {
            case .all:
                return true
            case .destinationOnly:
                return issue.kind == .destinationOnly
            case .duplicates:
                return issue.kind == .pixelDuplicate
            case .naming:
                return issue.kind == .namingWarning
            case .missing:
                return issue.kind == .missingOutput
            case .unresolved:
                return decision(for: issue).action
                    == .unreviewed
            }
        }
    }

    var currentIssue: AuditIssue? {
        let list = filteredIssues
        guard list.indices.contains(currentIndex) else {
            return nil
        }
        return list[currentIndex]
    }

    var summary: AuditSummary? {
        scanResult?.summary
    }

    var reviewedCount: Int {
        issues.reduce(0) { count, issue in
            count
                + (
                    decision(for: issue).action
                        == .unreviewed ? 0 : 1
                )
        }
    }

    var queuedChangeCount: Int {
        document.decisions.values.reduce(0) {
            count, decision in
            switch decision.action {
            case .delete, .rename:
                return count + 1
            default:
                return count
            }
        }
    }

    var canApplyChanges: Bool {
        queuedChangeCount > 0
            && !isApplying
            && !isScanning
    }

    var canRollback: Bool {
        document.lastApply != nil
            && !isApplying
            && !isScanning
    }

    var canStartAudit: Bool {
        sourceSelection != nil
            && destinationSelection != nil
            && !isScanning
            && !isApplying
    }

    func chooseSourceFolder() {
        guard let url = chooseDirectory(
            title: "Choose current ALL_PRODUCT_ASSETS",
            prompt: "Use as Source"
        ) else {
            return
        }

        setSourceFolder(url)
    }

    func chooseDestinationFolder() {
        guard let url = chooseDirectory(
            title: "Choose finalized assets folder",
            prompt: "Use as Destination"
        ) else {
            return
        }

        setDestinationFolder(url)
    }

    func chooseExcelFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose client Excel workbook"
        panel.prompt = "Use Excel"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if let xlsx = UTType(
            filenameExtension: "xlsx"
        ) {
            panel.allowedContentTypes = [xlsx]
        }

        if panel.runModal() == .OK,
           let url = panel.url
        {
            setExcelFile(url)
        }
    }

    func setSourceFolder(_ url: URL) {
        guard !isScanning, !isApplying else {
            return
        }
        sourceSelection = url.standardizedFileURL
    }

    func setDestinationFolder(_ url: URL) {
        guard !isScanning, !isApplying else {
            return
        }
        destinationSelection =
            url.standardizedFileURL
    }

    func setExcelFile(_ url: URL?) {
        guard !isScanning, !isApplying else {
            return
        }
        excelSelection = url?.standardizedFileURL
    }

    func startAudit() {
        guard let sourceSelection,
              let destinationSelection
        else {
            errorMessage =
                "Choose both the current source and finalized destination folders."
            return
        }

        guard sourceSelection.path
            != destinationSelection.path
        else {
            errorMessage =
                "Source and destination must be different folders."
            return
        }

        guard magickPath != nil else {
            errorMessage =
                "ImageMagick was not found. Install it with: brew install imagemagick"
            return
        }

        isScanning = true
        scanProgress = 0
        scanStage = "Preparing audit…"
        message = nil
        errorMessage = nil
        differenceURL = nil

        let excel = excelSelection
        let magick = magickPath

        let progressSink:
            AuditProgressHandler = {
                [weak self] fraction, stage in
                Task { @MainActor in
                    self?.scanProgress = fraction
                    self?.scanStage = stage
                }
            }

        Task {
            do {
                let result =
                    try await Task.detached(
                        priority: .userInitiated
                    ) {
                        try AssetAuditEngine.scan(
                            sourceURL:
                                sourceSelection,
                            destinationURL:
                                destinationSelection,
                            excelURL: excel,
                            magickPath: magick,
                            progressHandler:
                                progressSink
                        )
                    }.value

                var loaded =
                    try AuditStore.load(
                        rootURL:
                            destinationSelection,
                        sourceRootName:
                            sourceSelection
                                .lastPathComponent,
                        excelFileName:
                            excel?.lastPathComponent
                    )

                let currentIDs = Set(
                    result.issues.map(\.id)
                )
                loaded.decisions =
                    loaded.decisions.filter {
                        currentIDs.contains($0.key)
                    }

                scanResult = result
                document = loaded
                isScanning = false
                scanProgress = 1
                scanStage = "Audit ready"
                currentIndex = 0
                filter = .unresolved

                try AuditStore.save(
                    document,
                    rootURL:
                        destinationSelection
                )

                message =
                    "Audit ready: \(result.summary.destinationOnlyCount) destination-only, \(result.summary.duplicateIssueCount) duplicate group(s), \(result.summary.namingWarningCount) naming warning(s), \(result.summary.missingOutputCount) missing output(s)."

                prepareCurrentIssue()
            } catch {
                isScanning = false
                errorMessage =
                    error.localizedDescription
            }
        }
    }

    func decision(
        for issue: AuditIssue
    ) -> AuditDecision {
        document.decisions[issue.id]
            ?? AuditDecision(
                issueID: issue.id,
                action: .unreviewed,
                proposedFileName: nil,
                note: nil,
                decidedAt:
                    Date(timeIntervalSince1970: 0)
            )
    }

    func setDecision(
        _ action: AuditDecisionKind,
        note: String? = nil
    ) {
        guard let issue = currentIssue,
              let destination = destinationSelection
        else {
            return
        }

        if action == .delete,
           issue.primarySourceBacked
        {
            errorMessage =
                "This output is still source-backed. Audit mode will not delete it; use Keep Both, Intentional Duplicate, or Source Issue instead."
            return
        }

        var proposed: String?
        if action == .rename {
            validateRenameDraft()
            guard renameValidation?.isValid == true
            else {
                errorMessage =
                    renameValidation?.message
                    ?? "Enter a valid replacement filename."
                return
            }
            proposed = renameDraft
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        }

        document.decisions[issue.id] =
            AuditDecision(
                issueID: issue.id,
                action: action,
                proposedFileName: proposed,
                note: note,
                decidedAt: Date()
            )

        do {
            try AuditStore.save(
                document,
                rootURL: destination
            )
        } catch {
            errorMessage =
                "Could not save audit decision: \(error.localizedDescription)"
            return
        }

        advanceAfterDecision()
    }

    func clearDecision() {
        guard let issue = currentIssue,
              let destination = destinationSelection
        else {
            return
        }

        document.decisions.removeValue(
            forKey: issue.id
        )

        do {
            try AuditStore.save(
                document,
                rootURL: destination
            )
        } catch {
            errorMessage =
                "Could not clear audit decision: \(error.localizedDescription)"
        }

        prepareCurrentIssue()
    }

    func nextIssue() {
        let list = filteredIssues
        guard !list.isEmpty else { return }
        currentIndex = min(
            currentIndex + 1,
            list.count - 1
        )
        prepareCurrentIssue()
    }

    func previousIssue() {
        currentIndex = max(
            currentIndex - 1,
            0
        )
        prepareCurrentIssue()
    }

    func jumpToIssue(_ issue: AuditIssue) {
        guard let index = filteredIssues
            .firstIndex(of: issue)
        else {
            return
        }

        currentIndex = index
        prepareCurrentIssue()
    }

    func validateRenameDraft() {
        guard let issue = currentIssue,
              let scanResult
        else {
            renameValidation = nil
            return
        }

        renameValidation =
            AssetAuditEngine.validateRename(
                proposedFileName:
                    renameDraft,
                issue: issue,
                scan: scanResult
            )
    }

    func useSuggestedRename() {
        guard let suggestion =
            renameValidation?.suggestedFileName
                ?? currentIssue?
                    .suggestedFileName
        else {
            return
        }

        renameDraft = suggestion
        validateRenameDraft()
    }

    func primaryURL(
        for issue: AuditIssue
    ) -> URL? {
        guard let scanResult else {
            return nil
        }

        let destination =
            scanResult.destinationRootURL
            .appendingPathComponent(
                issue.primaryRelativePath
            )

        if FileManager.default.fileExists(
            atPath: destination.path
        ) {
            return destination
        }

        if let sourcePath =
            issue.sourceRelativePath
        {
            let source =
                scanResult.sourceRootURL
                .appendingPathComponent(
                    sourcePath
                )
            if FileManager.default.fileExists(
                atPath: source.path
            ) {
                return source
            }
        }

        return nil
    }

    func relatedURL(
        for issue: AuditIssue
    ) -> URL? {
        guard let path =
            issue.relatedRelativePaths.first,
              let scanResult
        else {
            return nil
        }

        let url =
            scanResult.destinationRootURL
            .appendingPathComponent(path)

        return FileManager.default.fileExists(
            atPath: url.path
        ) ? url : nil
    }

    func sourceURL(
        for issue: AuditIssue
    ) -> URL? {
        guard let sourcePath =
            issue.sourceRelativePath,
              let scanResult
        else {
            return nil
        }

        let url = scanResult.sourceRootURL
            .appendingPathComponent(sourcePath)

        return FileManager.default.fileExists(
            atPath: url.path
        ) ? url : nil
    }

    func generateDifferenceIfNeeded() {
        guard previewMode == .difference,
              let issue = currentIssue,
              let left = primaryURL(for: issue),
              let right = relatedURL(for: issue),
              let magickPath
        else {
            differenceURL = nil
            return
        }

        isGeneratingDifference = true
        differenceURL = nil

        Task {
            do {
                let url =
                    try await Task.detached(
                        priority: .utility
                    ) {
                        try AssetAuditEngine
                            .makeDifferenceImage(
                                left: left,
                                right: right,
                                magickPath:
                                    magickPath
                            )
                    }.value

                if currentIssue?.id == issue.id,
                   previewMode == .difference
                {
                    differenceURL = url
                }
            } catch {
                errorMessage =
                    "Could not generate difference preview: \(error.localizedDescription)"
            }

            isGeneratingDifference = false
        }
    }

    func applyQueuedChanges() {
        guard let scanResult,
              let destinationSelection
        else {
            return
        }

        guard canApplyChanges else {
            return
        }

        isApplying = true
        errorMessage = nil
        message =
            "Backing up and applying reviewed audit changes…"

        let issues = scanResult.issues
        var documentCopy = document

        Task {
            do {
                let result =
                    try await Task.detached(
                        priority: .userInitiated
                    ) {
                        let manifest =
                            try AssetAuditEngine
                            .applyChanges(
                                scan: scanResult,
                                issues: issues,
                                document:
                                    &documentCopy
                            )
                        return (
                            manifest,
                            documentCopy
                        )
                    }.value

                document = result.1
                try AuditStore.save(
                    document,
                    rootURL:
                        destinationSelection
                )
                let reports =
                    try AuditStore.writeReports(
                        document: document,
                        issues: issues,
                        manifest: result.0,
                        rootURL:
                            destinationSelection
                    )

                isApplying = false
                message =
                    "Applied \(result.0.operations.count) change(s). Backup: \(result.0.backupRootPath). Reports: \(reports.csvURL.lastPathComponent), \(reports.jsonURL.lastPathComponent)."

                startAudit()
            } catch {
                isApplying = false
                errorMessage =
                    error.localizedDescription
            }
        }
    }

    func rollbackLastApply() {
        guard let manifest =
            document.lastApply,
              let destinationSelection
        else {
            return
        }

        isApplying = true
        errorMessage = nil
        message = "Verifying and restoring the last audit backup…"

        Task {
            do {
                try await Task.detached(
                    priority: .userInitiated
                ) {
                    try AssetAuditEngine.rollback(
                        manifest: manifest,
                        destinationRootURL:
                            destinationSelection
                    )
                }.value

                document.lastApply = nil
                try AuditStore.save(
                    document,
                    rootURL:
                        destinationSelection
                )

                isApplying = false
                message =
                    "Last audit apply was rolled back successfully."
                startAudit()
            } catch {
                isApplying = false
                errorMessage =
                    error.localizedDescription
            }
        }
    }

    func revealDestination() {
        guard let destinationSelection else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(
            [destinationSelection]
        )
    }

    func resetSelections() {
        guard !isScanning, !isApplying else {
            return
        }

        sourceSelection = nil
        destinationSelection = nil
        excelSelection = nil
        scanResult = nil
        document =
            AuditDocument(
                destinationRootName: ""
            )
        currentIndex = 0
        message = nil
        errorMessage = nil
        renameDraft = ""
        renameValidation = nil
        resetPreview()
    }

    private func chooseDirectory(
        title: String,
        prompt: String
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK
        else {
            return nil
        }

        return panel.url
    }

    private func advanceAfterDecision() {
        if filter == .unresolved {
            currentIndex = min(
                currentIndex,
                max(filteredIssues.count - 1, 0)
            )
        } else if currentIndex
            < filteredIssues.count - 1
        {
            currentIndex += 1
        }

        prepareCurrentIssue()
    }

    private func prepareCurrentIssue() {
        resetPreview()

        guard let issue = currentIssue else {
            renameDraft = ""
            renameValidation = nil
            return
        }

        let existing = decision(for: issue)

        renameDraft =
            existing.proposedFileName
            ?? issue.suggestedFileName
            ?? URL(
                fileURLWithPath:
                    issue.primaryRelativePath
            ).lastPathComponent

        validateRenameDraft()
    }

    private func resetPreview() {
        previewMode = .sideBySide
        differenceURL = nil
        isGeneratingDifference = false
    }
}
