import Foundation
import XCTest
@testable import TotalImageAssetClassifier

final class ComparisonPlannerTests: XCTestCase {
    private func makeItem(
        _ relativePath: String,
        outputStem: String? = nil,
        fileSize: Int64 = 100,
        modificationTime: TimeInterval = 100
    ) -> AssetItem {
        let url = URL(fileURLWithPath: "/source")
            .appendingPathComponent(relativePath)

        return AssetItem(
            id: relativePath,
            sourceURL: url,
            relativePath: relativePath,
            outputStem: outputStem
                ?? url.deletingPathExtension().lastPathComponent,
            fileSize: fileSize,
            modificationTime: modificationTime
        )
    }

    private func destinationAsset(
        product: String,
        classification: AssetClassification,
        stem: String,
        modificationTime: TimeInterval = 200
    ) -> DestinationAsset {
        let relative = [
            product,
            "webp",
            classification.outputFolderName,
            stem + ".webp"
        ].joined(separator: "/")

        return DestinationAsset(
            id: [
                product,
                classification.rawValue,
                stem + ".webp"
            ].joined(separator: "/"),
            productFolderName: product,
            classification: classification,
            outputStem: stem,
            outputURL: URL(fileURLWithPath: "/destination")
                .appendingPathComponent(relative),
            outputRelativePath: relative,
            modificationTime: modificationTime
        )
    }

    private func snapshot(
        _ assets: [DestinationAsset]
    ) -> DestinationSnapshot {
        DestinationSnapshot(
            assets: assets,
            productFolderNames: Set(
                assets.map(\.productFolderName)
            )
        )
    }

    func testExactExistingOutputIsSkippedAndNewImageRemainsManual() {
        let existing = makeItem(
            "SKU_A/SKU_A_BLACK_FRONT.jpg"
        )
        let new = makeItem(
            "SKU_A/SKU_A_NAVY_FRONT.jpg"
        )
        let destination = snapshot([
            destinationAsset(
                product: "SKU_A",
                classification: .product,
                stem: "SKU_A_BLACK_FRONT"
            )
        ])

        let plan = ComparisonPlanner.makePlan(
            items: [existing, new],
            sourceScanMode: .library,
            sourceRootFolderName: "ALL_PRODUCT_ASSETS",
            destinationRootFolderName: "assets",
            destination: destination,
            storedProgress: ProgressDocument(
                rootFolderName: "assets"
            )
        )

        XCTAssertEqual(
            plan.progress.records[existing.relativePath]?.status,
            .completed
        )
        XCTAssertEqual(
            plan.progress.records[existing.relativePath]?.classification,
            .product
        )
        XCTAssertNil(plan.progress.records[new.relativePath])
        XCTAssertEqual(plan.summary.alreadyCurrentCount, 1)
        XCTAssertEqual(plan.summary.automaticRefreshCount, 0)
        XCTAssertEqual(plan.summary.manualClassificationCount, 1)
    }

    func testRenamedFolderAndPrefixReuseExistingClassifications() {
        let sourceProduct = "AS1130_ACCESS_CAP"
        let destinationProduct = "1130_ACCESS_CAP"
        let descriptors = [
            ("BLACK_HERO_FRONT", AssetClassification.model),
            ("BLACK_HERO_SIDE", AssetClassification.model),
            ("BONE_FRONT", AssetClassification.product),
            ("BONE_SIDE", AssetClassification.product)
        ]

        let items = descriptors.map { suffix, _ in
            makeItem(
                "\(sourceProduct)/\(sourceProduct)_\(suffix).png"
            )
        }
        let outputs = descriptors.map { suffix, classification in
            destinationAsset(
                product: destinationProduct,
                classification: classification,
                stem: "\(destinationProduct)_\(suffix)"
            )
        }

        let plan = ComparisonPlanner.makePlan(
            items: items,
            sourceScanMode: .library,
            sourceRootFolderName: "ALL_PRODUCT_ASSETS",
            destinationRootFolderName: "assets",
            destination: snapshot(outputs),
            storedProgress: ProgressDocument(
                rootFolderName: "assets"
            )
        )

        XCTAssertEqual(
            plan.productFolderMap[sourceProduct],
            destinationProduct
        )
        XCTAssertEqual(plan.summary.mappedProductFolderCount, 1)
        XCTAssertEqual(plan.summary.manualClassificationCount, 0)
        XCTAssertEqual(plan.summary.automaticRefreshCount, 4)

        for (item, descriptor) in zip(items, descriptors) {
            let record = plan.progress.records[item.relativePath]
            XCTAssertEqual(record?.status, .pending)
            XCTAssertEqual(record?.classification, descriptor.1)
            XCTAssertEqual(
                record?.destinationProductFolderName,
                destinationProduct
            )
            XCTAssertEqual(
                record?.outputStemOverride,
                "\(destinationProduct)_\(descriptor.0)"
            )
        }
    }

    func testNewSimilarAssetDoesNotStealOutputClaimedByExactSource() {
        let sourceProduct =
            "10722_Siena_Womens_Bandless_Elastic_Waist_Pant"
        let destinationProduct =
            "10722_WOMEN'S_BANDLESS_ELASTIC_WAIST_PANT"

        let exact = makeItem(
            "\(sourceProduct)/\(destinationProduct)_BLACK_BACK.jpg"
        )
        let newSimilar = makeItem(
            "\(sourceProduct)/\(sourceProduct)_BLACK_BACK.jpg"
        )
        let output = destinationAsset(
            product: destinationProduct,
            classification: .product,
            stem: "\(destinationProduct)_BLACK_BACK"
        )

        let plan = ComparisonPlanner.makePlan(
            items: [exact, newSimilar],
            sourceScanMode: .library,
            sourceRootFolderName: "ALL_PRODUCT_ASSETS",
            destinationRootFolderName: "assets",
            destination: snapshot([output]),
            storedProgress: ProgressDocument(
                rootFolderName: "assets"
            )
        )

        XCTAssertEqual(
            plan.productFolderMap[sourceProduct],
            destinationProduct
        )
        XCTAssertEqual(
            plan.progress.records[exact.relativePath]?.status,
            .completed
        )
        XCTAssertNil(
            plan.progress.records[newSimilar.relativePath]
        )
        XCTAssertEqual(plan.summary.manualClassificationCount, 1)
    }

    func testChangedSourceRefreshesUsingSavedDestinationTarget() {
        let item = makeItem(
            "AS1130_ACCESS_CAP/AS1130_ACCESS_CAP_BLACK_SIDE.jpg",
            fileSize: 222,
            modificationTime: 300
        )
        let output = destinationAsset(
            product: "1130_ACCESS_CAP",
            classification: .product,
            stem: "1130_ACCESS_CAP_BLACK_SIDE",
            modificationTime: 200
        )

        var stored = ProgressDocument(
            rootFolderName: "assets",
            sourceRootFolderName: "ALL_PRODUCT_ASSETS"
        )
        stored.records[item.relativePath] = AssetProgressRecord(
            relativePath: item.relativePath,
            classification: .product,
            status: .completed,
            revision: "old",
            outputRelativePath: output.outputRelativePath,
            error: nil,
            fileSize: 111,
            modificationTime: 100,
            updatedAt: Date(timeIntervalSince1970: 100),
            destinationProductFolderName: "1130_ACCESS_CAP",
            outputStemOverride: "1130_ACCESS_CAP_BLACK_SIDE"
        )

        let plan = ComparisonPlanner.makePlan(
            items: [item],
            sourceScanMode: .library,
            sourceRootFolderName: "ALL_PRODUCT_ASSETS",
            destinationRootFolderName: "assets",
            destination: snapshot([output]),
            storedProgress: stored
        )

        let record = plan.progress.records[item.relativePath]
        XCTAssertEqual(record?.status, .pending)
        XCTAssertEqual(record?.classification, .product)
        XCTAssertEqual(
            record?.destinationProductFolderName,
            "1130_ACCESS_CAP"
        )
        XCTAssertEqual(
            record?.outputStemOverride,
            "1130_ACCESS_CAP_BLACK_SIDE"
        )
        XCTAssertNil(record?.outputRelativePath)
        XCTAssertEqual(plan.summary.automaticRefreshCount, 1)
        XCTAssertEqual(plan.summary.manualClassificationCount, 0)
    }

    func testDestinationOnlyOutputsArePreservedAndReported() {
        let item = makeItem(
            "SKU_A/SKU_A_BLACK_FRONT.jpg"
        )
        let current = destinationAsset(
            product: "SKU_A",
            classification: .product,
            stem: "SKU_A_BLACK_FRONT"
        )
        let stale = destinationAsset(
            product: "OLD_SKU",
            classification: .model,
            stem: "OLD_SKU_HERO_FRONT"
        )

        let plan = ComparisonPlanner.makePlan(
            items: [item],
            sourceScanMode: .library,
            sourceRootFolderName: "ALL_PRODUCT_ASSETS",
            destinationRootFolderName: "assets",
            destination: snapshot([current, stale]),
            storedProgress: ProgressDocument(
                rootFolderName: "assets"
            )
        )

        XCTAssertEqual(plan.summary.destinationOnlyOutputCount, 1)
        XCTAssertEqual(plan.summary.manualClassificationCount, 0)
    }
}
