import Foundation

enum AssetClassification: String, Codable, CaseIterable, Sendable {
    case model
    case product

    var label: String {
        switch self {
        case .model: return "Model"
        case .product: return "Product"
        }
    }

    var outputFolderName: String {
        rawValue
    }
}

enum ProcessingStatus: String, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
}

struct AssetItem: Identifiable, Hashable, Sendable {
    let id: String
    let sourceURL: URL
    let relativePath: String
    let outputStem: String
    let fileSize: Int64
    let modificationTime: TimeInterval

    var fileName: String {
        sourceURL.lastPathComponent
    }

    var productFolderName: String {
        sourceURL.deletingLastPathComponent().lastPathComponent
    }
}

struct AssetProgressRecord: Codable, Sendable {
    var relativePath: String
    var classification: AssetClassification
    var status: ProcessingStatus
    var revision: String
    var outputRelativePath: String?
    var error: String?
    var fileSize: Int64
    var modificationTime: TimeInterval
    var updatedAt: Date
}

struct ProgressDocument: Codable, Sendable {
    var version: Int = 1
    var rootFolderName: String
    var records: [String: AssetProgressRecord] = [:]
}

struct ProcessingJob: Sendable {
    let sourceURL: URL
    let rootURL: URL
    let relativePath: String
    let outputStem: String
    let classification: AssetClassification
    let revision: String
}

struct ProcessingResult: Sendable {
    let outputURL: URL
    let outputRelativePath: String
    let bboxDescription: String?
    let canvasDescription: String?
}
