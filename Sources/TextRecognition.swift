import AppKit
import Vision

// MARK: - Copy text from a selection (on-device, via Vision)

enum TextRecognition {
    /// Recognizes the text in an image, one line per row, top to bottom. Calls back on the main queue.
    static func recognize(_ image: CGImage, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let text = lines(from: request.results ?? []).joined(separator: "\n")
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// Vision returns separate observations for pieces of text on the same row (e.g. table cells).
    /// Group them into rows by vertical overlap and join each row left to right.
    private static func lines(from observations: [VNRecognizedTextObservation]) -> [String] {
        let pieces = observations.compactMap { o in o.topCandidates(1).first.map { (box: o.boundingBox, text: $0.string) } }
            .sorted { $0.box.midY > $1.box.midY } // Vision's y axis points up
        var rows: [[(box: CGRect, text: String)]] = []
        for piece in pieces {
            if let last = rows.last?.first, abs(last.box.midY - piece.box.midY) < min(last.box.height, piece.box.height) / 2 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ") }
    }
}
