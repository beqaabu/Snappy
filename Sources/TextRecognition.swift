import AppKit
import Vision

// MARK: - Copy text (and QR codes) from a selection, on-device via Vision

enum TextRecognition {
    struct Result {
        var text: String
        var codes: [String] // QR and other barcode payloads, e.g. links
    }

    /// Recognizes text (one line per row, top to bottom) and barcodes in an image. Calls back on the main queue.
    static func recognize(_ image: CGImage, completion: @escaping (Result) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = true
            text.automaticallyDetectsLanguage = true
            let barcodes = VNDetectBarcodesRequest()
            try? VNImageRequestHandler(cgImage: image).perform([text, barcodes])

            let pieces = (text.results ?? []).compactMap { o in o.topCandidates(1).first.map { (box: o.boundingBox, text: $0.string) } }
            var codes: [String] = []
            for payload in (barcodes.results ?? []).compactMap(\.payloadStringValue) where !codes.contains(payload) {
                codes.append(payload)
            }
            let result = Result(text: rows(pieces).joined(separator: "\n"), codes: codes)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Vision returns separate observations for pieces of text on the same row (e.g. table cells).
    /// Groups them into rows by vertical overlap and joins each row left to right. Boxes use Vision's
    /// normalized coordinates, with y pointing up.
    static func rows(_ pieces: [(box: CGRect, text: String)]) -> [String] {
        var rows: [[(box: CGRect, text: String)]] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let first = rows.last?.first, abs(first.box.midY - piece.box.midY) < min(first.box.height, piece.box.height) / 2 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ") }
    }
}
