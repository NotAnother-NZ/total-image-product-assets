import Foundation

enum AssetScanner {
    static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "avif"
    ]

    static func scan(rootURL: URL) throws -> [AssetItem] {
        let fileManager = FileManager.default
        let rootPath = rootURL.standardizedFileURL.path

        let immediateChildren = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let productFolders = try immediateChildren
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                return values.isDirectory == true && url.lastPathComponent.lowercased() != "webp"
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        struct RawAsset {
            let url: URL
            let relativePath: String
            let stem: String
            let ext: String
            let fileSize: Int64
            let modificationTime: TimeInterval
            let collisionKey: String
        }

        var rawAssets: [RawAsset] = []

        for productFolder in productFolders {
            guard let enumerator = fileManager.enumerator(
                at: productFolder,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                let values = try url.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .fileSizeKey,
                        .contentModificationDateKey
                    ]
                )

                if values.isDirectory == true {
                    if url.lastPathComponent.lowercased() == "webp" {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard values.isRegularFile == true else { continue }

                let ext = url.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else { continue }

                let standardizedPath = url.standardizedFileURL.path
                guard standardizedPath.hasPrefix(rootPath + "/") else { continue }

                let relativePath = String(standardizedPath.dropFirst(rootPath.count + 1))
                let stem = url.deletingPathExtension().lastPathComponent
                let parentRelative = url.deletingLastPathComponent().standardizedFileURL.path
                    .replacingOccurrences(of: rootPath + "/", with: "")

                rawAssets.append(
                    RawAsset(
                        url: url,
                        relativePath: relativePath,
                        stem: stem,
                        ext: ext,
                        fileSize: Int64(values.fileSize ?? 0),
                        modificationTime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                        collisionKey: (parentRelative + "|" + stem).lowercased()
                    )
                )
            }
        }

        let collisionCounts = Dictionary(
            grouping: rawAssets,
            by: \.collisionKey
        ).mapValues(\.count)

        return rawAssets
            .map { raw in
                let hasCollision = (collisionCounts[raw.collisionKey] ?? 0) > 1
                let outputStem = hasCollision
                    ? "\(raw.stem)__\(raw.ext)"
                    : raw.stem

                return AssetItem(
                    id: raw.relativePath,
                    sourceURL: raw.url,
                    relativePath: raw.relativePath,
                    outputStem: outputStem,
                    fileSize: raw.fileSize,
                    modificationTime: raw.modificationTime
                )
            }
            .sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
    }
}
