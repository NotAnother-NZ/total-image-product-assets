import Foundation
import XCTest
@testable import TotalImageAssetClassifier

final class ExcelCatalogTests: XCTestCase {
    private final class ProgressRecorder:
        @unchecked Sendable
    {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ value: String) {
            lock.lock()
            storage.append(value)
            lock.unlock()
        }

        var values: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private func makeTemporaryDirectory()
        throws -> URL
    {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "ExcelCatalogTests-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func makeLargeWorkbook(
        rowCount: Int
    ) throws -> (root: URL, workbook: URL) {
        let root = try makeTemporaryDirectory()
        let worksheetDirectory = root
            .appendingPathComponent(
                "xl/worksheets",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: worksheetDirectory,
            withIntermediateDirectories: true
        )

        var xml =
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>"#

        xml +=
            #"<row r="1"><c r="A1" t="inlineStr"><is><t>Product Name</t></is></c><c r="B1" t="inlineStr"><is><t>SKU</t></is></c><c r="C1" t="inlineStr"><is><t>Colour</t></is></c></row>"#

        for row in 2...(rowCount + 1) {
            let index = row - 1
            xml +=
                #"<row r="#(row)"><c r="A#(row)" t="inlineStr"><is><t>Product #(index)</t></is></c><c r="B#(row)" t="inlineStr"><is><t>SKU#(index)</t></is></c><c r="C#(row)" t="inlineStr"><is><t>Navy</t></is></c></row>"#
        }

        xml += "</sheetData></worksheet>"

        let sheetURL = worksheetDirectory
            .appendingPathComponent("sheet1.xml")
        try xml.write(
            to: sheetURL,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertGreaterThan(
            try Data(contentsOf: sheetURL).count,
            128 * 1024,
            "Fixture must be larger than a typical process pipe buffer."
        )

        let workbook = root
            .appendingPathComponent(
                "large-workbook.xlsx"
            )
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/zip"
        )
        process.currentDirectoryURL = root
        process.arguments = [
            "-q",
            "-r",
            workbook.lastPathComponent,
            "xl"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(
            process.terminationStatus,
            0,
            "Failed to create test workbook."
        )

        return (root, workbook)
    }

    func testLargeWorkbookDoesNotDeadlockAndReportsProgress()
        throws
    {
        let fixture = try makeLargeWorkbook(
            rowCount: 5_000
        )
        defer {
            try? FileManager.default.removeItem(
                at: fixture.root
            )
        }

        let recorder = ProgressRecorder()
        let started = Date()

        let catalog = try ExcelCatalog.load(
            from: fixture.workbook
        ) { _, message in
            recorder.append(message)
        }

        let elapsed = Date()
            .timeIntervalSince(started)

        XCTAssertLessThan(
            elapsed,
            10,
            "Large workbook parsing should finish promptly instead of blocking on subprocess output."
        )
        XCTAssertEqual(
            catalog.knownSKUs.count,
            5_000
        )
        XCTAssertTrue(
            catalog.knownSKUs.contains("SKU5000")
        )
        XCTAssertTrue(
            catalog.knownColors.contains("NAVY")
        )
        XCTAssertTrue(
            recorder.values.contains {
                $0.contains(
                    "Reading worksheet 1/1"
                )
            }
        )
        XCTAssertTrue(
            recorder.values.contains {
                $0.contains(
                    "Client Excel ready"
                )
            }
        )
    }
}
