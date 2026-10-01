import Foundation

struct DestinationAsset: Hashable, Sendable {
    let id: String
    let productFolderName: String
    let classification: AssetClassification
    let outputStem: String
    let outputURL: URL
    let outputRelativePath: String
    let modificationTime: TimeInterval
}

struct DestinationSnapshot: Sendable {
    let assets: [DestinationAsset]
    let productFolderNames: Set<String>
}

struct ComparisonSummary: Sendable {
    let sourceImageCount: Int
    let alreadyCurrentCount: Int
    let automaticRefreshCount: Int
    let manualClassificationCount: Int
    let destinationOnlyOutputCount: Int
    let mappedProductFolderCount: Int
    let newProductFolderCount: Int
}

struct ComparisonPlan: Sendable {
    let progress: ProgressDocument
    let productFolderMap: [String: String]
    let summary: ComparisonSummary
}

enum DestinationScanner {
    static func scan(rootURL: URL) throws -> DestinationSnapshot {
        let fileManager = FileManager.default
        let rootPath = rootURL.standardizedFileURL.path
        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var assets: [DestinationAsset] = []
        var productFolderNames = Set<String>()

        for productFolder in children {
            let values = try productFolder.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            guard productFolder.lastPathComponent.lowercased()
                != ProgressStore.stateDirectoryName.lowercased()
            else {
                continue
            }

            let productName = productFolder.lastPathComponent
            let webpFolder = productFolder.appendingPathComponent("webp", isDirectory: true)
            guard fileManager.fileExists(atPath: webpFolder.path) else { continue }

            productFolderNames.insert(productName)

            for classification in AssetClassification.allCases {
                let classificationFolder = webpFolder.appendingPathComponent(
                    classification.outputFolderName,
                    isDirectory: true
                )

                guard fileManager.fileExists(atPath: classificationFolder.path) else {
                    continue
                }

                let files = try fileManager.contentsOfDirectory(
                    at: classificationFolder,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .contentModificationDateKey
                    ],
                    options: [.skipsHiddenFiles]
                )

                for file in files {
                    let fileValues = try file.resourceValues(
                        forKeys: [.isRegularFileKey, .contentModificationDateKey]
                    )

                    guard fileValues.isRegularFile == true,
                          file.pathExtension.lowercased() == "webp"
                    else {
                        continue
                    }

                    let outputPath = file.standardizedFileURL.path
                    guard outputPath.hasPrefix(rootPath + "/") else { continue }

                    let relativePath = String(
                        outputPath.dropFirst(rootPath.count + 1)
                    )
                    let outputStem = file.deletingPathExtension().lastPathComponent
                    let id = [
                        productName,
                        classification.rawValue,
                        file.lastPathComponent
                    ].joined(separator: "/")

                    assets.append(
                        DestinationAsset(
                            id: id,
                            productFolderName: productName,
                            classification: classification,
                            outputStem: outputStem,
                            outputURL: file,
                            outputRelativePath: relativePath,
                            modificationTime: fileValues.contentModificationDate?
                                .timeIntervalSince1970 ?? 0
                        )
                    )
                }
            }
        }

        return DestinationSnapshot(
            assets: assets.sorted {
                $0.id.localizedStandardCompare($1.id) == .orderedAscending
            },
            productFolderNames: productFolderNames
        )
    }
}

enum ComparisonPlanner {
    static func makePlan(
        items: [AssetItem],
        sourceScanMode: AssetScanMode,
        sourceRootFolderName: String,
        destinationRootFolderName: String,
        destination: DestinationSnapshot,
        storedProgress: ProgressDocument
    ) -> ComparisonPlan {
        let sourceProductGroups = Dictionary(grouping: items) { item in
            sourceProductFolderName(
                for: item,
                sourceScanMode: sourceScanMode,
                sourceRootFolderName: sourceRootFolderName
            )
        }
        let productFolderMap = makeProductFolderMap(
            sourceProductGroups: sourceProductGroups,
            destination: destination
        )

        let destinationByRelativePath = Dictionary(
            uniqueKeysWithValues: destination.assets.map {
                ($0.outputRelativePath, $0)
            }
        )
        let destinationByStem = Dictionary(
            grouping: destination.assets,
            by: \.outputStem
        )
        let destinationByProduct = Dictionary(
            grouping: destination.assets,
            by: \.productFolderName
        )

        var document = ProgressDocument(
            rootFolderName: destinationRootFolderName
        )
        document.version = 2
        document.sourceRootFolderName = sourceRootFolderName

        var claimedDestinationIDs = Set<String>()
        var automaticRefreshCount = 0
        var alreadyCurrentCount = 0

        let canReuseStoredProgress =
            storedProgress.sourceRootFolderName == sourceRootFolderName

        if canReuseStoredProgress {
            for item in items {
                guard var record = storedProgress.records[item.relativePath] else {
                    continue
                }

                let sourceProduct = sourceProductFolderName(
                    for: item,
                    sourceScanMode: sourceScanMode,
                    sourceRootFolderName: sourceRootFolderName
                )
                let destinationProduct = record.destinationProductFolderName
                    ?? productFolderMap[sourceProduct]
                    ?? sourceProduct
                let outputStem = record.outputStemOverride ?? item.outputStem
                let expectedRelativePath = outputRelativePath(
                    productFolderName: destinationProduct,
                    classification: record.classification,
                    outputStem: outputStem
                )

                let existingOutput: DestinationAsset? = {
                    if let saved = record.outputRelativePath,
                       let asset = destinationByRelativePath[saved]
                    {
                        return asset
                    }

                    return destinationByRelativePath[expectedRelativePath]
                }()

                if let existingOutput {
                    claimedDestinationIDs.insert(existingOutput.id)
                    record.destinationProductFolderName =
                        existingOutput.productFolderName
                    record.outputStemOverride =
                        existingOutput.outputStem == item.outputStem
                        ? nil
                        : existingOutput.outputStem
                } else {
                    record.destinationProductFolderName = destinationProduct
                    record.outputStemOverride =
                        outputStem == item.outputStem ? nil : outputStem
                }

                let sourceChanged =
                    record.fileSize != item.fileSize ||
                    abs(record.modificationTime - item.modificationTime) > 0.5
                let outputMissing = existingOutput == nil

                record.relativePath = item.relativePath
                record.fileSize = item.fileSize
                record.modificationTime = item.modificationTime
                record.updatedAt = Date()

                if sourceChanged || outputMissing || record.status != .completed {
                    record.status = .pending
                    record.outputRelativePath = nil
                    record.error = nil
                    record.revision = UUID().uuidString
                    automaticRefreshCount += 1
                } else {
                    record.status = .completed
                    record.outputRelativePath = existingOutput?.outputRelativePath
                    record.error = nil
                    alreadyCurrentCount += 1
                }

                document.records[item.relativePath] = record
            }
        }

        let unresolvedItems = items.filter {
            document.records[$0.relativePath] == nil
        }
        var exactMatches: [String: DestinationAsset] = [:]

        for item in unresolvedItems {
            let sourceProduct = sourceProductFolderName(
                for: item,
                sourceScanMode: sourceScanMode,
                sourceRootFolderName: sourceRootFolderName
            )
            let mappedProduct = productFolderMap[sourceProduct]
            let stemCandidates = (destinationByStem[item.outputStem] ?? [])
                .filter { !claimedDestinationIDs.contains($0.id) }
            let preferredCandidates = stemCandidates.filter {
                $0.productFolderName == mappedProduct
            }

            let match: DestinationAsset?
            if preferredCandidates.count == 1 {
                match = preferredCandidates[0]
            } else if preferredCandidates.isEmpty && stemCandidates.count == 1 {
                match = stemCandidates[0]
            } else {
                match = nil
            }

            if let match {
                exactMatches[item.relativePath] = match
                claimedDestinationIDs.insert(match.id)
            }
        }

        var aliasMatches: [String: DestinationAsset] = [:]

        for item in unresolvedItems where exactMatches[item.relativePath] == nil {
            let sourceProduct = sourceProductFolderName(
                for: item,
                sourceScanMode: sourceScanMode,
                sourceRootFolderName: sourceRootFolderName
            )
            guard let mappedProduct = productFolderMap[sourceProduct],
                  mappedProduct != sourceProduct
                    || destination.productFolderNames.contains(mappedProduct)
            else {
                continue
            }

            let descriptor = assetDescriptor(
                stem: item.outputStem,
                productFolderName: sourceProduct
            )
            guard !descriptor.isEmpty else { continue }

            let candidates = (destinationByProduct[mappedProduct] ?? [])
                .filter { asset in
                    !claimedDestinationIDs.contains(asset.id)
                        && assetDescriptor(
                            stem: asset.outputStem,
                            productFolderName: mappedProduct
                        ) == descriptor
                }

            guard candidates.count == 1, let match = candidates.first else {
                continue
            }

            aliasMatches[item.relativePath] = match
            claimedDestinationIDs.insert(match.id)
        }

        for item in unresolvedItems {
            let match =
                exactMatches[item.relativePath]
                ?? aliasMatches[item.relativePath]
            guard let match else { continue }

            let isAlias = aliasMatches[item.relativePath] != nil
            let sourceIsNewer =
                item.modificationTime > match.modificationTime + 1.0
            let needsRefresh = isAlias || sourceIsNewer

            document.records[item.relativePath] = AssetProgressRecord(
                relativePath: item.relativePath,
                classification: match.classification,
                status: needsRefresh ? .pending : .completed,
                revision: UUID().uuidString,
                outputRelativePath: needsRefresh
                    ? nil
                    : match.outputRelativePath,
                error: nil,
                fileSize: item.fileSize,
                modificationTime: item.modificationTime,
                updatedAt: Date(),
                destinationProductFolderName: match.productFolderName,
                outputStemOverride: match.outputStem == item.outputStem
                    ? nil
                    : match.outputStem
            )

            if needsRefresh {
                automaticRefreshCount += 1
            } else {
                alreadyCurrentCount += 1
            }
        }

        let manualClassificationCount =
            items.count - document.records.count
        let mappedProductFolderCount = productFolderMap.reduce(
            into: 0
        ) { count, pair in
            if pair.key != pair.value {
                count += 1
            }
        }
        let newProductFolderCount = sourceProductGroups.keys.reduce(
            into: 0
        ) { count, sourceProduct in
            let target = productFolderMap[sourceProduct] ?? sourceProduct
            if !destination.productFolderNames.contains(target) {
                count += 1
            }
        }

        return ComparisonPlan(
            progress: document,
            productFolderMap: sourceProductGroups.keys.reduce(
                into: [:]
            ) { map, sourceProduct in
                map[sourceProduct] =
                    productFolderMap[sourceProduct] ?? sourceProduct
            },
            summary: ComparisonSummary(
                sourceImageCount: items.count,
                alreadyCurrentCount: alreadyCurrentCount,
                automaticRefreshCount: automaticRefreshCount,
                manualClassificationCount: manualClassificationCount,
                destinationOnlyOutputCount: max(
                    destination.assets.count - claimedDestinationIDs.count,
                    0
                ),
                mappedProductFolderCount: mappedProductFolderCount,
                newProductFolderCount: newProductFolderCount
            )
        )
    }

    static func sourceProductFolderName(
        for item: AssetItem,
        sourceScanMode: AssetScanMode,
        sourceRootFolderName: String
    ) -> String {
        if sourceScanMode == .singleSKU {
            return sourceRootFolderName
        }

        return item.relativePath
            .split(separator: "/", maxSplits: 1)
            .first
            .map(String.init)
            ?? item.productFolderName
    }

    static func outputRelativePath(
        productFolderName: String,
        classification: AssetClassification,
        outputStem: String
    ) -> String {
        [
            productFolderName,
            "webp",
            classification.outputFolderName,
            outputStem + ".webp"
        ].joined(separator: "/")
    }

    private static func makeProductFolderMap(
        sourceProductGroups: [String: [AssetItem]],
        destination: DestinationSnapshot
    ) -> [String: String] {
        let destinationByProduct = Dictionary(
            grouping: destination.assets,
            by: \.productFolderName
        )
        let destinationStemSets = destinationByProduct.mapValues {
            Set($0.map(\.outputStem))
        }
        let destinationDescriptorSets = destinationByProduct.mapValues {
            assets in
            Set(
                assets.map {
                    assetDescriptor(
                        stem: $0.outputStem,
                        productFolderName: $0.productFolderName
                    )
                }.filter { !$0.isEmpty }
            )
        }

        var result: [String: String] = [:]

        for (sourceProduct, items) in sourceProductGroups {
            if destination.productFolderNames.contains(sourceProduct) {
                result[sourceProduct] = sourceProduct
                continue
            }

            let sourceStems = Set(items.map(\.outputStem))
            let exactOverlapCandidates = destinationStemSets.compactMap {
                product, stems -> (Int, String)? in
                let overlap = sourceStems.intersection(stems).count
                return overlap > 0 ? (overlap, product) : nil
            }.sorted {
                if $0.0 != $1.0 {
                    return $0.0 > $1.0
                }
                return $0.1 < $1.1
            }

            if let best = exactOverlapCandidates.first,
               exactOverlapCandidates.count == 1
                    || best.0 > exactOverlapCandidates[1].0
            {
                result[sourceProduct] = best.1
                continue
            }

            let sourceDescriptors = Set(
                items.map {
                    assetDescriptor(
                        stem: $0.outputStem,
                        productFolderName: sourceProduct
                    )
                }.filter { !$0.isEmpty }
            )
            let sourceTokens = normalizedTokens(sourceProduct)
            let sourceSKU = sourceTokens.first ?? ""
            let sourceNameTokens = Array(sourceTokens.dropFirst())

            let descriptorCandidates = destinationDescriptorSets
                .compactMap {
                    product, descriptors -> (Double, String)? in
                    let overlap =
                        sourceDescriptors.intersection(descriptors).count
                    let denominator = max(
                        1,
                        min(
                            sourceDescriptors.count,
                            descriptors.count
                        )
                    )
                    let overlapRatio =
                        Double(overlap) / Double(denominator)

                    guard overlap >= 4, overlapRatio >= 0.8 else {
                        return nil
                    }

                    let destinationTokens = normalizedTokens(product)
                    let destinationSKU = destinationTokens.first ?? ""
                    let destinationNameTokens = Array(
                        destinationTokens.dropFirst()
                    )
                    let nameSimilarity = jaccardSimilarity(
                        sourceNameTokens,
                        destinationNameTokens
                    )

                    let sameSKUFamily =
                        skuFamily(sourceSKU)
                        == skuFamily(destinationSKU)
                    let sameNumericSKU =
                        !numericPart(sourceSKU).isEmpty
                        && numericPart(sourceSKU)
                            == numericPart(destinationSKU)
                        && nameSimilarity >= 0.9

                    guard nameSimilarity >= 0.6,
                          sameSKUFamily || sameNumericSKU
                    else {
                        return nil
                    }

                    return (
                        overlapRatio + (nameSimilarity * 0.2),
                        product
                    )
                }.sorted {
                    if abs($0.0 - $1.0) > 0.0001 {
                        return $0.0 > $1.0
                    }
                    return $0.1 < $1.1
                }

            if let best = descriptorCandidates.first,
               descriptorCandidates.count == 1
                    || best.0 > descriptorCandidates[1].0 + 0.05
            {
                result[sourceProduct] = best.1
            }
        }

        return result
    }

    private static func assetDescriptor(
        stem: String,
        productFolderName: String
    ) -> [String] {
        let stemTokens = normalizedTokens(stem)
        let folderTokens = normalizedTokens(productFolderName)
        var prefixCount = 0

        while prefixCount < min(
            stemTokens.count,
            folderTokens.count
        ), stemTokens[prefixCount] == folderTokens[prefixCount] {
            prefixCount += 1
        }

        guard prefixCount > 0 else { return stemTokens }
        return Array(stemTokens.dropFirst(prefixCount))
    }

    private static func normalizedTokens(
        _ value: String
    ) -> [String] {
        let folded = value.folding(
            options: [
                .diacriticInsensitive,
                .widthInsensitive,
                .caseInsensitive
            ],
            locale: Locale(identifier: "en_US_POSIX")
        ).uppercased()

        let rawTokens = folded.components(
            separatedBy: CharacterSet.alphanumerics.inverted
        ).filter { !$0.isEmpty }

        var tokens: [String] = []

        for raw in rawTokens {
            let token: String
            switch raw {
            case "WOMENS", "WOMAN", "LADIES", "LADY":
                token = "WOMEN"
            case "MENS", "MAN":
                token = "MEN"
            default:
                token = raw
            }

            if token == "S",
               let previous = tokens.last,
               previous == "WOMEN" || previous == "MEN"
            {
                continue
            }

            tokens.append(token)
        }

        return tokens
    }

    private static func jaccardSimilarity(
        _ lhs: [String],
        _ rhs: [String]
    ) -> Double {
        let left = Set(lhs)
        let right = Set(rhs)
        let union = left.union(right)

        guard !union.isEmpty else { return 1 }

        return Double(
            left.intersection(right).count
        ) / Double(union.count)
    }

    private static func skuFamily(
        _ token: String
    ) -> String {
        var result = ""
        var sawDigit = false

        for character in token {
            if character.isNumber {
                sawDigit = true
                result.append(character)
            } else if !sawDigit {
                result.append(character)
            } else {
                break
            }
        }

        return result.isEmpty ? token : result
    }

    private static func numericPart(
        _ token: String
    ) -> String {
        String(token.filter(\.isNumber))
    }
}
