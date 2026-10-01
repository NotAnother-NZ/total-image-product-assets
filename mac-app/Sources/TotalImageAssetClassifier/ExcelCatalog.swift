import Foundation

struct ExcelCatalog: Sendable {
    let knownSKUs: Set<String>
    let knownColors: Set<String>
    let productNamesBySKU: [String: Set<String>]

    static func load(from url: URL) throws -> ExcelCatalog {
        let entries = try unzip(arguments: ["-Z1", url.path])
            .split(separator: "\n")
            .map(String.init)

        let sharedStrings: [String]
        if entries.contains("xl/sharedStrings.xml") {
            let data = try unzipData(
                arguments: ["-p", url.path, "xl/sharedStrings.xml"]
            )
            sharedStrings = try SharedStringsParser.parse(data)
        } else {
            sharedStrings = []
        }

        let sheetPaths = entries
            .filter {
                $0.range(
                    of: #"^xl/worksheets/sheet\d+\.xml$"#,
                    options: .regularExpression
                ) != nil
            }
            .sorted()

        var knownSKUs = Set<String>()
        var knownColors = Set<String>()
        var productNamesBySKU: [String: Set<String>] = [:]

        for sheetPath in sheetPaths {
            let data = try unzipData(
                arguments: ["-p", url.path, sheetPath]
            )
            let rows = try WorksheetParser.parse(
                data,
                sharedStrings: sharedStrings
            )

            guard let header = findHeader(in: rows) else {
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
        }

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
        arguments: [String]
    ) throws -> String {
        let data = try unzipData(arguments: arguments)

        guard let output = String(
            data: data,
            encoding: .utf8
        ) else {
            throw ExcelCatalogError.invalidUTF8
        }

        return output
    }

    private static func unzipData(
        arguments: [String]
    ) throws -> Data {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/unzip"
        )
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: error, encoding: .utf8)
                ?? "unzip failed"
            throw ExcelCatalogError.unzipFailed(message)
        }

        return output
    }
}

enum ExcelCatalogError: LocalizedError {
    case invalidUTF8
    case unzipFailed(String)
    case invalidXML

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "Could not decode Excel workbook metadata."
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
