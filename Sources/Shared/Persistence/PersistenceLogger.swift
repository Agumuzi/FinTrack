import OSLog
import SwiftData

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "FinTrack"

    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let startup = Logger(subsystem: subsystem, category: "Startup")
    static let export = Logger(subsystem: subsystem, category: "Export")

    static func info(_ logger: Logger, _ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ logger: Logger, _ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    static func fault(_ logger: Logger, _ message: String) {
        logger.fault("\(message, privacy: .public)")
    }
}

struct PersistenceLogger {
    // Central save gateway for SwiftData writes. Callers should route
    // persistence through this helper so logging and error handling stay uniform.
    static func save(
        _ modelContext: ModelContext,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        do {
            try saveThrowing(
                modelContext,
                file: file,
                function: function,
                line: line
            )
        } catch {
            // Errors are already logged by saveThrowing.
        }
    }

    static func saveThrowing(
        _ modelContext: ModelContext,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) throws {
        do {
            try modelContext.save()
        } catch {
            AppLog.error(
                AppLog.persistence,
                "Save failed at \(String(describing: file)):\(line) \(String(describing: function)): \(String(describing: error))"
            )
            throw error
        }
    }
}
