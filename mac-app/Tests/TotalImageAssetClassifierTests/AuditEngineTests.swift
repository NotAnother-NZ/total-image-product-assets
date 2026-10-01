import Foundation
import XCTest
@testable import TotalImageAssetClassifier

final class AuditEngineTests: XCTestCase {
    private func makeTemporaryDirectory(
        _ name: String
    ) throws -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func makeFile(
        _ url: URL,
        contents: String
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    private func sourceFile(
        root: URL,
        product: String,
        name: String,
        contents: String = "source"
    ) throws -> URL {
        let url = root
            .appendingPathComponent(
                product,
                isDirectory: true
            )
            .appendingPathComponent(name)
        try makeFile(url, contents: contents)
        return url
    }

    private func destinationFile(
        root: URL,
        product: String,
        classification: AssetClassification,
        name: String,
        contents: String
    ) throws -> URL {
        let url = root
            .appendingPathComponent(
                product,
                isDirectory: true
            )
            .appendingPathComponent(
                "webp",
                isDirectory: true
            )
            .appendingPathComponent(
                classification.outputFolderName,
                isDirectory: true
            )
            .appendingPathComponent(name)
        try makeFile(url, contents: contents)
        return url
    }

    private func saveProgress(
        destination: URL,
        records: [String: AssetProgressRecord]
    ) throws {
        try ProgressStore.save(
            ProgressDocument(
                rootFolderName:
                    destination.lastPathComponent,
                sourceRootFolderName:
                    "ALL_PRODUCT_ASSETS",
                records: records
            ),
            rootURL: destination
        )
    }

    private func record(
        sourcePath: String,
        outputPath: String
    ) -> AssetProgressRecord {
        AssetProgressRecord(
            relativePath: sourcePath,
            classification: .product,
            status: .completed,
            revision: "test",
            outputRelativePath: outputPath,
            error: nil,
            fileSize: 1,
            modificationTime: 1,
            updatedAt:
                Date(timeIntervalSince1970: 1)
        )
    }

    func testAuditFindsDestinationOnlyOutput() throws {
        let source = try makeTemporaryDirectory(
            "AuditSource"
        )
        let destination =
            try makeTemporaryDirectory(
                "AuditDestination"
            )
        defer {
            try? FileManager.default
                .removeItem(at: source)
            try? FileManager.default
                .removeItem(at: destination)
        }

        try sourceFile(
            root: source,
            product: "SKU_A",
            name: "SKU_A_BLACK_FRONT.jpg"
        )

        try destinationFile(
            root: destination,
            product: "SKU_A",
            classification: .product,
            name: "SKU_A_BLACK_FRONT.webp",
            contents: "current"
        )
        try destinationFile(
            root: destination,
            product: "SKU_A",
            classification: .product,
            name: "OLD_SKU_A_BLACK_FRONT.webp",
            contents: "legacy-output"
        )

        let sourcePath =
            "SKU_A/SKU_A_BLACK_FRONT.jpg"
        let outputPath =
            "SKU_A/webp/product/SKU_A_BLACK_FRONT.webp"

        try saveProgress(
            destination: destination,
            records: [
                sourcePath:
                    record(
                        sourcePath: sourcePath,
                        outputPath: outputPath
                    )
            ]
        )

        let result = try AssetAuditEngine.scan(
            sourceURL: source,
            destinationURL: destination,
            excelURL: nil,
            magickPath: nil
        )

        XCTAssertEqual(
            result.summary.totalDestinationAssets,
            2
        )
        XCTAssertEqual(
            result.summary.sourceBackedOutputs,
            1
        )
        XCTAssertEqual(
            result.summary.destinationOnlyCount,
            1
        )

        let issue = try XCTUnwrap(
            result.issues.first {
                $0.kind == .destinationOnly
            }
        )
        XCTAssertEqual(
            issue.primaryRelativePath,
            "SKU_A/webp/product/OLD_SKU_A_BLACK_FRONT.webp"
        )
        XCTAssertFalse(
            issue.primarySourceBacked
        )
    }

    func testAuditProtectsActiveExactPixelDuplicates()
        throws
    {
        let source = try makeTemporaryDirectory(
            "AuditSource"
        )
        let destination =
            try makeTemporaryDirectory(
                "AuditDestination"
            )
        defer {
            try? FileManager.default
                .removeItem(at: source)
            try? FileManager.default
                .removeItem(at: destination)
        }

        try sourceFile(
            root: source,
            product: "SKU_A",
            name: "SKU_A_BLACK_FRONT.jpg",
            contents: "source-a"
        )
        try sourceFile(
            root: source,
            product: "SKU_A",
            name: "SKU_A_NAVY_FRONT.jpg",
            contents: "source-b"
        )

        try destinationFile(
            root: destination,
            product: "SKU_A",
            classification: .product,
            name: "SKU_A_BLACK_FRONT.webp",
            contents: "identical-webp"
        )
        try destinationFile(
            root: destination,
            product: "SKU_A",
            classification: .product,
            name: "SKU_A_NAVY_FRONT.webp",
            contents: "identical-webp"
        )

        let blackSource =
            "SKU_A/SKU_A_BLACK_FRONT.jpg"
        let navySource =
            "SKU_A/SKU_A_NAVY_FRONT.jpg"
        let blackOutput =
            "SKU_A/webp/product/SKU_A_BLACK_FRONT.webp"
        let navyOutput =
            "SKU_A/webp/product/SKU_A_NAVY_FRONT.webp"

        try saveProgress(
            destination: destination,
            records: [
                blackSource:
                    record(
                        sourcePath: blackSource,
                        outputPath: blackOutput
                    ),
                navySource:
                    record(
                        sourcePath: navySource,
                        outputPath: navyOutput
                    )
            ]
        )

        let result = try AssetAuditEngine.scan(
            sourceURL: source,
            destinationURL: destination,
            excelURL: nil,
            magickPath: nil
        )

        XCTAssertEqual(
            result.summary.destinationOnlyCount,
            0
        )
        XCTAssertEqual(
            result.summary.duplicateIssueCount,
            1
        )

        let issue = try XCTUnwrap(
            result.issues.first {
                $0.kind == .pixelDuplicate
            }
        )
        XCTAssertTrue(
            issue.primarySourceBacked
        )
        XCTAssertEqual(
            issue.relatedSourceBacked,
            [true]
        )
    }

    func testOrphanExactDuplicatePointsToActiveKeeper()
        throws
    {
        let source = try makeTemporaryDirectory(
            "AuditSource"
        )
        let destination =
            try makeTemporaryDirectory(
                "AuditDestination"
            )
        defer {
            try? FileManager.default
                .removeItem(at: source)
            try? FileManager.default
                .removeItem(at: destination)
        }

        try sourceFile(
            root: source,
            product: "SKU_A",
            name: "SKU_A_BLACK_FRONT.jpg"
        )

        try destinationFile(
            root: destination,
            product: "SKU_A",
            classification: .product,
            name: "SKU_A_BLACK_FRONT.webp",
            contents: "same"
        )
        try destinationFile(
            root: destination,
            product: "SKU_A",
            classification: .product,
            name: "OLD_BLACK_FRONT.webp",
            contents: "same"
        )

        let sourcePath =
            "SKU_A/SKU_A_BLACK_FRONT.jpg"
        let outputPath =
            "SKU_A/webp/product/SKU_A_BLACK_FRONT.webp"

        try saveProgress(
            destination: destination,
            records: [
                sourcePath:
                    record(
                        sourcePath: sourcePath,
                        outputPath: outputPath
                    )
            ]
        )

        let result = try AssetAuditEngine.scan(
            sourceURL: source,
            destinationURL: destination,
            excelURL: nil,
            magickPath: nil
        )

        let issue = try XCTUnwrap(
            result.issues.first {
                $0.kind == .destinationOnly
            }
        )

        XCTAssertEqual(
            issue.relatedRelativePaths,
            [outputPath]
        )
        XCTAssertTrue(
            issue.detail.contains(
                "pixel-identical"
            )
        )
    }

    func testRenameValidationRejectsTypoAndCollision()
        throws
    {
        let destination =
            try makeTemporaryDirectory(
                "AuditDestination"
            )
        let source = try makeTemporaryDirectory(
            "AuditSource"
        )
        defer {
            try? FileManager.default
                .removeItem(at: source)
            try? FileManager.default
                .removeItem(at: destination)
        }

        let original = try destinationFile(
            root: destination,
            product: "SKU_A",
            classification: .model,
            name:
                "SKU_A_NAVY_HERO_FRRONT.webp",
            contents: "a"
        )
        _ = try destinationFile(
            root: destination,
            product: "SKU_A",
            classification: .model,
            name:
                "SKU_A_NAVY_HERO_FRONT.webp",
            contents: "b"
        )

        let relative =
            "SKU_A/webp/model/\(original.lastPathComponent)"
        let issue = AuditIssue(
            id: "naming:\(relative)",
            kind: .namingWarning,
            primaryRelativePath: relative,
            relatedRelativePaths: [],
            sourceRelativePath: nil,
            title: original.lastPathComponent,
            detail: "test",
            primarySourceBacked: false,
            relatedSourceBacked: [],
            suggestedFileName:
                "SKU_A_NAVY_HERO_FRONT.webp"
        )

        let scan = AuditScanResult(
            issues: [issue],
            summary: AuditSummary(
                totalDestinationAssets: 2,
                sourceBackedOutputs: 0,
                destinationOnlyCount: 1,
                duplicateIssueCount: 0,
                namingWarningCount: 1,
                missingOutputCount: 0
            ),
            sourceRootURL: source,
            destinationRootURL: destination,
            excelURL: nil,
            sourceItemsByRelativePath: [:],
            destinationAssetsByRelativePath: [:],
            progress:
                ProgressDocument(
                    rootFolderName: "assets"
                ),
            excelCatalog: nil
        )

        let typo = AssetAuditEngine
            .validateRename(
                proposedFileName:
                    original.lastPathComponent,
                issue: issue,
                scan: scan
            )
        XCTAssertFalse(typo.isValid)
        XCTAssertEqual(
            typo.suggestedFileName,
            "SKU_A_NAVY_HERO_FRONT.webp"
        )

        let collision = AssetAuditEngine
            .validateRename(
                proposedFileName:
                    "SKU_A_NAVY_HERO_FRONT.webp",
                issue: issue,
                scan: scan
            )
        XCTAssertFalse(collision.isValid)
        XCTAssertTrue(
            collision.message.contains(
                "already exists"
            )
        )
    }

    func testApplyRefusesDeleteOfActiveOutput()
        throws
    {
        let source = URL(
            fileURLWithPath: "/source"
        )
        let destination = URL(
            fileURLWithPath: "/destination"
        )
        let path =
            "SKU_A/webp/product/SKU_A_BLACK_FRONT.webp"

        let issue = AuditIssue(
            id: "duplicate:test",
            kind: .pixelDuplicate,
            primaryRelativePath: path,
            relatedRelativePaths: [],
            sourceRelativePath:
                "SKU_A/SKU_A_BLACK_FRONT.jpg",
            title:
                "SKU_A_BLACK_FRONT.webp",
            detail: "test",
            primarySourceBacked: true,
            relatedSourceBacked: [],
            suggestedFileName: nil
        )

        let scan = AuditScanResult(
            issues: [issue],
            summary: AuditSummary(
                totalDestinationAssets: 1,
                sourceBackedOutputs: 1,
                destinationOnlyCount: 0,
                duplicateIssueCount: 1,
                namingWarningCount: 0,
                missingOutputCount: 0
            ),
            sourceRootURL: source,
            destinationRootURL: destination,
            excelURL: nil,
            sourceItemsByRelativePath: [:],
            destinationAssetsByRelativePath: [:],
            progress:
                ProgressDocument(
                    rootFolderName: "assets"
                ),
            excelCatalog: nil
        )

        var document = AuditDocument(
            destinationRootName: "assets"
        )
        document.decisions[issue.id] =
            AuditDecision(
                issueID: issue.id,
                action: .delete,
                proposedFileName: nil,
                note: nil,
                decidedAt: Date()
            )

        XCTAssertThrowsError(
            try AssetAuditEngine.applyChanges(
                scan: scan,
                issues: [issue],
                document: &document
            )
        ) { error in
            guard case
                AuditApplyError
                .activeOutputDeleteForbidden =
                    error
            else {
                XCTFail(
                    "Expected active output delete guard, got \(error)"
                )
                return
            }
        }
    }
}
