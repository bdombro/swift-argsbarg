/// Handler closure type for leaf commands.
public typealias CliHandler = @Sendable (CliContext) -> Void

/// Values passed to a leaf command handler after parsing.
public final class CliContext: @unchecked Sendable {
    public let appName: String
    public let commandPath: [String]
    public let args: [String]
    /// Merged program root (same value passed to `cliRun`, after built-in merge) for contextual help.
    public let schema: CliCommand

    let opts: [String: String]

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

    /// Presence flag was set (including implicit `"1"` for boolean options).
    public func flag(_ name: String) -> Bool {
        opts[name] != nil
    }

    public func stringOpt(_ name: String) -> String? {
        opts[name]
    }

    /// Parsed from the stored string; returns `nil` if missing or not a strict double string.
    public func numberOpt(_ name: String) -> Double? {
        guard let s = opts[name] else { return nil }
        return strictParseDouble(s)
    }
}
