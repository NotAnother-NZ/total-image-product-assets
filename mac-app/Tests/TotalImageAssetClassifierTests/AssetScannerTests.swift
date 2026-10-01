import Foundation
import XCTest
@testable import TotalImageAssetClassifier

final class AssetScannerTests: XCTestCase {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TotalImageAssetClassifierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func makeFile(_ url: URL) throws {
        let created = FileManager.default.createFile(
            atPath: url.path,
            contents: Data("test".utf8)
        )
        XCTAssertTrue(created, "Failed to create test file at \(url.path)")
    }

    func testLibraryModeScansSKUFilesButIgnoresGeneratedOutputs() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let skuA = root.appendingPathComponent("J510M_UNISEX_CHARGER_JACKET", isDirectory: true)
        let skuB = root.appendingPathComponent("1061_FRESHEN_POLO_MENS", isDirectory: true)
        try FileManager.default.createDirectory(at: skuA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skuB, withIntermediateDirectories: true)

        try makeFile(skuA.appendingPathComponent("J510M_FRONT.jpg"))
        try makeFile(skuB.appendingPathComponent("1061_FRONT.png"))

        let generated = skuA
            .appendingPathComponent("webp", isDirectory: true)
            .appendingPathComponent("product", isDirectory: true)
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        try makeFile(generated.appendingPathComponent("J510M_FRONT.webp"))

        let result = try AssetScanner.scan(rootURL: root)

        XCTAssertEqual(result.mode, .library)
        XCTAssertEqual(result.productFolderCount, 2)
        XCTAssertEqual(
            result.items.map(\.relativePath),
            [
                "1061_FRESHEN_POLO_MENS/1061_FRONT.png",
                "J510M_UNISEX_CHARGER_JACKET/J510M_FRONT.jpg"
            ]
        )
    }

    func testSingleSKUModeOnlyScansRootImages() throws {
        let sku = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sku) }

        try makeFile(sku.appendingPathComponent("J510M_UNISEX_CHARGER_JACKET_BLACK_ROYAL_GREY_FRONT.jpg"))
        try makeFile(sku.appendingPathComponent("J510M_UNISEX_CHARGER_JACKET_BLACK_ROYAL_GREY_BACK.jpg"))

        let model = sku
            .appendingPathComponent("webp", isDirectory: true)
            .appendingPathComponent("model", isDirectory: true)
        let product = sku
            .appendingPathComponent("webp", isDirectory: true)
            .appendingPathComponent("product", isDirectory: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: product, withIntermediateDirectories: true)
        try makeFile(model.appendingPathComponent("OLD_MODEL.webp"))
        try makeFile(product.appendingPathComponent("OLD_PRODUCT.webp"))

        let result = try AssetScanner.scan(rootURL: sku)

        XCTAssertEqual(result.mode, .singleSKU)
        XCTAssertEqual(result.productFolderCount, 1)
        XCTAssertEqual(
            Set(result.items.map(\.relativePath)),
            Set([
                "J510M_UNISEX_CHARGER_JACKET_BLACK_ROYAL_GREY_FRONT.jpg",
                "J510M_UNISEX_CHARGER_JACKET_BLACK_ROYAL_GREY_BACK.jpg"
            ])
        )
    }

    func testSingleSKUModeKeepsSameStemDifferentExtensionsDistinct() throws {
        let sku = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sku) }

        try makeFile(sku.appendingPathComponent("SAME.jpg"))
        try makeFile(sku.appendingPathComponent("SAME.png"))

        let result = try AssetScanner.scan(rootURL: sku)
        let stems = Set(result.items.map(\.outputStem))

        XCTAssertEqual(result.mode, .singleSKU)
        XCTAssertEqual(stems, Set(["SAME__jpg", "SAME__png"]))
    }
}
