import Foundation

enum AuditStore {
    static let stateDirectoryName = ".total-image-audit"
    static let decisionsFileName = "decisions.json"

    static func stateDirectory(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(
            stateDirectoryName,
            isDirectory: true
        )
    }

    static func decisionsURL(rootURL: URL) -> URL {
        stateDirectory(rootURL: rootURL)
            .appendingPathComponent(decisionsFileName)
    }

    static func load(
        rootURL: URL,
        sourceRootName: String?,
        excelFileName: String?
    ) throws -> AuditDocument {
        let url = decisionsURL(rootURL: rootURL)

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return AuditDocument(
                destinationRootName: rootURL.lastPathComponent,
                sourceRootName: sourceRootName,
                excelFileName: excelFileName
            )
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var document = try decoder.decode(
            AuditDocument.self,
            from: data
        )
        document.destinationRootName = rootURL.lastPathComponent
        document.sourceRootName = sourceRootName
        document.excelFileName = excelFileName
        return document
    }

    static func save(
        _ document: AuditDocument,
        rootURL: URL
    ) throws {
        let directory = stateDirectory(rootURL: rootURL)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]
        encoder.dateEncodingStrategy = .iso8601

        try encoder.encode(document).write(
            to: decisionsURL(rootURL: rootURL),
            options: .atomic
        )
    }

    static func reportDirectory(
        rootURL: URL
    ) throws -> URL {
        let directory = stateDirectory(rootURL: rootURL)
            .appendingPathComponent(
                "reports",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    static func writeReports(
        document: AuditDocument,
        issues: [AuditIssue],
        manifest: AuditApplyManifest?,
        rootURL: URL
    ) throws -> (jsonURL: URL, csvURL: URL) {
        let directory = try reportDirectory(rootURL: rootURL)
        let stamp = reportTimestamp()

        let jsonURL = directory.appendingPathComponent(
            "audit-report-\(stamp).json"
        )
        let csvURL = directory.appendingPathComponent(
            "audit-report-\(stamp).csv"
        )

        struct JSONReport: Codable {
            let generatedAt: Date
            let document: AuditDocument
            let issues: [AuditIssue]
            let manifest: AuditApplyManifest?
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]
        encoder.dateEncodingStrategy = .iso8601

        try encoder.encode(
            JSONReport(
                generatedAt: Date(),
                document: document,
                issues: issues,
                manifest: manifest
            )
        ).write(to: jsonURL, options: .atomic)

        var rows: [String] = [
            [
                "issue_id",
                "kind",
                "primary_path",
                "related_paths",
                "source_path",
                "decision",
                "proposed_file_name",
                "note"
            ].joined(separator: ",")
        ]

        for issue in issues {
            let decision = document.decisions[issue.id]
            rows.append(
                [
                    issue.id,
                    issue.kind.rawValue,
                    issue.primaryRelativePath,
                    issue.relatedRelativePaths.joined(
                        separator: " | "
                    ),
                    issue.sourceRelativePath ?? "",
                    decision?.action.rawValue
                        ?? AuditDecisionKind.unreviewed.rawValue,
                    decision?.proposedFileName ?? "",
                    decision?.note ?? ""
                ]
                .map(csvEscape)
                .joined(separator: ",")
            )
        }

        try rows.joined(separator: "\n")
            .appending("\n")
            .write(
                to: csvURL,
                atomically: true,
                encoding: .utf8
            )

        return (jsonURL, csvURL)
    }

    static func backupRoot() throws -> URL {
        guard let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            throw AuditStoreError.downloadsUnavailable
        }

        let root = downloads
            .appendingPathComponent(
                "TotalImageAssetAuditBackups",
                isDirectory: true
            )
            .appendingPathComponent(
                reportTimestamp(),
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private static func reportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return formatter.string(from: Date())
    }

    private static func csvEscape(
        _ value: String
    ) -> String {
        let escaped = value.replacingOccurrences(
            of: "\"",
            with: "\"\""
        )
        return "\"\(escaped)\""
    }
}

enum AuditStoreError: LocalizedError {
    case downloadsUnavailable

    var errorDescription: String? {
        switch self {
        case .downloadsUnavailable:
            return "Could not locate the Downloads folder for the audit backup."
        }
    }
}
