import AppKit
import Foundation
import Vision
import PDFKit
import CoreGraphics
import CoreText
import ImageIO

// MARK: - CLI Parsing

struct Config {
    let inputPath: String
    let outputDir: String
    var dpi: CGFloat = 200
    var language: String = "en-US"
    var fast: Bool = false
    var pdfOutputPath: String? = nil
}

func parseArgs() -> Config? {
    var args = CommandLine.arguments.dropFirst()
    guard args.count >= 2 else {
        fputs("Usage: vision-ocr <input> <output-dir> [--dpi 200] [--lang en-US] [--fast] [--pdf <path>]\n", stderr)
        return nil
    }
    let input = args.removeFirst()
    let output = args.removeFirst()
    var cfg = Config(inputPath: input, outputDir: output)
    while !args.isEmpty {
        let flag = args.removeFirst()
        switch flag {
        case "--dpi":
            if let val = args.first.flatMap({ Double($0) }) { cfg.dpi = CGFloat(val); args.removeFirst() }
        case "--lang":
            if let val = args.first { cfg.language = val; args.removeFirst() }
        case "--fast":
            cfg.fast = true
        case "--pdf":
            if let val = args.first { cfg.pdfOutputPath = val; args.removeFirst() }
        default:
            fputs("Unknown flag: \(flag)\n", stderr)
        }
    }
    return cfg
}

// MARK: - OCR

/// Returns (plain text, observations as (string, normalized boundingBox in 0–1 bottom-left)).
func recognizeTextWithBoxes(in cgImage: CGImage, language: String, fast: Bool) -> (String, [(string: String, box: CGRect)]) {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = fast ? .fast : .accurate
    request.recognitionLanguages = [language]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])

    guard let observations = request.results else { return ("", []) }

    let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
    var lines: [String] = []
    var boxed: [(String, CGRect)] = []
    for obs in sorted {
        guard let candidate = obs.topCandidates(1).first, candidate.confidence >= 0.4 else { continue }
        let s = candidate.string
        lines.append(s)
        boxed.append((s, obs.boundingBox))
    }
    return (lines.joined(separator: "\n"), boxed)
}

func recognizeText(in cgImage: CGImage, language: String, fast: Bool) -> String {
    recognizeTextWithBoxes(in: cgImage, language: language, fast: fast).0
}

// MARK: - Searchable PDF

struct SearchablePDFPage {
    let cgImage: CGImage
    let bounds: CGRect
    let observations: [(string: String, box: CGRect)]
}

func writeSearchablePDF(pages: [SearchablePDFPage], to path: String) throws {
    guard let first = pages.first else { return }
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        throw NSError(domain: "vision-ocr", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create PDF consumer"])
    }
    var mediaBox = first.bounds
    guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw NSError(domain: "vision-ocr", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot create PDF context"])
    }

    for page in pages {
        var box = page.bounds
        ctx.beginPage(mediaBox: &box)

        // Draw page image
        ctx.draw(page.cgImage, in: CGRect(x: 0, y: 0, width: box.width, height: box.height))

        // Invisible text layer (transparent fill, selectable/searchable only).
        // Column-major order (left column then right, top-to-bottom) so selection stays per column.
        let columnMajor = page.observations.sorted { a, b in
            let (_, b1) = a, (_, b2) = b
            if abs(b1.midX - b2.midX) > 0.05 { return b1.midX < b2.midX }
            return b1.midY > b2.midY
        }
        for (string, normBox) in columnMajor {
            let pdfX = normBox.minX * box.width
            let pdfY = normBox.minY * box.height
            let pdfH = normBox.height * box.height
            if pdfH <= 0 { continue }
            guard let font = NSFont(name: "Helvetica", size: pdfH) else { continue }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0)
            ]
            let attrStr = NSAttributedString(string: string, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
            ctx.textPosition = CGPoint(x: pdfX, y: pdfY)
            CTLineDraw(line, ctx)
        }

        ctx.endPage()
    }

    ctx.closePDF()
    try (data as Data).write(to: URL(fileURLWithPath: path))
}

// MARK: - PDF path

func processPDF(cfg: Config, pdfPages: inout [SearchablePDFPage]?) throws -> Int {
    guard let pdf = PDFDocument(url: URL(fileURLWithPath: cfg.inputPath)) else {
        throw NSError(domain: "vision-ocr", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open PDF: \(cfg.inputPath)"])
    }
    let pageCount = pdf.pageCount
    let scale = cfg.dpi / 72.0

    for i in 0..<pageCount {
        guard let page = pdf.page(at: i) else { continue }
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let nsImage = page.thumbnail(of: size, for: .mediaBox)
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }

        let (text, observations) = recognizeTextWithBoxes(in: cgImage, language: cfg.language, fast: cfg.fast)
        let outPath = (cfg.outputDir as NSString).appendingPathComponent(String(format: "page-%03d.txt", i + 1))
        try text.write(toFile: outPath, atomically: true, encoding: .utf8)

        if var collector = pdfPages {
            collector.append(SearchablePDFPage(cgImage: cgImage, bounds: bounds, observations: observations))
            pdfPages = collector
        }
    }
    return pageCount
}

// MARK: - Image path

func processImage(cfg: Config) throws -> (Int, SearchablePDFPage?) {
    let url = URL(fileURLWithPath: cfg.inputPath)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw NSError(domain: "vision-ocr", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot load image: \(cfg.inputPath)"])
    }
    let (text, observations) = recognizeTextWithBoxes(in: cgImage, language: cfg.language, fast: cfg.fast)
    let outPath = (cfg.outputDir as NSString).appendingPathComponent("page-001.txt")
    try text.write(toFile: outPath, atomically: true, encoding: .utf8)
    let page: SearchablePDFPage? = cfg.pdfOutputPath != nil
        ? SearchablePDFPage(cgImage: cgImage, bounds: CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)), observations: observations)
        : nil
    return (1, page)
}

// MARK: - Manifest

func writeManifest(cfg: Config, inputType: String, pageCount: Int) throws {
    let iso8601: String = {
        let fmt = ISO8601DateFormatter()
        return fmt.string(from: Date())
    }()
    let manifest: [String: Any] = [
        "source": (cfg.inputPath as NSString).lastPathComponent,
        "input_type": inputType,
        "page_count": pageCount,
        "dpi": cfg.dpi,
        "language": cfg.language,
        "accuracy": cfg.fast ? "fast" : "accurate",
        "timestamp": iso8601
    ]
    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    let outPath = (cfg.outputDir as NSString).appendingPathComponent("manifest.json")
    try data.write(to: URL(fileURLWithPath: outPath))
}

// MARK: - Main

guard let cfg = parseArgs() else { exit(1) }

let fm = FileManager.default
try? fm.createDirectory(atPath: cfg.outputDir, withIntermediateDirectories: true)

let ext = (cfg.inputPath as NSString).pathExtension.lowercased()
let isPDF = ext == "pdf"

do {
    var pagesForPDF: [SearchablePDFPage]? = cfg.pdfOutputPath != nil ? [] : nil
    let pageCount: Int
    let inputType: String
    if isPDF {
        pageCount = try processPDF(cfg: cfg, pdfPages: &pagesForPDF)
        inputType = "pdf"
    } else {
        let (count, singlePage) = try processImage(cfg: cfg)
        pageCount = count
        if let p = singlePage { pagesForPDF = [p] }
        inputType = "image"
    }
    try writeManifest(cfg: cfg, inputType: inputType, pageCount: pageCount)
    if let path = cfg.pdfOutputPath, let pages = pagesForPDF, !pages.isEmpty {
        try writeSearchablePDF(pages: pages, to: path)
        print("Done: \(pageCount) page(s) → \(cfg.outputDir), searchable PDF → \(path)")
    } else {
        print("Done: \(pageCount) page(s) → \(cfg.outputDir)")
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
