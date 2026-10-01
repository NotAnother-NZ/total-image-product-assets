import Foundation

typealias ExcelCatalogProgressHandler = @Sendable (
    Double,
    String
) -> Void

struct ExcelCatalog: Sendable {
    let knownSKUs: Set<String>
    let knownColors: Set<String>
    let productNamesBySKU: [String: Set<String>]

    static func load(
        from url: URL,
        progressHandler: ExcelCatalogProgressHandler? = nil
    ) throws -> ExcelCatalog {
        progressHandler?(0.02, "Opening Excel workbook archive…")

        let entries = try unzip(
            arguments: ["-Z1", url.path],
            operation: "listing workbook contents"
        )
        .split(separator: "\n")
        .map(String.init)

        progressHandler?(
            0.08,
            "Workbook opened: \(entries.count) archive entries found."
        )

        let sharedStrings: [String]
        if entries.contains("xl/sharedStrings.xml") {
            progressHandler?(0.12, "Reading Excel shared strings…")

            let data = try unzipData(
                arguments: [
                    "-p",
                    url.path,
                    "xl/sharedStrings.xml"
                ],
                operation: "reading Excel shared strings"
            )

            progressHandler?(0.18, "Parsing Excel shared strings…")
            sharedStrings = try SharedStringsParser.parse(data)

            progressHandler?(
                0.24,
                "Parsed \(sharedStrings.count) shared strings."
            )
        } else {
            sharedStrings = []
            progressHandler?(
                0.24,
                "Workbook uses inline values; no shared strings file."
            )
        }

        let sheetPaths = entries
            .filter {
                $0.range(
                    of: #"^xl/worksheets/sheet\d+\.xml$"#,
                    options: .regularExpression
                ) != nil
            }
            .sorted()

        guard !sheetPaths.isEmpty else {
            throw ExcelCatalogError.noWorksheets
        }

        progressHandler?(
            0.28,
            "Found \(sheetPaths.count) worksheet(s)."
        )

        var knownSKUs = Set<String>()
        var knownColors = Set<String>()
        var productNamesBySKU: [String: Set<String>] = [:]

        let sheetProgressSpan = 0.68
        let perSheet = sheetProgressSpan
            / Double(sheetPaths.count)

        for (index, sheetPath) in sheetPaths.enumerated() {
            let sheetNumber = index + 1
            let base = 0.28 + (Double(index) * perSheet)

            progressHandler?(
                base,
                "Reading worksheet \(sheetNumber)/\(sheetPaths.count)…"
            )

            let data = try unzipData(
                arguments: ["-p", url.path, sheetPath],
                operation:
                    "reading worksheet \(sheetNumber)/\(sheetPaths.count)"
            )

            progressHandler?(
                base + (perSheet * 0.30),
                "Parsing worksheet \(sheetNumber)/\(sheetPaths.count)…"
            )

            let rows = try WorksheetParser.parse(
                data,
                sharedStrings: sharedStrings
            )

            progressHandler?(
                base + (perSheet * 0.60),
                "Processing worksheet \(sheetNumber)/\(sheetPaths.count) (\(rows.count) rows)…"
            )

            guard let header = findHeader(in: rows) else {
                progressHandler?(
                    base + perSheet,
                    "Worksheet \(sheetNumber)/\(sheetPaths.count) has no SKU header; skipped."
                )
                continue
            }

            for row in rows where row.number > header.rowNumber {
                guard let skuValue = row.cells[header.skuColumn],
                      !skuValue.trimmingCharacters(
                        in: .whitespacesAndNewlines
                      ).isEmpty
                else {
                    continue
                }

                let skus = splitSKUs(skuValue)

                for sku in skus {
                    knownSKUs.insert(sku)
                }

                if let colorColumn = header.colorColumn,
                   let colorValue = row.cells[colorColumn]
                {
                    for color in splitColors(colorValue) {
                        knownColors.insert(color)
                    }
                }

                if let productColumn = header.productColumn,
                   let product = row.cells[productColumn]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !product.isEmpty
                {
                    for sku in skus {
                        productNamesBySKU[sku, default: []]
                            .insert(product)
                    }
                }
            }

            progressHandler?(
                base + perSheet,
                "Finished worksheet \(sheetNumber)/\(sheetPaths.count)."
            )
        }

        progressHandler?(
            1,
            "Client Excel ready: \(knownSKUs.count) SKU(s), \(knownColors.count) colour value(s)."
        )

        return ExcelCatalog(
            knownSKUs: knownSKUs,
            knownColors: knownColors,
            productNamesBySKU: productNamesBySKU
        )
    }

    private struct Header {
        let rowNumber: Int
        let skuColumn: String
        let colorColumn: String?
        let productColumn: String?
    }

    private static func findHeader(
        in rows: [WorksheetRow]
    ) -> Header? {
        for row in rows.prefix(25) {
            var skuColumn: String?
            var colorColumn: String?
            var productColumn: String?

            for (column, value) in row.cells {
                let normalized = value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                if normalized == "sku"
                    || normalized == "product sku"
                    || normalized.hasSuffix(" sku")
                {
                    skuColumn = column
                }

                if normalized.contains("colour")
                    || normalized.contains("color")
                {
                    colorColumn = column
                }

                if normalized == "product"
                    || normalized == "product name"
                    || normalized == "name"
                {
                    productColumn = column
                }
            }

            if let skuColumn {
                return Header(
                    rowNumber: row.number,
                    skuColumn: skuColumn,
                    colorColumn: colorColumn,
                    productColumn: productColumn
                )
            }
        }

        return nil
    }

    private static func splitSKUs(
        _ value: String
    ) -> [String] {
        value.components(
            separatedBy: CharacterSet(
                charactersIn: " ,;\n\t"
            )
        )
        .map(normalizeToken)
        .filter {
            !$0.isEmpty
                && $0 != "-"
                && $0 != "N/A"
        }
    }

    private static func splitColors(
        _ value: String
    ) -> [String] {
        let primary = value.components(
            separatedBy: CharacterSet(
                charactersIn: ",;\n\t"
            )
        )

        var values = Set<String>()

        for item in primary {
            let normalized = normalizeLabel(item)
            if !normalized.isEmpty {
                values.insert(normalized)
            }

            for component in item.split(separator: "/") {
                let piece = normalizeLabel(String(component))
                if !piece.isEmpty {
                    values.insert(piece)
                }
            }
        }

        return values.sorted()
    }

    private static func normalizeToken(
        _ value: String
    ) -> String {
        value.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).uppercased()
    }

    static func normalizeLabel(
        _ value: String
    ) -> String {
        value
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .uppercased()
            .replacingOccurrences(
                of: #"[^A-Z0-9]+"#,
                with: " ",
                options: .regularExpression
            )
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func unzip(
        arguments: [String],
        operation: String
    ) throws -> String {
        let data = try unzipData(
            arguments: arguments,
            operation: operation
        )

        guard let output = String(
            data: data,
            encoding: .utf8
        ) else {
            throw ExcelCatalogError.invalidUTF8
        }

        return output
    }

    private static func unzipData(
        arguments: [String],
        operation: String,
        timeout: TimeInterval = 30
    ) throws -> Data {
        let process = Process()
        let fileManager = FileManager.default
        let token = UUID().uuidString
        let temporaryDirectory =
            fileManager.temporaryDirectory
        let outputURL = temporaryDirectory
            .appendingPathComponent(
                "total-image-excel-\(token).stdout"
            )
        let errorURL = temporaryDirectory
            .appendingPathComponent(
                "total-image-excel-\(token).stderr"
            )

        guard fileManager.createFile(
            atPath: outputURL.path,
            contents: nil
        ),
        fileManager.createFile(
            atPath: errorURL.path,
            contents: nil
        ) else {
            throw ExcelCatalogError.temporaryFileFailed
        }

        let stdout = try FileHandle(
            forWritingTo: outputURL
        )
        let stderr = try FileHandle(
            forWritingTo: errorURL
        )

        defer {
            try? stdout.close()
            try? stderr.close()
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.removeItem(at: errorURL)
        }

        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/unzip"
        )
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let deadline = Date()
            .addingTimeInterval(timeout)

        while process.isRunning && Date() < deadline {
            Thread.sleep(
                forTimeInterval: 0.05
            )
        }

        if process.isRunning {
            process.terminate()

            let terminationDeadline = Date()
                .addingTimeInterval(2)

            while process.isRunning
                && Date() < terminationDeadline
            {
                Thread.sleep(
                    forTimeInterval: 0.05
                )
            }

            throw ExcelCatalogError.unzipTimedOut(
                operation,
                Int(timeout)
            )
        }

        process.waitUntilExit()

        let output = try Data(contentsOf: outputURL)
        let error = try Data(contentsOf: errorURL)

        guard process.terminationStatus == 0 else {
            let message = String(
                data: error,
                encoding: .utf8
            )?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            throw ExcelCatalogError.unzipFailed(
                message?.isEmpty == false
                    ? message!
                    : "unzip exited with status \(process.terminationStatus)"
            )
        }

        return output
    }
}

enum ExcelCatalogError: LocalizedError {
    case invalidUTF8
    case noWorksheets
    case temporaryFileFailed
    case unzipTimedOut(String, Int)
    case unzipFailed(String)
    case invalidXML

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "Could not decode Excel workbook metadata."
        case .noWorksheets:
            return "The selected Excel workbook does not contain any readable worksheets."
        case .temporaryFileFailed:
            return "Could not create temporary files needed to read the Excel workbook."
        case .unzipTimedOut(let operation, let seconds):
            return "Excel workbook read timed out after \(seconds) seconds while \(operation). The audit was stopped safely; no destination files were changed."
        case .unzipFailed(let message):
            return "Could not read Excel workbook: \(message)"
        case .invalidXML:
            return "Could not parse the Excel workbook."
        }
    }
}

private struct WorksheetRow {
    let number: Int
    let cells: [String: String]
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentText = ""
    private var insideText = false
    private var insideString = false

    static func parse(
        _ data: Data
    ) throws -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw ExcelCatalogError.invalidXML
        }

        return delegate.strings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "si" {
            insideString = true
            currentText = ""
        } else if insideString && elementName == "t" {
            insideText = true
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if insideText {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "t" {
            insideText = false
        } else if elementName == "si" {
            strings.append(currentText)
            insideString = false
        }
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]

    private var rows: [WorksheetRow] = []
    private var currentRowNumber = 0
    private var currentCells: [String: String] = [:]

    private var currentReference = ""
    private var currentType = ""
    private var currentValue = ""
    private var currentInlineText = ""
    private var insideValue = false
    private var insideInlineText = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(
        _ data: Data,
        sharedStrings: [String]
    ) throws -> [WorksheetRow] {
        let delegate = WorksheetParser(
            sharedStrings: sharedStrings
        )
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw ExcelCatalogError.invalidXML
        }

        return delegate.rows
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "row":
            currentRowNumber = Int(attributeDict["r"] ?? "") ?? 0
            currentCells = [:]

        case "c":
            currentReference = attributeDict["r"] ?? ""
            currentType = attributeDict["t"] ?? ""
            currentValue = ""
            currentInlineText = ""

        case "v":
            insideValue = true

        case "t":
            if currentType == "inlineStr" {
                insideInlineText = true
            }

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if insideValue {
            currentValue += string
        }

        if insideInlineText {
            currentInlineText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "v":
            insideValue = false

        case "t":
            insideInlineText = false

        case "c":
            let column = currentReference
                .prefix { $0.isLetter }
                .map(String.init)
                .joined()

            guard !column.isEmpty else { return }

            let value: String
            if currentType == "s",
               let index = Int(currentValue),
               sharedStrings.indices.contains(index)
            {
                value = sharedStrings[index]
            } else if currentType == "inlineStr" {
                value = currentInlineText
            } else {
                value = currentValue
            }

            currentCells[column] = value

        case "row":
            rows.append(
                WorksheetRow(
                    number: currentRowNumber,
                    cells: currentCells
                )
            )

        default:
            break
        }
    }
}
