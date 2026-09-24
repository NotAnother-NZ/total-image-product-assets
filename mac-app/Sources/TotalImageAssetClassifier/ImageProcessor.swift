import Foundation

enum ImageProcessorError: LocalizedError {
    case imageMagickNotFound
    case commandFailed(String)
    case boundingBoxNotFound

    var errorDescription: String? {
        switch self {
        case .imageMagickNotFound:
            return "ImageMagick was not found. Install it with: brew install imagemagick"
        case .commandFailed(let message):
            return message
        case .boundingBoxNotFound:
            return "Could not detect the visible product bounds."
        }
    }
}

enum ImageProcessor {
    static let targetVisibleWidthFraction = 0.621

    static func locateMagick() -> String? {
        let fileManager = FileManager.default

        let candidates = [
            "/opt/homebrew/bin/magick",
            "/usr/local/bin/magick",
            "/opt/local/bin/magick"
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let which = Process()
        let pipe = Pipe()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["magick"]
        which.standardOutput = pipe
        which.standardError = Pipe()

        do {
            try which.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            which.waitUntilExit()

            guard which.terminationStatus == 0,
                  let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty,
                  fileManager.isExecutableFile(atPath: path)
            else {
                return nil
            }

            return path
        } catch {
            return nil
        }
    }

    static func process(
        job: ProcessingJob,
        magickPath: String
    ) throws -> ProcessingResult {
        let fileManager = FileManager.default
        let parent = job.sourceURL.deletingLastPathComponent()

        let outputDirectory = parent
            .appendingPathComponent("webp", isDirectory: true)
            .appendingPathComponent(job.classification.outputFolderName, isDirectory: true)

        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let outputURL = outputDirectory
            .appendingPathComponent(job.outputStem)
            .appendingPathExtension("webp")

        let opposite: AssetClassification = job.classification == .model ? .product : .model
        let staleOppositeURL = parent
            .appendingPathComponent("webp", isDirectory: true)
            .appendingPathComponent(opposite.outputFolderName, isDirectory: true)
            .appendingPathComponent(job.outputStem)
            .appendingPathExtension("webp")

        if fileManager.fileExists(atPath: staleOppositeURL.path) {
            try? fileManager.removeItem(at: staleOppositeURL)
        }

        var bboxDescription: String?
        var canvasDescription: String?

        switch job.classification {
        case .model:
            try run(
                executable: magickPath,
                arguments: [
                    job.sourceURL.path,
                    "-auto-orient",
                    "-resize", "1200x>",
                    "-strip",
                    "-quality", "88",
                    outputURL.path
                ]
            )

        case .product:
            let bbox = try detectProductBoundingBox(
                sourceURL: job.sourceURL,
                magickPath: magickPath
            )

            let canvas = normalizedCanvas(for: bbox)
            bboxDescription = "\(bbox.width)x\(bbox.height)+\(bbox.x)+\(bbox.y)"
            canvasDescription = "\(canvas.width)x\(canvas.height)"

            try run(
                executable: magickPath,
                arguments: [
                    job.sourceURL.path,
                    "-auto-orient",
                    "-crop", "\(bbox.width)x\(bbox.height)+\(bbox.x)+\(bbox.y)",
                    "+repage",
                    "-background", "#FFFFFF",
                    "-gravity", "center",
                    "-extent", "\(canvas.width)x\(canvas.height)",
                    "-resize", "1200x>",
                    "-strip",
                    "-quality", "88",
                    outputURL.path
                ]
            )
        }

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw ImageProcessorError.commandFailed(
                "ImageMagick finished without creating the expected output."
            )
        }

        let rootPath = job.rootURL.standardizedFileURL.path
        let outputPath = outputURL.standardizedFileURL.path
        let relativeOutput: String

        if outputPath.hasPrefix(rootPath + "/") {
            relativeOutput = String(outputPath.dropFirst(rootPath.count + 1))
        } else {
            relativeOutput = outputPath
        }

        return ProcessingResult(
            outputURL: outputURL,
            outputRelativePath: relativeOutput,
            bboxDescription: bboxDescription,
            canvasDescription: canvasDescription
        )
    }

    private struct BoundingBox {
        let width: Int
        let height: Int
        let x: Int
        let y: Int
    }

    private struct Canvas {
        let width: Int
        let height: Int
    }

    private static func normalizedCanvas(for bbox: BoundingBox) -> Canvas {
        var width = Int(
            ceil(Double(bbox.width) / targetVisibleWidthFraction)
        )

        width = roundUpToMultipleOfThree(width)
        var height = width * 4 / 3

        if bbox.height > height {
            let minimumWidth = roundUpToMultipleOfThree(
                Int(ceil(Double(bbox.height) * 3.0 / 4.0))
            )

            if minimumWidth > width {
                width = minimumWidth
                height = width * 4 / 3
            }
        }

        return Canvas(width: width, height: height)
    }

    private static func roundUpToMultipleOfThree(_ value: Int) -> Int {
        let remainder = value % 3
        return remainder == 0 ? value : value + (3 - remainder)
    }

    private static func detectProductBoundingBox(
        sourceURL: URL,
        magickPath: String
    ) throws -> BoundingBox {
        let thresholds = [3, 4, 5, 2, 1]

        for threshold in thresholds {
            let output = try run(
                executable: magickPath,
                arguments: [
                    sourceURL.path,
                    "-auto-orient",
                    "-background", "white",
                    "-alpha", "remove",
                    "-alpha", "off",
                    "-colorspace", "gray",
                    "-negate",
                    "-threshold", "\(threshold)%",
                    "-define", "connected-components:verbose=true",
                    "-define", "connected-components:sort=area",
                    "-define", "connected-components:sort-order=decreasing",
                    "-connected-components", "8",
                    "null:"
                ]
            )

            if let bbox = parseLargestWhiteComponent(output) {
                return bbox
            }
        }

        throw ImageProcessorError.boundingBoxNotFound
    }

    private static func parseLargestWhiteComponent(_ text: String) -> BoundingBox? {
        let geometryRegex = try? NSRegularExpression(
            pattern: #"([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)"#
        )

        guard let geometryRegex else { return nil }

        for line in text.components(separatedBy: .newlines) {
            let lower = line.lowercased()

            guard lower.contains("gray(255") || lower.contains("srgb(255,255,255") else {
                continue
            }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            guard let match = geometryRegex.firstMatch(
                in: line,
                options: [],
                range: range
            ), match.numberOfRanges == 5 else {
                continue
            }

            func intValue(_ index: Int) -> Int? {
                guard let swiftRange = Range(match.range(at: index), in: line) else {
                    return nil
                }
                return Int(line[swiftRange])
            }

            guard let width = intValue(1),
                  let height = intValue(2),
                  let x = intValue(3),
                  let y = intValue(4),
                  width > 5,
                  height > 5
            else {
                continue
            }

            return BoundingBox(
                width: width,
                height: height,
                x: x,
                y: y
            )
        }

        return nil
    }

    @discardableResult
    private static func run(
        executable: String,
        arguments: [String]
    ) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw ImageProcessorError.commandFailed(
                "Could not launch ImageMagick: \(error.localizedDescription)"
            )
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ImageProcessorError.commandFailed(
                message.isEmpty
                    ? "ImageMagick exited with status \(process.terminationStatus)."
                    : message
            )
        }

        return output
    }
}
