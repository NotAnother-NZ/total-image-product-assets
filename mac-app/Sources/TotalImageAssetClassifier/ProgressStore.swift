import Foundation

enum ProgressStore {
    static let stateDirectoryName = ".total-image-classifier"
    static let fileName = "progress.json"

    static func stateDirectory(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(stateDirectoryName, isDirectory: true)
    }

    static func progressURL(rootURL: URL) -> URL {
        stateDirectory(rootURL: rootURL).appendingPathComponent(fileName)
    }

    static func load(rootURL: URL) throws -> ProgressDocument {
        let url = progressURL(rootURL: rootURL)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return ProgressDocument(rootFolderName: rootURL.lastPathComponent)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var document = try decoder.decode(ProgressDocument.self, from: data)
        document.rootFolderName = rootURL.lastPathComponent
        return document
    }

    static func save(_ document: ProgressDocument, rootURL: URL) throws {
        let fileManager = FileManager.default
        let directory = stateDirectory(rootURL: rootURL)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(document)
        try data.write(to: progressURL(rootURL: rootURL), options: .atomic)
    }

    static func reset(rootURL: URL) throws {
        let directory = stateDirectory(rootURL: rootURL)

        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
