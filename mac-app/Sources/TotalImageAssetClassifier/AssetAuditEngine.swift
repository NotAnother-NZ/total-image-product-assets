import CryptoKit
import Foundation

typealias AuditProgressHandler = @Sendable (
    Double,
    String
) -> Void

enum AssetAuditEngine {
    static func scan(
        sourceURL: URL,
        destinationURL: URL,
        excelURL: URL?,
        magickPath: String?,
        progressHandler: AuditProgressHandler? = nil
    ) throws -> AuditScanResult {
        progressHandler?(0.02, "Scanning current source assets…")
        let sourceScan = try AssetScanner.scan(
            rootURL: sourceURL
        )
        progressHandler?(
            0.06,
            "Source scan complete: \(sourceScan.items.count) image(s) across \(sourceScan.productFolderCount) product folder(s)."
        )
        let sourceItemsByRelativePath = Dictionary(
            uniqueKeysWithValues: sourceScan.items.map {
                ($0.relativePath, $0)
            }
        )

        progressHandler?(0.08, "Scanning finalized destination…")
        let destination = try DestinationScanner.scan(
            rootURL: destinationURL
        )
        progressHandler?(
            0.11,
            "Destination scan complete: \(destination.assets.count) finalized WebP asset(s)."
        )
        let destinationByPath = Dictionary(
            uniqueKeysWithValues: destination.assets.map {
                ($0.outputRelativePath, $0)
            }
        )

        progressHandler?(0.12, "Loading saved classifier progress…")
        let classifierProgress = try ProgressStore.load(
            rootURL: destinationURL
        )
        progressHandler?(
            0.13,
            "Loaded \(classifierProgress.records.count) saved classifier record(s)."
        )

        let excelCatalog: ExcelCatalog?
        if let excelURL {
            progressHandler?(0.14, "Opening client Excel workbook…")
            excelCatalog = try ExcelCatalog.load(
                from: excelURL
            ) { fraction, detail in
                progressHandler?(
                    0.14 + (fraction * 0.07),
                    detail
                )
            }
        } else {
            excelCatalog = nil
            progressHandler?(
                0.21,
                "No client Excel selected; continuing with source/destination validation."
            )
        }

        progressHandler?(
            0.22,
            "Reconciling current source records with finalized outputs…"
        )

        var activeOutputToSource: [String: String] = [:]
        var missingIssues: [AuditIssue] = []

        for (sourcePath, record) in classifierProgress.records {
            guard sourceItemsByRelativePath[sourcePath] != nil else {
                continue
            }

            guard let outputPath = record.outputRelativePath else {
                missingIssues.append(
                    missingIssue(
                        sourcePath: sourcePath,
                        expectedOutputPath: nil
                    )
                )
                continue
            }

            if destinationByPath[outputPath] != nil {
                activeOutputToSource[outputPath] = sourcePath
            } else {
                missingIssues.append(
                    missingIssue(
                        sourcePath: sourcePath,
                        expectedOutputPath: outputPath
                    )
                )
            }
        }

        let activePaths = Set(activeOutputToSource.keys)
        let activeAssets = destination.assets.filter {
            activePaths.contains($0.outputRelativePath)
        }

        progressHandler?(
            0.23,
            "Finding exact duplicate candidates…"
        )

        let repeatedSizeBuckets = Dictionary(
            grouping: destination.assets.filter { $0.fileSize > 0 },
            by: \.fileSize
        ).values.filter { $0.count > 1 }

        let hashWorkCount = repeatedSizeBuckets.reduce(0) {
            $0 + $1.count
        }
        var hashByPath: [String: String] = [:]
        var hashIndex = 0

        for bucket in repeatedSizeBuckets {
            for asset in bucket {
                hashIndex += 1
                if hashIndex % 25 == 0 || hashIndex == hashWorkCount {
                    let fraction = hashWorkCount == 0
                        ? 1
                        : Double(hashIndex) / Double(hashWorkCount)
                    progressHandler?(
                        0.23 + (fraction * 0.31),
                        "Hashing duplicate candidate \(hashIndex)/\(hashWorkCount): \(asset.outputURL.lastPathComponent)"

                    )
                }

                hashByPath[asset.outputRelativePath] =
                    try sha256(asset.outputURL)
            }
        }

        var relatedForOrphan: [String: String] = [:]
        var duplicateIssues: [AuditIssue] = []
        var duplicatePathSets = Set<String>()

        let exactGroups = Dictionary(
            grouping: destination.assets.compactMap {
                asset -> (String, DestinationAsset)? in
                guard let hash = hashByPath[
                    asset.outputRelativePath
                ] else {
                    return nil
                }

                let key = [
                    asset.productFolderName,
                    asset.classification.rawValue,
                    hash
                ].joined(separator: "|")

                return (key, asset)
            },
            by: { $0.0 }
        )

        for group in exactGroups.values {
            let assets = group.map(\.1)
            guard assets.count > 1 else { continue }

            processDuplicateGroup(
                assets,
                activeOutputToSource: activeOutputToSource,
                relatedForOrphan: &relatedForOrphan,
                duplicateIssues: &duplicateIssues,
                duplicatePathSets: &duplicatePathSets,
                reason: "These finalized files are byte-identical."
            )
        }

        progressHandler?(
            0.55,
            "Checking differently encoded logical duplicates…"
        )

        let logicalGroups = Dictionary(
            grouping: destination.assets,
            by: logicalGroupKey
        ).values.filter { $0.count > 1 }

        var signatureCache: [String: String] = [:]
        var logicalIndex = 0

        for group in logicalGroups {
            logicalIndex += 1
            progressHandler?(
                0.55
                    + (
                        Double(logicalIndex)
                        / Double(max(logicalGroups.count, 1))
                    ) * 0.23,
                "Pixel-checking duplicate group \(logicalIndex)/\(logicalGroups.count) (\(group.count) file(s))…"
            )

            guard let magickPath else { continue }

            var groupsBySignature: [String: [DestinationAsset]] = [:]

            for asset in group {
                let signature: String
                if let cached = signatureCache[
                    asset.outputRelativePath
                ] {
                    signature = cached
                } else {
                    signature = try pixelSignature(
                        asset.outputURL,
                        magickPath: magickPath
                    )
                    signatureCache[
                        asset.outputRelativePath
                    ] = signature
                }

                groupsBySignature[
                    signature,
                    default: []
                ].append(asset)
            }

            for assets in groupsBySignature.values
                where assets.count > 1
            {
                processDuplicateGroup(
                    assets,
                    activeOutputToSource: activeOutputToSource,
                    relatedForOrphan: &relatedForOrphan,
                    duplicateIssues: &duplicateIssues,
                    duplicatePathSets: &duplicatePathSets,
                    reason: "These finalized files decode to identical pixels."
                )
            }
        }

        progressHandler?(
            0.80,
            "Building destination-only review queue…"
        )

        let activeByProductClass = Dictionary(
            grouping: activeAssets
        ) {
            [
                $0.productFolderName,
                $0.classification.rawValue
            ].joined(separator: "|")
        }

        var destinationOnlyIssues: [AuditIssue] = []

        for asset in destination.assets
            where !activePaths.contains(asset.outputRelativePath)
        {
            let related: String?
            if let duplicate = relatedForOrphan[
                asset.outputRelativePath
            ] {
                related = duplicate
            } else {
                let key = [
                    asset.productFolderName,
                    asset.classification.rawValue
                ].joined(separator: "|")

                related = closestAsset(
                    to: asset,
                    candidates: activeByProductClass[key] ?? []
                )?.outputRelativePath
            }

            let detail: String
            if relatedForOrphan[asset.outputRelativePath] != nil {
                detail =
                    "No current source record points to this finalized output. It is pixel-identical to the compared current output."
            } else {
                detail =
                    "No current source record points to this finalized output. It is preserved until you explicitly decide to keep, rename, or delete it."
            }

            destinationOnlyIssues.append(
                AuditIssue(
                    id: "destination-only:\(asset.outputRelativePath)",
                    kind: .destinationOnly,
                    primaryRelativePath:
                        asset.outputRelativePath,
                    relatedRelativePaths:
                        related.map { [$0] } ?? [],
                    sourceRelativePath:
                        related.flatMap {
                            activeOutputToSource[$0]
                        },
                    title: asset.outputURL.lastPathComponent,
                    detail: detail,
                    primarySourceBacked: false,
                    relatedSourceBacked:
                        related == nil ? [] : [true],
                    suggestedFileName: nil
                )
            )
        }

        progressHandler?(
            0.88,
            "Checking filename quality…"
        )

        let namingIssues = destination.assets.compactMap {
            asset -> AuditIssue? in
            guard let suggestion = typoSuggestion(
                fileName: asset.outputURL.lastPathComponent
            ) else {
                return nil
            }

            return AuditIssue(
                id: "naming:\(asset.outputRelativePath)",
                kind: .namingWarning,
                primaryRelativePath:
                    asset.outputRelativePath,
                relatedRelativePaths: [],
                sourceRelativePath:
                    activeOutputToSource[
                        asset.outputRelativePath
                    ],
                title: asset.outputURL.lastPathComponent,
                detail:
                    "The filename contains a likely typo. Review the suggested correction before applying a rename.",
                primarySourceBacked:
                    activePaths.contains(
                        asset.outputRelativePath
                    ),
                relatedSourceBacked: [],
                suggestedFileName: suggestion
            )
        }

        progressHandler?(
            0.94,
            "Reconciling audit queue and saved review state…"
        )

        let issues = (
            destinationOnlyIssues
            + duplicateIssues
            + namingIssues
            + missingIssues
        ).sorted {
            if issuePriority($0.kind)
                != issuePriority($1.kind)
            {
                return issuePriority($0.kind)
                    < issuePriority($1.kind)
            }

            return $0.primaryRelativePath
                .localizedStandardCompare(
                    $1.primaryRelativePath
                ) == .orderedAscending
        }

        let summary = AuditSummary(
            totalDestinationAssets:
                destination.assets.count,
            sourceBackedOutputs: activePaths.count,
            destinationOnlyCount:
                destinationOnlyIssues.count,
            duplicateIssueCount:
                duplicateIssues.count,
            namingWarningCount:
                namingIssues.count,
            missingOutputCount:
                missingIssues.count
        )

        progressHandler?(1, "Audit ready.")

        return AuditScanResult(
            issues: issues,
            summary: summary,
            sourceRootURL: sourceURL,
            destinationRootURL: destinationURL,
            excelURL: excelURL,
            sourceItemsByRelativePath:
                sourceItemsByRelativePath,
            destinationAssetsByRelativePath:
                destinationByPath,
            progress: classifierProgress,
            excelCatalog: excelCatalog
        )
    }

    static func validateRename(
        proposedFileName: String,
        issue: AuditIssue,
        scan: AuditScanResult
    ) -> RenameValidation {
        let trimmed = proposedFileName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            return RenameValidation(
                isValid: false,
                message: "Enter a filename.",
                suggestedFileName:
                    issue.suggestedFileName
            )
        }

        guard !trimmed.contains("/"),
              !trimmed.contains(":")
        else {
            return RenameValidation(
                isValid: false,
                message:
                    "Enter only a filename, not a path.",
                suggestedFileName:
                    issue.suggestedFileName
            )
        }

        guard trimmed.lowercased().hasSuffix(".webp")
        else {
            return RenameValidation(
                isValid: false,
                message:
                    "Finalized asset filenames must end in .webp.",
                suggestedFileName:
                    issue.suggestedFileName
            )
        }

        let originalURL = scan.destinationRootURL
            .appendingPathComponent(
                issue.primaryRelativePath
            )
        let targetURL = originalURL
            .deletingLastPathComponent()
            .appendingPathComponent(trimmed)

        if targetURL.path != originalURL.path,
           FileManager.default.fileExists(
            atPath: targetURL.path
           )
        {
            return RenameValidation(
                isValid: false,
                message:
                    "A file with that name already exists in this Model/Product folder.",
                suggestedFileName:
                    issue.suggestedFileName
            )
        }

        let suspicious = typoSuggestion(
            fileName: trimmed
        )
        if let suspicious,
           suspicious.caseInsensitiveCompare(
            trimmed
           ) != .orderedSame
        {
            return RenameValidation(
                isValid: false,
                message:
                    "The proposed filename still contains a likely typo.",
                suggestedFileName: suspicious
            )
        }

        let sourceSuggestion = closestExpectedFileName(
            to: trimmed,
            issue: issue,
            scan: scan
        )

        if let sourceSuggestion,
           sourceSuggestion.caseInsensitiveCompare(
            trimmed
           ) != .orderedSame
        {
            let distance = levenshtein(
                normalizedStem(trimmed),
                normalizedStem(sourceSuggestion)
            )

            if distance <= 3 {
                return RenameValidation(
                    isValid: true,
                    message:
                        "Valid filename. A close current-source name is \(sourceSuggestion).",
                    suggestedFileName:
                        sourceSuggestion
                )
            }
        }

        if let catalog = scan.excelCatalog {
            let product = issue.primaryRelativePath
                .split(separator: "/")
                .first
                .map(String.init)
                ?? ""
            let sku = product
                .split(separator: "_")
                .first
                .map(String.init)?
                .uppercased()
                ?? ""

            if !sku.isEmpty,
               !catalog.knownSKUs.contains(sku),
               sku != "P105LS"
            {
                return RenameValidation(
                    isValid: true,
                    message:
                        "Filename is structurally valid. Note: destination SKU \(sku) was not found as a direct SKU in the supplied workbook.",
                    suggestedFileName:
                        sourceSuggestion
                )
            }
        }

        return RenameValidation(
            isValid: true,
            message:
                "Filename is valid and does not collide with another finalized output.",
            suggestedFileName:
                sourceSuggestion
        )
    }

    static func makeDifferenceImage(
        left: URL,
        right: URL,
        magickPath: String
    ) throws -> URL {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "TotalImageAssetAudit",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let identifier = UUID().uuidString
        let leftNormalized = root.appendingPathComponent(
            "\(identifier)-left.png"
        )
        let rightNormalized = root.appendingPathComponent(
            "\(identifier)-right.png"
        )
        let difference = root.appendingPathComponent(
            "\(identifier)-difference.png"
        )

        defer {
            try? FileManager.default.removeItem(
                at: leftNormalized
            )
            try? FileManager.default.removeItem(
                at: rightNormalized
            )
        }

        try runImageMagick(
            magickPath: magickPath,
            arguments: [
                left.path,
                "-auto-orient",
                "-background", "white",
                "-alpha", "remove",
                "-alpha", "off",
                "-resize", "1000x1000>",
                "-gravity", "center",
                "-extent", "1000x1000",
                leftNormalized.path
            ],
            timeout: 20
        )

        try runImageMagick(
            magickPath: magickPath,
            arguments: [
                right.path,
                "-auto-orient",
                "-background", "white",
                "-alpha", "remove",
                "-alpha", "off",
                "-resize", "1000x1000>",
                "-gravity", "center",
                "-extent", "1000x1000",
                rightNormalized.path
            ],
            timeout: 20
        )

        try runImageMagick(
            magickPath: magickPath,
            arguments: [
                leftNormalized.path,
                rightNormalized.path,
                "-compose", "difference",
                "-composite",
                difference.path
            ],
            timeout: 20
        )

        return difference
    }

    static func buildChangePlan(
        scan: AuditScanResult,
        issues: [AuditIssue],
        document: AuditDocument
    ) -> AuditChangePlan {
        let fileManager = FileManager.default
        let issueByID = Dictionary(
            uniqueKeysWithValues: issues.map {
                ($0.id, $0)
            }
        )

        struct Candidate {
            let issue: AuditIssue
            let decision: AuditDecision
        }

        let destructive = document.decisions.values.compactMap {
            decision -> Candidate? in
            guard decision.action == .delete
                    || decision.action == .rename,
                  let issue = issueByID[decision.issueID]
            else {
                return nil
            }

            return Candidate(
                issue: issue,
                decision: decision
            )
        }

        let grouped = Dictionary(
            grouping: destructive,
            by: { $0.issue.primaryRelativePath }
        )

        var changes: [AuditPlannedChange] = []
        var conflicts: [AuditPlanConflict] = []
        var supersededDecisionCount = 0

        for path in grouped.keys.sorted() {
            guard let group = grouped[path] else {
                continue
            }

            let sorted = group.sorted {
                if $0.decision.decidedAt
                    != $1.decision.decidedAt
                {
                    return $0.decision.decidedAt
                        > $1.decision.decidedAt
                }

                return $0.issue.id > $1.issue.id
            }

            guard let selected = sorted.first else {
                continue
            }

            supersededDecisionCount += max(
                0,
                sorted.count - 1
            )

            let issue = selected.issue
            let decision = selected.decision
            let from = scan.destinationRootURL
                .appendingPathComponent(path)
            let fromExists = fileManager.fileExists(
                atPath: from.path
            )

            switch decision.action {
            case .delete:
                if issue.primarySourceBacked {
                    conflicts.append(
                        AuditPlanConflict(
                            id: "active-delete:\(path)",
                            paths: [path],
                            message:
                                "Delete is not allowed because this output is still source-backed."
                        )
                    )
                    continue
                }

                changes.append(
                    AuditPlannedChange(
                        issueID: issue.id,
                        action: .delete,
                        originalRelativePath: path,
                        targetRelativePath: nil,
                        sourceBacked: false,
                        decidedAt: decision.decidedAt,
                        state:
                            fromExists
                            ? .ready
                            : .alreadySatisfied,
                        note:
                            fromExists
                            ? nil
                            : "File is already absent; delete is already satisfied."
                    )
                )

            case .rename:
                guard let proposed =
                    decision.proposedFileName?
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ),
                      !proposed.isEmpty
                else {
                    conflicts.append(
                        AuditPlanConflict(
                            id: "missing-rename:\(path)",
                            paths: [path],
                            message:
                                "Rename has no target filename."
                        )
                    )
                    continue
                }

                let to = from
                    .deletingLastPathComponent()
                    .appendingPathComponent(proposed)
                let targetRelativePath =
                    relativePath(
                        to,
                        root:
                            scan.destinationRootURL
                    )
                let targetExists =
                    fileManager.fileExists(
                        atPath: to.path
                    )

                if !fromExists {
                    if targetExists {
                        let targetOwnedByOtherSource =
                            scan.progress.records.contains {
                                sourcePath, record in
                                record.outputRelativePath
                                    == targetRelativePath
                                    && sourcePath
                                        != issue.sourceRelativePath
                            }

                        if targetOwnedByOtherSource {
                            conflicts.append(
                                AuditPlanConflict(
                                    id:
                                        "rename-target-owned:\(path)",
                                    paths: [
                                        path,
                                        targetRelativePath
                                    ],
                                    message:
                                        "The original file is missing and the rename target is already owned by another current source record."
                                )
                            )
                            continue
                        }

                        changes.append(
                            AuditPlannedChange(
                                issueID: issue.id,
                                action: .rename,
                                originalRelativePath:
                                    path,
                                targetRelativePath:
                                    targetRelativePath,
                                sourceBacked:
                                    issue.primarySourceBacked,
                                decidedAt:
                                    decision.decidedAt,
                                state:
                                    .alreadySatisfied,
                                note:
                                    "Original is already absent and the requested rename target exists; this will be reconciled without moving the file again."
                            )
                        )
                    } else {
                        conflicts.append(
                            AuditPlanConflict(
                                id:
                                    "rename-source-missing:\(path)",
                                paths: [
                                    path,
                                    targetRelativePath
                                ],
                                message:
                                    "The file to rename no longer exists and the requested target does not exist either. Re-scan or restore the file before applying."
                            )
                        )
                    }
                    continue
                }

                let validation = validateRename(
                    proposedFileName: proposed,
                    issue: issue,
                    scan: scan
                )

                if !validation.isValid {
                    conflicts.append(
                        AuditPlanConflict(
                            id:
                                "invalid-rename:\(path)",
                            paths: [
                                path,
                                targetRelativePath
                            ],
                            message:
                                validation.message
                        )
                    )
                    continue
                }

                changes.append(
                    AuditPlannedChange(
                        issueID: issue.id,
                        action: .rename,
                        originalRelativePath: path,
                        targetRelativePath:
                            targetRelativePath,
                        sourceBacked:
                            issue.primarySourceBacked,
                        decidedAt:
                            decision.decidedAt,
                        state: .ready,
                        note: nil
                    )
                )

            default:
                break
            }
        }

        let readyRenames = changes.filter {
            $0.action == .rename
                && $0.state == .ready
        }

        let byTarget = Dictionary(
            grouping: readyRenames.compactMap {
                change -> (String, AuditPlannedChange)? in
                guard let target =
                    change.targetRelativePath
                else {
                    return nil
                }
                return (target, change)
            },
            by: { $0.0 }
        )

        for (target, group) in byTarget
            where group.count > 1
        {
            conflicts.append(
                AuditPlanConflict(
                    id: "duplicate-target:\(target)",
                    paths:
                        group.map {
                            $0.1.originalRelativePath
                        } + [target],
                    message:
                        "More than one queued rename points to the same destination filename."
                )
            )
        }

        let readyOriginals = Set(
            changes
                .filter { $0.state == .ready }
                .map(\.originalRelativePath)
        )

        for change in readyRenames {
            guard let target =
                change.targetRelativePath,
                  target
                    != change.originalRelativePath,
                  readyOriginals.contains(target)
            else {
                continue
            }

            conflicts.append(
                AuditPlanConflict(
                    id:
                        "target-is-source:\(change.originalRelativePath)",
                    paths: [
                        change.originalRelativePath,
                        target
                    ],
                    message:
                        "A queued rename targets another file that is also scheduled to change. Resolve that chain before applying."
                )
            )
        }

        return AuditChangePlan(
            changes: changes.sorted {
                $0.originalRelativePath
                    .localizedStandardCompare(
                        $1.originalRelativePath
                    ) == .orderedAscending
            },
            conflicts: conflicts,
            supersededDecisionCount:
                supersededDecisionCount
        )
    }

    static func applyChanges(
        scan: AuditScanResult,
        issues: [AuditIssue],
        document: inout AuditDocument
    ) throws -> AuditApplyManifest {
        let fileManager = FileManager.default
        let issueByID = Dictionary(
            uniqueKeysWithValues: issues.map {
                ($0.id, $0)
            }
        )
        let plan = buildChangePlan(
            scan: scan,
            issues: issues,
            document: document
        )

        guard plan.conflicts.isEmpty else {
            throw AuditApplyError.changePlanConflict(
                plan.conflicts.map(\.message)
                    .joined(separator: "\n")
            )
        }

        guard !plan.changes.isEmpty else {
            throw AuditApplyError.noChanges
        }

        let ready = plan.changes.filter {
            $0.state == .ready
        }
        let reconciled = plan.changes.filter {
            $0.state == .alreadySatisfied
        }

        let backupRoot = try AuditStore.backupRoot()
        let progressURL = ProgressStore.progressURL(
            rootURL: scan.destinationRootURL
        )
        let progressExistedBeforeApply =
            fileManager.fileExists(
                atPath: progressURL.path
            )
        let progressBackup = backupRoot
            .appendingPathComponent(
                ".total-image-classifier",
                isDirectory: true
            )
            .appendingPathComponent(
                ProgressStore.fileName
            )

        if progressExistedBeforeApply {
            try fileManager.createDirectory(
                at: progressBackup
                    .deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(
                at: progressURL,
                to: progressBackup
            )
        }

        var manifestOperations:
            [AuditApplyOperation] = []
        var updatedProgress = scan.progress
        var applied:
            [(from: URL, to: URL?)] = []

        func reconcileRename(
            _ change: AuditPlannedChange
        ) {
            guard change.action == .rename,
                  let target =
                    change.targetRelativePath,
                  let issue =
                    issueByID[change.issueID]
            else {
                return
            }

            let targetURL = scan.destinationRootURL
                .appendingPathComponent(target)

            if issue.primarySourceBacked {
                updateClassifierProgress(
                    fromRelativePath:
                        change.originalRelativePath,
                    toRelativePath: target,
                    newStem:
                        targetURL
                        .deletingPathExtension()
                        .lastPathComponent,
                    progress: &updatedProgress
                )
            } else {
                let newIssueID =
                    "destination-only:\(target)"
                document.decisions[newIssueID] =
                    AuditDecision(
                        issueID: newIssueID,
                        action: .keep,
                        proposedFileName: nil,
                        note:
                            "Reviewed and renamed during audit apply.",
                        decidedAt: Date()
                    )
            }
        }

        for change in reconciled {
            reconcileRename(change)
        }

        do {
            for change in ready {
                guard let issue =
                    issueByID[change.issueID]
                else {
                    throw AuditApplyError
                        .changePlanConflict(
                            "A queued audit issue disappeared before apply: \(change.issueID)"
                        )
                }

                let from = scan.destinationRootURL
                    .appendingPathComponent(
                        change.originalRelativePath
                    )

                if change.action == .delete,
                   !fileManager.fileExists(
                    atPath: from.path
                   )
                {
                    continue
                }

                guard fileManager.fileExists(
                    atPath: from.path
                ) else {
                    throw AuditApplyError.missingFile(
                        change.originalRelativePath
                    )
                }

                let hashBefore = try sha256(from)
                let relativeBackup =
                    change.originalRelativePath
                let backupURL = backupRoot
                    .appendingPathComponent(
                        relativeBackup
                    )

                try fileManager.createDirectory(
                    at: backupURL
                        .deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(
                    at: from,
                    to: backupURL
                )

                guard try sha256(from)
                    == hashBefore
                else {
                    throw AuditApplyError
                        .fileChangedDuringApply(
                            change.originalRelativePath
                        )
                }

                if change.action == .rename {
                    guard let target =
                        change.targetRelativePath
                    else {
                        throw AuditApplyError
                            .invalidRename(
                                change.originalRelativePath
                            )
                    }

                    let to = scan.destinationRootURL
                        .appendingPathComponent(target)

                    guard !fileManager.fileExists(
                        atPath: to.path
                    ) else {
                        throw AuditApplyError
                            .targetExists(
                                to.lastPathComponent
                            )
                    }

                    try fileManager.moveItem(
                        at: from,
                        to: to
                    )

                    reconcileRename(change)

                    manifestOperations.append(
                        AuditApplyOperation(
                            kind: .rename,
                            originalRelativePath:
                                change.originalRelativePath,
                            targetRelativePath: target,
                            backupRelativePath:
                                relativeBackup,
                            originalSHA256:
                                hashBefore
                        )
                    )
                    applied.append(
                        (from: from, to: to)
                    )
                } else {
                    guard !issue.primarySourceBacked
                    else {
                        throw AuditApplyError
                            .activeOutputDeleteForbidden(
                                change.originalRelativePath
                            )
                    }

                    try fileManager.removeItem(
                        at: from
                    )

                    manifestOperations.append(
                        AuditApplyOperation(
                            kind: .delete,
                            originalRelativePath:
                                change.originalRelativePath,
                            targetRelativePath: nil,
                            backupRelativePath:
                                relativeBackup,
                            originalSHA256:
                                hashBefore
                        )
                    )
                    applied.append(
                        (from: from, to: nil)
                    )
                }
            }

            try ProgressStore.save(
                updatedProgress,
                rootURL: scan.destinationRootURL
            )

            for operation in manifestOperations {
                let original = scan.destinationRootURL
                    .appendingPathComponent(
                        operation.originalRelativePath
                    )

                switch operation.kind {
                case .delete:
                    guard !fileManager.fileExists(
                        atPath: original.path
                    ) else {
                        throw AuditApplyError
                            .verificationFailed(
                                operation
                                    .originalRelativePath
                            )
                    }

                case .rename:
                    guard let target =
                        operation.targetRelativePath
                    else {
                        throw AuditApplyError
                            .verificationFailed(
                                operation
                                    .originalRelativePath
                            )
                    }

                    let targetURL =
                        scan.destinationRootURL
                        .appendingPathComponent(target)

                    guard fileManager.fileExists(
                        atPath: targetURL.path
                    ),
                    try sha256(targetURL)
                        == operation.originalSHA256
                    else {
                        throw AuditApplyError
                            .verificationFailed(target)
                    }
                }
            }
        } catch {
            do {
                try rollbackApplied(
                    applied,
                    backupRoot: backupRoot,
                    destinationRoot:
                        scan.destinationRootURL,
                    progressBackup:
                        progressBackup,
                    progressExistedBeforeApply:
                        progressExistedBeforeApply
                )
            } catch let rollbackError {
                throw AuditApplyError
                    .applyAndRollbackFailed(
                        apply:
                            error.localizedDescription,
                        rollback:
                            rollbackError
                            .localizedDescription,
                        backup:
                            backupRoot.path
                    )
            }

            throw error
        }

        let manifest = AuditApplyManifest(
            id: UUID().uuidString,
            appliedAt: Date(),
            backupRootPath: backupRoot.path,
            operations: manifestOperations
        )
        document.lastApply = manifest
        return manifest
    }

    static func rollback(
        manifest: AuditApplyManifest,
        destinationRootURL: URL
    ) throws {
        let fileManager = FileManager.default
        let backupRoot = URL(
            fileURLWithPath:
                manifest.backupRootPath,
            isDirectory: true
        )

        guard fileManager.fileExists(
            atPath: backupRoot.path
        ) else {
            throw AuditApplyError.backupMissing
        }

        for operation in manifest.operations {
            let original = destinationRootURL
                .appendingPathComponent(
                    operation.originalRelativePath
                )
            let backup = backupRoot
                .appendingPathComponent(
                    operation.backupRelativePath
                )

            guard fileManager.fileExists(
                atPath: backup.path
            ),
            try sha256(backup)
                == operation.originalSHA256
            else {
                throw AuditApplyError.backupInvalid(
                    operation.backupRelativePath
                )
            }

            switch operation.kind {
            case .delete:
                guard !fileManager.fileExists(
                    atPath: original.path
                ) else {
                    throw AuditApplyError
                        .rollbackConflict(
                            operation
                                .originalRelativePath
                        )
                }

            case .rename:
                guard let target =
                    operation.targetRelativePath
                else {
                    throw AuditApplyError
                        .rollbackConflict(
                            operation
                                .originalRelativePath
                        )
                }

                let targetURL = destinationRootURL
                    .appendingPathComponent(target)
                guard fileManager.fileExists(
                    atPath: targetURL.path
                ),
                try sha256(targetURL)
                    == operation.originalSHA256
                else {
                    throw AuditApplyError
                        .rollbackConflict(target)
                }
            }
        }

        for operation in manifest.operations.reversed() {
            let original = destinationRootURL
                .appendingPathComponent(
                    operation.originalRelativePath
                )
            let backup = backupRoot
                .appendingPathComponent(
                    operation.backupRelativePath
                )

            try fileManager.createDirectory(
                at: original.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if let target = operation.targetRelativePath {
                let targetURL = destinationRootURL
                    .appendingPathComponent(target)
                if fileManager.fileExists(
                    atPath: targetURL.path
                ) {
                    try fileManager.removeItem(
                        at: targetURL
                    )
                }
            }

            try fileManager.copyItem(
                at: backup,
                to: original
            )
        }

        let progressBackup = backupRoot
            .appendingPathComponent(
                ".total-image-classifier",
                isDirectory: true
            )
            .appendingPathComponent(
                ProgressStore.fileName
            )
        let progressURL = ProgressStore.progressURL(
            rootURL: destinationRootURL
        )

        if fileManager.fileExists(
            atPath: progressBackup.path
        ) {
            try fileManager.createDirectory(
                at: progressURL
                    .deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(
                atPath: progressURL.path
            ) {
                try fileManager.removeItem(
                    at: progressURL
                )
            }

            try fileManager.copyItem(
                at: progressBackup,
                to: progressURL
            )
        }
    }

    private static func processDuplicateGroup(
        _ assets: [DestinationAsset],
        activeOutputToSource: [String: String],
        relatedForOrphan: inout [String: String],
        duplicateIssues: inout [AuditIssue],
        duplicatePathSets: inout Set<String>,
        reason: String
    ) {
        let sorted = assets.sorted {
            $0.outputRelativePath
                < $1.outputRelativePath
        }
        let active = sorted.filter {
            activeOutputToSource[
                $0.outputRelativePath
            ] != nil
        }
        let orphan = sorted.filter {
            activeOutputToSource[
                $0.outputRelativePath
            ] == nil
        }

        if let keeper = active.first {
            for asset in orphan {
                relatedForOrphan[
                    asset.outputRelativePath
                ] = keeper.outputRelativePath
            }
        } else if sorted.count > 1 {
            for asset in sorted.dropFirst() {
                relatedForOrphan[
                    asset.outputRelativePath
                ] = sorted[0].outputRelativePath
            }
        }

        guard active.count > 1 else { return }

        let setKey = active
            .map(\.outputRelativePath)
            .sorted()
            .joined(separator: "\n")

        guard duplicatePathSets.insert(setKey).inserted
        else {
            return
        }

        let primary = active[0]
        let related = Array(active.dropFirst())

        duplicateIssues.append(
            AuditIssue(
                id:
                    "duplicate:\(stableID(setKey))",
                kind: .pixelDuplicate,
                primaryRelativePath:
                    primary.outputRelativePath,
                relatedRelativePaths:
                    related.map(\.outputRelativePath),
                sourceRelativePath:
                    activeOutputToSource[
                        primary.outputRelativePath
                    ],
                title:
                    primary.outputURL.lastPathComponent,
                detail:
                    "\(reason) All files in this group are still source-backed, so Audit mode will never offer destructive deletion here.",
                primarySourceBacked: true,
                relatedSourceBacked:
                    related.map { _ in true },
                suggestedFileName: nil
            )
        )
    }

    private static func missingIssue(
        sourcePath: String,
        expectedOutputPath: String?
    ) -> AuditIssue {
        AuditIssue(
            id: "missing:\(sourcePath)",
            kind: .missingOutput,
            primaryRelativePath:
                expectedOutputPath ?? sourcePath,
            relatedRelativePaths: [],
            sourceRelativePath: sourcePath,
            title:
                URL(fileURLWithPath: sourcePath)
                    .lastPathComponent,
            detail:
                expectedOutputPath == nil
                ? "This current source record has no finalized output path in classifier progress."
                : "Classifier progress points to a finalized output that no longer exists.",
            primarySourceBacked: true,
            relatedSourceBacked: [],
            suggestedFileName: nil
        )
    }

    private static func logicalGroupKey(
        _ asset: DestinationAsset
    ) -> String {
        [
            asset.productFolderName,
            asset.classification.rawValue,
            canonicalCollisionStem(
                asset.outputStem
            )
        ].joined(separator: "|")
    }

    private static func canonicalCollisionStem(
        _ value: String
    ) -> String {
        var stem = value.lowercased()

        let suffixes = [
            "__jpg",
            "__jpeg",
            "__png",
            "__webp",
            "__avif"
        ]

        var changed = true
        while changed {
            changed = false

            for suffix in suffixes {
                if stem.hasSuffix(suffix) {
                    stem.removeLast(suffix.count)
                    changed = true
                }
            }

            if stem.range(
                of: #"_\d+$"#,
                options: .regularExpression
            ) != nil {
                stem = stem.replacingOccurrences(
                    of: #"_\d+$"#,
                    with: "",
                    options: .regularExpression
                )
                changed = true
            }
        }

        return stem
    }

    private static func closestAsset(
        to asset: DestinationAsset,
        candidates: [DestinationAsset]
    ) -> DestinationAsset? {
        candidates.min {
            levenshtein(
                normalizedStem(asset.outputStem),
                normalizedStem($0.outputStem)
            )
            <
            levenshtein(
                normalizedStem(asset.outputStem),
                normalizedStem($1.outputStem)
            )
        }
    }

    private static func closestExpectedFileName(
        to proposed: String,
        issue: AuditIssue,
        scan: AuditScanResult
    ) -> String? {
        let product = issue.primaryRelativePath
            .split(separator: "/")
            .first
            .map(String.init)
            ?? ""

        var candidates = Set<String>()

        for (sourcePath, record) in scan.progress.records {
            guard let item =
                scan.sourceItemsByRelativePath[sourcePath]
            else {
                continue
            }

            let destinationProduct =
                record.destinationProductFolderName
                ?? sourcePath
                    .split(separator: "/")
                    .first
                    .map(String.init)
                ?? ""

            guard destinationProduct == product else {
                continue
            }

            let stem = record.outputStemOverride
                ?? item.outputStem
            candidates.insert(stem + ".webp")
        }

        guard !candidates.isEmpty else { return nil }

        return candidates.min {
            levenshtein(
                normalizedStem(proposed),
                normalizedStem($0)
            )
            <
            levenshtein(
                normalizedStem(proposed),
                normalizedStem($1)
            )
        }
    }

    private static func typoSuggestion(
        fileName: String
    ) -> String? {
        let replacements: [(String, String)] = [
            ("FRRONT", "FRONT"),
            ("FROTN", "FRONT"),
            ("NACY", "NAVY"),
            ("CLOESUP", "CLOSEUP"),
            ("CLOSE_UP", "CLOSEUP")
        ]

        var suggestion = fileName
        var changed = false

        for (wrong, correct) in replacements {
            if suggestion.range(
                of: wrong,
                options: .caseInsensitive
            ) != nil {
                suggestion =
                    suggestion.replacingOccurrences(
                        of: wrong,
                        with: correct,
                        options: .caseInsensitive
                    )
                changed = true
            }
        }

        return changed ? suggestion : nil
    }

    private static func normalizedStem(
        _ value: String
    ) -> String {
        URL(fileURLWithPath: value)
            .deletingPathExtension()
            .lastPathComponent
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: Locale(
                    identifier: "en_US_POSIX"
                )
            )
            .uppercased()
            .replacingOccurrences(
                of: #"[^A-Z0-9]+"#,
                with: "",
                options: .regularExpression
            )
    }

    private static func issuePriority(
        _ kind: AuditIssueKind
    ) -> Int {
        switch kind {
        case .destinationOnly: return 0
        case .pixelDuplicate: return 1
        case .namingWarning: return 2
        case .missingOutput: return 3
        }
    }

    static func levenshtein(
        _ lhs: String,
        _ rhs: String
    ) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)

        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)

        for (i, leftCharacter) in left.enumerated() {
            var current = [i + 1]

            for (j, rightCharacter) in right.enumerated() {
                let insertion = current[j] + 1
                let deletion = previous[j + 1] + 1
                let substitution =
                    previous[j]
                    + (
                        leftCharacter
                            == rightCharacter ? 0 : 1
                    )

                current.append(
                    min(
                        min(insertion, deletion),
                        substitution
                    )
                )
            }

            previous = current
        }

        return previous[right.count]
    }

    private static func sha256(
        _ url: URL
    ) throws -> String {
        let handle = try FileHandle(
            forReadingFrom: url
        )
        defer {
            try? handle.close()
        }

        var hasher = SHA256()

        while autoreleasepool(
            invoking: {
                let data = try? handle.read(
                    upToCount: 1_048_576
                )

                guard let data,
                      !data.isEmpty
                else {
                    return false
                }

                hasher.update(data: data)
                return true
            }
        ) {}

        return hasher.finalize()
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
    }

    private static func pixelSignature(
        _ url: URL,
        magickPath: String
    ) throws -> String {
        try runImageMagick(
            magickPath: magickPath,
            arguments: [
                url.path,
                "-auto-orient",
                "-format",
                "%wx%h:%[signature]",
                "info:"
            ],
            timeout: 20
        )
    }

    @discardableResult
    private static func runImageMagick(
        magickPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(
            fileURLWithPath: magickPath
        )
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let semaphore = DispatchSemaphore(
            value: 0
        )
        DispatchQueue.global(
            qos: .utility
        ).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(
            timeout: .now() + timeout
        ) == .timedOut {
            process.terminate()
            _ = semaphore.wait(
                timeout: .now() + 2
            )
            throw AuditApplyError.imageMagickTimeout(
                arguments.first ?? "image"
            )
        }

        let output = stdout.fileHandleForReading
            .readDataToEndOfFile()
        let error = stderr.fileHandleForReading
            .readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            throw AuditApplyError.imageMagickFailed(
                String(
                    data: error,
                    encoding: .utf8
                ) ?? "ImageMagick failed."
            )
        }

        return String(
            data: output,
            encoding: .utf8
        )?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
    }

    private static func stableID(
        _ value: String
    ) -> String {
        let digest = SHA256.hash(
            data: Data(value.utf8)
        )
        return digest.prefix(12)
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
    }

    private static func relativePath(
        _ url: URL,
        root: URL
    ) -> String {
        let rootPath =
            root.standardizedFileURL.path
        let path =
            url.standardizedFileURL.path

        if path.hasPrefix(rootPath + "/") {
            return String(
                path.dropFirst(
                    rootPath.count + 1
                )
            )
        }

        return path
    }

    private static func updateClassifierProgress(
        fromRelativePath: String,
        toRelativePath: String,
        newStem: String,
        progress: inout ProgressDocument
    ) {
        guard let match = progress.records.first(
            where: {
                $0.value.outputRelativePath
                    == fromRelativePath
            }
        ) else {
            return
        }

        var record = match.value
        record.outputRelativePath =
            toRelativePath
        record.outputStemOverride =
            newStem
        record.updatedAt = Date()
        progress.records[match.key] = record
    }

    private static func rollbackApplied(
        _ applied: [(from: URL, to: URL?)],
        backupRoot: URL,
        destinationRoot: URL,
        progressBackup: URL
    ) {
        let fileManager = FileManager.default

        for operation in applied.reversed() {
            let relative = relativePath(
                operation.from,
                root: destinationRoot
            )
            let backup = backupRoot
                .appendingPathComponent(relative)

            if let to = operation.to,
               fileManager.fileExists(
                atPath: to.path
               )
            {
                try? fileManager.removeItem(
                    at: to
                )
            }

            if fileManager.fileExists(
                atPath: backup.path
            ) {
                try? fileManager.createDirectory(
                    at: operation.from
                        .deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if fileManager.fileExists(
                    atPath: operation.from.path
                ) {
                    try? fileManager.removeItem(
                        at: operation.from
                    )
                }

                try? fileManager.copyItem(
                    at: backup,
                    to: operation.from
                )
            }
        }

        if fileManager.fileExists(
            atPath: progressBackup.path
        ) {
            let progressURL =
                ProgressStore.progressURL(
                    rootURL: destinationRoot
                )

            if fileManager.fileExists(
                atPath: progressURL.path
            ) {
                try? fileManager.removeItem(
                    at: progressURL
                )
            }

            try? fileManager.createDirectory(
                at: progressURL
                    .deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.copyItem(
                at: progressBackup,
                to: progressURL
            )
        }
    }
}

enum AuditApplyError: LocalizedError {
    case noChanges
    case activeOutputDeleteForbidden(String)
    case invalidRename(String)
    case missingFile(String)
    case targetExists(String)
    case fileChangedDuringApply(String)
    case verificationFailed(String)
    case backupMissing
    case backupInvalid(String)
    case rollbackConflict(String)
    case imageMagickTimeout(String)
    case imageMagickFailed(String)

    var errorDescription: String? {
        switch self {
        case .noChanges:
            return "There are no Delete or Rename decisions waiting to be applied."
        case .activeOutputDeleteForbidden(let path):
            return "Refusing to delete a current source-backed output: \(path)"
        case .invalidRename(let detail):
            return "Rename is not safe: \(detail)"
        case .missingFile(let path):
            return "A file selected for audit changes no longer exists: \(path)"
        case .targetExists(let name):
            return "Rename target already exists: \(name)"
        case .fileChangedDuringApply(let path):
            return "A file changed while the audit plan was being applied: \(path)"
        case .verificationFailed(let path):
            return "Post-apply verification failed for: \(path)"
        case .backupMissing:
            return "The previous audit backup is no longer available."
        case .backupInvalid(let path):
            return "The previous audit backup does not match its recorded hash: \(path)"
        case .rollbackConflict(let path):
            return "Rollback stopped because a file changed after the audit apply: \(path)"
        case .imageMagickTimeout(let path):
            return "ImageMagick timed out while checking: \(path)"
        case .imageMagickFailed(let message):
            return message
        }
    }
}
