import Foundation

enum AuditIssueKind: String, Codable, CaseIterable, Sendable {
    case destinationOnly
    case pixelDuplicate
    case namingWarning
    case missingOutput

    var label: String {
        switch self {
        case .destinationOnly: return "Destination-only"
        case .pixelDuplicate: return "Pixel duplicate"
        case .namingWarning: return "Naming warning"
        case .missingOutput: return "Missing output"
        }
    }
}

enum AuditDecisionKind: String, Codable, CaseIterable, Sendable {
    case unreviewed
    case keep
    case delete
    case rename
    case clientReview
    case intentionalDuplicate
    case sourceIssue

    var label: String {
        switch self {
        case .unreviewed: return "Unreviewed"
        case .keep: return "Keep"
        case .delete: return "Delete"
        case .rename: return "Rename"
        case .clientReview: return "Client review"
        case .intentionalDuplicate: return "Intentional duplicate"
        case .sourceIssue: return "Source issue"
        }
    }
}

enum AuditPreviewMode: String, CaseIterable, Identifiable {
    case sideBySide
    case primary
    case related
    case difference

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sideBySide: return "Side by side"
        case .primary: return "Primary"
        case .related: return "Related"
        case .difference: return "Difference"
        }
    }
}

enum AuditQueueFilter: String, CaseIterable, Identifiable {
    case all
    case destinationOnly
    case duplicates
    case naming
    case missing
    case unresolved

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .destinationOnly: return "Destination-only"
        case .duplicates: return "Duplicates"
        case .naming: return "Naming"
        case .missing: return "Missing"
        case .unresolved: return "Unreviewed"
        }
    }
}

struct AuditIssue: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: AuditIssueKind
    let primaryRelativePath: String
    let relatedRelativePaths: [String]
    let sourceRelativePath: String?
    let title: String
    let detail: String
    let primarySourceBacked: Bool
    let relatedSourceBacked: [Bool]
    let suggestedFileName: String?
}

struct AuditDecision: Codable, Hashable, Sendable {
    let issueID: String
    var action: AuditDecisionKind
    var proposedFileName: String?
    var note: String?
    var decidedAt: Date
}

struct AuditApplyOperation: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case delete
        case rename
    }

    let kind: Kind
    let originalRelativePath: String
    let targetRelativePath: String?
    let backupRelativePath: String
    let originalSHA256: String
}

struct AuditApplyManifest: Codable, Hashable, Sendable {
    let id: String
    let appliedAt: Date
    let backupRootPath: String
    let operations: [AuditApplyOperation]
}

struct AuditDocument: Codable, Sendable {
    var version: Int = 1
    var destinationRootName: String
    var sourceRootName: String?
    var excelFileName: String?
    var decisions: [String: AuditDecision] = [:]
    var lastApply: AuditApplyManifest?
}

struct AuditSummary: Sendable {
    let totalDestinationAssets: Int
    let sourceBackedOutputs: Int
    let destinationOnlyCount: Int
    let duplicateIssueCount: Int
    let namingWarningCount: Int
    let missingOutputCount: Int

    var totalIssues: Int {
        destinationOnlyCount
            + duplicateIssueCount
            + namingWarningCount
            + missingOutputCount
    }
}

struct AuditScanResult: Sendable {
    let issues: [AuditIssue]
    let summary: AuditSummary
    let sourceRootURL: URL
    let destinationRootURL: URL
    let excelURL: URL?
    let sourceItemsByRelativePath: [String: AssetItem]
    let destinationAssetsByRelativePath: [String: DestinationAsset]
    let progress: ProgressDocument
    let excelCatalog: ExcelCatalog?
}

struct RenameValidation: Sendable {
    let isValid: Bool
    let message: String
    let suggestedFileName: String?
}
