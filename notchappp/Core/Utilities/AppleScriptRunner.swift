import Foundation

/// Runs AppleScript off the main thread on a single serial queue, caching compiled scripts.
nonisolated enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "com.kellydaniel.notchappp.applescript", qos: .userInitiated)
    // Only touched from `queue`.
    nonisolated(unsafe) private static var cache: [String: NSAppleScript] = [:]

    /// Executes `source` and converts the result with `transform` while still on the script queue.
    static func run<T: Sendable>(
        _ source: String,
        transform: @escaping @Sendable (NSAppleEventDescriptor) -> T?
    ) async -> T? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: execute(source).flatMap(transform))
            }
        }
    }

    /// Fire-and-forget execution, used for player commands.
    static func send(_ source: String) {
        queue.async { _ = execute(source) }
    }

    private static func execute(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let cached = cache[source] {
            script = cached
        } else {
            guard let compiled = NSAppleScript(source: source) else { return nil }
            var compileError: NSDictionary?
            guard compiled.compileAndReturnError(&compileError) else { return nil }
            cache[source] = compiled
            script = compiled
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}
