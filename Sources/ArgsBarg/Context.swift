// Runtime context passed to leaf command handlers after parsing.
// Callers read typed options and positional args from one place so handlers stay small and testable.
// Wraps merged option strings and the full schema for contextual error/help.

/// Handler closure type for leaf commands.
public typealias CliHandler = @Sendable (CliContext) -> Void

/// Values passed to a leaf command handler after parsing: app name, routed path, args, and merged options.
public final class CliContext: @unchecked Sendable {
    public let appName: String
    public let commandPath: [String]
    public let args: [String]
    /// Merged program root (same value passed to `cliRun`, after built-in merge) for contextual help.
    public let schema: CliCommand

    let opts: [String: String]

    /// Creates a context for invoking a leaf handler with the parsed argv slice and option map.
    init(
        appName: String,
        commandPath: [String],
        args: [String],
        opts: [String: String],
        schema: CliCommand
    ) {
        self.appName = appName
        self.commandPath = commandPath
        self.args = args
        self.opts = opts
        self.schema = schema
    }


    /// Returns whether a presence flag was set (including implicit `"1"` for boolean options).
    public func flag(_ name: String) -> Bool {
        opts[name] != nil
    }


    /// Returns the string value for a string-valued option, if present.
    public func stringOpt(_ name: String) -> String? {
        opts[name]
    }


    /// Parses a stored string as a number; returns `nil` if missing or not a strict double string.
    public func numberOpt(_ name: String) -> Double? {
        guard let s = opts[name] else { return nil }
        return strictParseDouble(s)
    }
}
