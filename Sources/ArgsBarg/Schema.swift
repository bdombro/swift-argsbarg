/// Option values for flags and options (non-positional).
public enum CliOptionKind {
    case presence
    case string
    case number
}

/// When `fallbackCommand` is used for missing or unknown top-level tokens.
/// Only the program root (the `CliCommand` passed to `cliRun`) may set a non-default mode or a non-nil `fallbackCommand`; nested commands must use defaults until per-group fallback is implemented.
public enum CliFallbackMode {
    case missingOnly
    case missingOrUnknown
    case unknownOnly
}

/// One CLI flag, option, or positional definition.
public struct CliOption {
    public var name: String
    public var description: String
    public var kind: CliOptionKind
    public var shortName: Character?
    public var positional: Bool
    public var argMin: Int
    public var argMax: Int

    public init(
        name: String,
        description: String,
        kind: CliOptionKind = .presence,
        shortName: Character? = nil,
        positional: Bool = false,
        argMin: Int = 1,
        argMax: Int = 1
    ) {
        self.name = name
        self.description = description
        self.kind = kind
        self.shortName = shortName
        self.positional = positional
        self.argMin = argMin
        self.argMax = argMax
    }
}

/// A command node: routing group (has `children`) or leaf (has `handler`).
///
/// The value passed to `cliRun(_:)` is the **program root**: `name` is the app/binary name, `children` are top-level subcommands, `options` are global flags. The root must not set `handler` or declare `positionals` (validated at startup).
public struct CliCommand {
    public var name: String
    public var description: String
    public var notes: String
    public var options: [CliOption]
    public var positionals: [CliOption]
    public var children: [CliCommand]
    public var handler: (@Sendable (CliContext) -> Void)?
    /// Default top-level subcommand when argv omits a command or uses an unknown first token (root only).
    public var fallbackCommand: String?
    /// How `fallbackCommand` is applied (root only).
    public var fallbackMode: CliFallbackMode

    public init(
        name: String,
        description: String,
        notes: String = "",
        options: [CliOption] = [],
        positionals: [CliOption] = [],
        children: [CliCommand] = [],
        handler: (@Sendable (CliContext) -> Void)? = nil,
        fallbackCommand: String? = nil,
        fallbackMode: CliFallbackMode = .missingOnly
    ) {
        self.name = name
        self.description = description
        self.notes = notes
        self.options = options
        self.positionals = positionals
        self.children = children
        self.handler = handler
        self.fallbackCommand = fallbackCommand
        self.fallbackMode = fallbackMode
    }
}
