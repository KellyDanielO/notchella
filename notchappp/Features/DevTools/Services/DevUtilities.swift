import AppKit

/// One-click developer helpers. Each puts its result on the clipboard.
enum DevUtilities {
    /// Pretty-prints JSON on the clipboard in place. Returns false if it isn't JSON.
    static func formatClipboardJSON() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string),
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              // Writing a bare string or number raises an uncatchable exception, so check first.
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let result = String(data: pretty, encoding: .utf8)
        else { return false }
        copy(result)
        return true
    }

    /// Shows the system magnifier; the picked color is copied as a hex string.
    static func pickColor(completion: @escaping (String?) -> Void) {
        NSColorSampler().show { color in
            guard let rgb = color?.usingColorSpace(.sRGB) else {
                completion(nil)
                return
            }
            let hex = String(
                format: "#%02X%02X%02X",
                Int((rgb.redComponent * 255).rounded()),
                Int((rgb.greenComponent * 255).rounded()),
                Int((rgb.blueComponent * 255).rounded())
            )
            copy(hex)
            completion(hex)
        }
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
