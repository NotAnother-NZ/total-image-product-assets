import Foundation

enum AssetScanner {
    static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "avif"
    ]

    static func scan(rootURL: URL) throws -> AssetScanResult {
        let fileManager = FileManager.default
        let immediateChildren = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        )

        let rootImages = try immediateChildren.filter { url in
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey]
            )
            return values.isRegularFile == true
                && supportedExtensions.contains(url.pathExtension.lowercased())
        }

        if !rootImages.isEmpty {
            return AssetScanResult(
                mode: .singleSKU,
                items: try makeItems(urls: rootImages, rootURL: rootURL),
                productFolderCount: 1
            )
        }

        let productFolders = try immediateChildren
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                let name = url.lastPathComponent.lowercased()
                return values.isDirectory == true
                    && name != "webp"
                    && name != "model"
                    && name != "product"
                    && name != ProgressStore.stateDirectoryName.lowercased()
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                    == .orderedAscending
            }

        var imageURLs: [URL] = []

        for productFolder in productFolders {
            guard let enumerator = fileManager.enumerator(
                at: productFolder,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey
                ],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                let values = try url.resourceValues(
                    forKeys: [.isDirectoryKey, .isRegularFileKey]
                )

                if values.isDirectory == true {
                    let name = url.lastPathComponent.lowercased()
                    if name == "webp"
                        || name == "model"
                        || name == "product"
                        || name == ProgressStore.stateDirectoryName.lowercased()
                    {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard values.isRegularFile == true else { continue }
                guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                    continue
                }

                imageURLs.append(url)
            }
        }

        return AssetScanResult(
            mode: .library,
            items: try makeItems(urls: imageURLs, rootURL: rootURL),
            productFolderCount: productFolders.count
        )
    }

    private static func makeItems(
        urls: [URL],
        rootURL: URL
    ) throws -> [AssetItem] {
        struct RawAsset {
            let url: URL
            let relativePath: String
            let stem: String
            let ext: String
            let fileSize: Int64
            let modificationTime: TimeInterval
            let collisionKey: String
        }

        let rootPath = rootURL.standardizedFileURL.path
        var rawAssets: [RawAsset] = []

        for url in urls {
            let values = try url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ]
            )

            guard values.isRegularFile == true else { continue }

            let standardizedPath = url.standardizedFileURL.path
            guard standardizedPath.hasPrefix(rootPath + "/") else { continue }

            let relativePath = String(
                standardizedPath.dropFirst(rootPath.count + 1)
            )
            let stem = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.lowercased()
            let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
            let parentRelative: String

            if parentPath == rootPath {
                parentRelative = ""
            } else if parentPath.hasPrefix(rootPath + "/") {
                parentRelative = String(parentPath.dropFirst(rootPath.count + 1))
            } else {
                parentRelative = parentPath
            }

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
                $0.relativePath.localizedStandardCompare($1.relativePath)
                    == .orderedAscending
            }
    }
}
