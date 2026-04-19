#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum ParseKind {
    case ok
    case help
    case error
}

struct ParseResult {
    var kind: ParseKind = .ok
    var path: [String] = []
    var opts: [String: String] = [:]
    var args: [String] = []
    var helpExplicit: Bool = false
    var helpPath: [String] = []
    var errorMsg: String = ""
    var errorHelpPath: [String] = []
}

enum CliSchemaValidationError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let s): return s
        }
    }
}

private let helpShort = "-h"
private let helpLong = "--help"

private func isHelpTok(_ tok: String) -> Bool {
    tok == helpShort || tok == helpLong
}

func findChild(_ cmds: [CliCommand], _ name: String) -> CliCommand? {
    cmds.first { $0.name == name }
}

func findOptionByName(_ defs: [CliOption], _ name: String) -> CliOption? {
    defs.first { $0.name == name }
}

private func findOptionDefByShort(_ defs: [CliOption], _ short: Character) -> CliOption? {
    defs.first { !$0.positional && $0.shortName == short }
}

/// Match C++ `strtod` consuming the entire string (no leading/trailing junk).
func fullStringIsDouble(_ s: String) -> Bool {
    if s.isEmpty { return false }
    return s.withCString { ptr -> Bool in
        var end: UnsafeMutablePointer<CChar>?
        _ = strtod(ptr, &end)
        guard let e = end else { return false }
        return e == ptr.advanced(by: strlen(ptr))
    }
}

func strictParseDouble(_ s: String) -> Double? {
    guard fullStringIsDouble(s) else { return nil }
    return s.withCString { ptr -> Double in
        var end: UnsafeMutablePointer<CChar>?
        return strtod(ptr, &end)
    }
}

private struct ConsumeReport {
    var err: String?
    var stoppedOnUnknown: Bool = false
}

private func consumeOptions(
    defs: [CliOption],
    lenientUnknown: Bool,
    argv: [String],
    i: inout Int,
    opts: inout [String: String]
) -> ConsumeReport {
    func consumeLong(_ tok: String) -> String? {
        let body = tok.dropFirst(2)
        let optName: String
        let inlineVal: String?
        if let eq = body.firstIndex(of: "=") {
            optName = String(body[..<eq])
            inlineVal = String(body[body.index(after: eq)...])
        } else {
            optName = String(body)
            inlineVal = nil
        }

        guard let def = findOptionByName(defs, optName) else {
            if lenientUnknown {
                return ""
            }
            return "Unknown option: --\(optName)"
        }

        if let v = inlineVal {
            if def.kind == .presence {
                opts[def.name] = "1"
            } else {
                opts[def.name] = v
            }
            i += 1
            return nil
        }

        if def.kind == .presence {
            opts[def.name] = "1"
        } else {
            i += 1
            if i >= argv.count {
                return "Missing value for option: --\(optName)"
            }
            opts[def.name] = argv[i]
        }
        i += 1
        return nil
    }

    func consumeShort(_ tok: String) -> String? {
        guard tok.count >= 2 else {
            return "Unexpected option token: \(tok)"
        }
        let shorts = tok.dropFirst()
        var j = shorts.startIndex
        while j < shorts.endIndex {
            let shortChar = shorts[j]
            guard let def = findOptionDefByShort(defs, shortChar) else {
                if lenientUnknown {
                    return ""
                }
                return "Unknown option: -\(shortChar)"
            }

            if def.kind == .presence {
                opts[def.name] = "1"
                j = shorts.index(after: j)
                continue
            }

            if shorts.distance(from: shorts.startIndex, to: j) != 0 || shorts.index(after: j) < shorts.endIndex {
                return "Short option -\(shortChar) requires a value and cannot be bundled: \(tok)"
            }

            i += 1
            if i >= argv.count {
                return "Missing value for option: -\(shortChar)"
            }
            opts[def.name] = argv[i]
            i += 1
            return nil
        }
        i += 1
        return nil
    }

    while i < argv.count {
        let tok = argv[i]
        if isHelpTok(tok) {
            break
        }
        if !tok.hasPrefix("-") {
            break
        }
        if tok.hasPrefix("--") {
            if let r = consumeLong(tok) {
                if r.isEmpty {
                    return ConsumeReport(stoppedOnUnknown: true)
                }
                return ConsumeReport(err: r)
            }
        } else {
            if let r = consumeShort(tok) {
                if r.isEmpty {
                    return ConsumeReport(stoppedOnUnknown: true)
                }
                return ConsumeReport(err: r)
            }
        }
    }
    return ConsumeReport()
}

private func finishLeaf(
    node: CliCommand,
    i: inout Int,
    argv: [String],
    path: [String],
    opts: [String: String]
) -> ParseResult {
    func errorResult(_ msg: String) -> ParseResult {
        var pr = ParseResult()
        pr.kind = .error
        pr.errorMsg = msg
        pr.errorHelpPath = path
        return pr
    }

    var args: [String] = []
    var idx = i

    for p in node.positionals where p.positional {
        if p.argMax == 1 {
            if p.argMin >= 1 {
                if idx >= argv.count {
                    return errorResult("Missing positional argument: \(p.name)")
                }
                args.append(argv[idx])
                idx += 1
            } else if idx < argv.count {
                args.append(argv[idx])
                idx += 1
            }
            continue
        }

        var count = 0
        if p.argMax == 0 {
            while idx < argv.count {
                args.append(argv[idx])
                idx += 1
                count += 1
            }
        } else {
            while count < p.argMax && idx < argv.count {
                args.append(argv[idx])
                idx += 1
                count += 1
            }
        }
        if count < p.argMin {
            return errorResult(
                "Expected at least \(p.argMin) argument(s) for \(p.name), got \(count)"
            )
        }
    }

    if idx < argv.count {
        return errorResult("Unexpected extra arguments")
    }

    var pr = ParseResult()
    pr.kind = .ok
    pr.path = path
    pr.opts = opts
    pr.args = args
    return pr
}

func parse(root: CliCommand, argv: [String]) -> ParseResult {
    var i = 0
    var path: [String] = []
    var opts: [String: String] = [:]

    func helpResult(_ p: [String], _ explicit: Bool) -> ParseResult {
        var r = ParseResult()
        r.kind = .help
        r.helpExplicit = explicit
        r.helpPath = p
        return r
    }

    func errorResult(_ msg: String) -> ParseResult {
        var r = ParseResult()
        r.kind = .error
        r.errorMsg = msg
        r.errorHelpPath = path
        return r
    }

    let rootLenient =
        root.fallbackCommand != nil
        && (root.fallbackMode == .missingOrUnknown || root.fallbackMode == .unknownOnly)

    let rootRep = consumeOptions(
        defs: root.options,
        lenientUnknown: rootLenient,
        argv: argv,
        i: &i,
        opts: &opts
    )
    if let e = rootRep.err {
        var r = ParseResult()
        r.kind = .error
        r.errorMsg = e
        r.errorHelpPath = path
        return r
    }

    if i < argv.count && isHelpTok(argv[i]) {
        return helpResult([], true)
    }

    let cmdName: String
    var node: CliCommand?

    if i >= argv.count {
        if let fb = root.fallbackCommand,
            root.fallbackMode == .missingOnly || root.fallbackMode == .missingOrUnknown
        {
            cmdName = fb
            node = findChild(root.children, cmdName)
            if node == nil {
                return errorResult("Unknown command: \(cmdName)")
            }
        } else {
            return helpResult([], false)
        }
    } else {
        let peek = argv[i]
        let childPick = findChild(root.children, peek)
        let canRouteUnknown =
            root.fallbackCommand != nil
            && (root.fallbackMode == .missingOrUnknown || root.fallbackMode == .unknownOnly)

        if childPick != nil {
            cmdName = peek
            i += 1
            node = childPick
        } else if canRouteUnknown {
            cmdName = root.fallbackCommand!
            node = findChild(root.children, cmdName)
            if node == nil {
                return errorResult("Unknown command: \(cmdName)")
            }
        } else {
            cmdName = peek
            i += 1
            node = findChild(root.children, cmdName)
            if node == nil {
                return errorResult("Unknown command: \(cmdName)")
            }
        }
    }

    path.append(cmdName)
    var current = node!

    while true {
        let orep = consumeOptions(
            defs: current.options,
            lenientUnknown: false,
            argv: argv,
            i: &i,
            opts: &opts
        )
        if let e = orep.err {
            var r = ParseResult()
            r.kind = .error
            r.errorMsg = e
            r.errorHelpPath = path
            return r
        }

        if i < argv.count && isHelpTok(argv[i]) {
            return helpResult(path, true)
        }

        if i >= argv.count {
            if !current.children.isEmpty {
                return helpResult(path, false)
            }
            return finishLeaf(node: current, i: &i, argv: argv, path: path, opts: opts)
        }

        let tok = argv[i]
        if tok.hasPrefix("-") {
            var r = ParseResult()
            r.kind = .error
            r.errorMsg = "Unexpected option token: \(tok)"
            r.errorHelpPath = path
            return r
        }

        if let childOpt = findChild(current.children, tok) {
            i += 1
            path.append(tok)
            current = childOpt
            continue
        }

        if !current.children.isEmpty {
            return errorResult("Unknown subcommand: \(tok)")
        }

        return finishLeaf(node: current, i: &i, argv: argv, path: path, opts: opts)
    }
}

func postParseValidate(root: CliCommand, pr: ParseResult) -> ParseResult {
    guard pr.kind == .ok else { return pr }

    var defs = root.options
    var cmds = root.children

    for seg in pr.path {
        guard let ch = findChild(cmds, seg) else {
            var r = ParseResult()
            r.kind = .error
            r.errorHelpPath = pr.path
            r.errorMsg = "Internal path error"
            return r
        }
        defs.append(contentsOf: ch.options)
        defs.append(contentsOf: ch.positionals)
        cmds = ch.children
    }

    for (k, v) in pr.opts {
        guard let d = findOptionByName(defs, k) else {
            var r = ParseResult()
            r.kind = .error
            r.errorHelpPath = pr.path
            r.errorMsg = "Unknown option key: \(k)"
            return r
        }
        if d.kind == .number {
            if !fullStringIsDouble(v) {
                var r = ParseResult()
                r.kind = .error
                r.errorHelpPath = pr.path
                r.errorMsg = "Invalid number for option --\(k): \(v)"
                return r
            }
        }
    }
    return pr
}

// MARK: - Schema validation

private func checkOptions(_ defs: [CliOption], scope: String) throws {
    var seenShorts = Set<Character>()
    for d in defs {
        guard let s = d.shortName else { continue }
        if d.positional {
            throw CliSchemaValidationError.message(
                "Positional arguments must not define short aliases: \(scope)/\(d.name)"
            )
        }
        if s == "h" {
            throw CliSchemaValidationError.message(
                "Short alias -h is reserved for help: \(scope)/\(d.name)"
            )
        }
        if seenShorts.contains(s) {
            throw CliSchemaValidationError.message(
                "Duplicate short alias -\(s) in scope \(scope)"
            )
        }
        seenShorts.insert(s)
    }
}

private func checkPositionals(_ defs: [CliOption], scope: String) throws {
    let pos = defs.filter(\.positional)
    for (idx, d) in pos.enumerated() {
        if d.argMin < 0 {
            throw CliSchemaValidationError.message(
                "argMin must be >= 0 for positional \(scope)/\(d.name)"
            )
        }
        if d.argMax < 0 {
            throw CliSchemaValidationError.message(
                "argMax must be >= 0 (use 0 for unlimited) for positional \(scope)/\(d.name)"
            )
        }
        if d.argMax > 0 && d.argMin > d.argMax {
            throw CliSchemaValidationError.message(
                "argMin must not exceed argMax for positional \(scope)/\(d.name)"
            )
        }
        if idx + 1 < pos.count && d.argMax == 0 {
            throw CliSchemaValidationError.message(
                "Unlimited positional (argMax == 0) must be last in scope \(scope)"
            )
        }
    }
    var sawOptional = false
    for d in pos {
        if d.argMin == 0 {
            sawOptional = true
        } else if sawOptional {
            throw CliSchemaValidationError.message(
                "Required positional after optional in scope \(scope)"
            )
        }
    }
}

private func walkCommand(_ cmd: CliCommand) throws {
    if cmd.fallbackCommand != nil {
        throw CliSchemaValidationError.message(
            "Fallback is only supported on the program root (not on \(cmd.name))"
        )
    }
    if cmd.fallbackMode != .missingOnly {
        throw CliSchemaValidationError.message(
            "fallbackMode may only be set on the program root (not on \(cmd.name))"
        )
    }

    if !cmd.children.isEmpty {
        if cmd.handler != nil {
            throw CliSchemaValidationError.message(
                "Routing command must not set handler: \(cmd.name)"
            )
        }
    } else {
        if cmd.handler == nil {
            throw CliSchemaValidationError.message(
                "Leaf command requires handler: \(cmd.name)"
            )
        }
    }
    try checkOptions(cmd.options, scope: cmd.name)
    try checkPositionals(cmd.positionals, scope: cmd.name)
    try checkOptions(cmd.positionals, scope: cmd.name)

    var childNames = Set<String>()
    for ch in cmd.children {
        if childNames.contains(ch.name) {
            throw CliSchemaValidationError.message(
                "Duplicate child command name: \(cmd.name)/\(ch.name)"
            )
        }
        childNames.insert(ch.name)
        try walkCommand(ch)
    }
}

func cliValidateRoot(_ root: CliCommand) throws {
    if root.handler != nil {
        throw CliSchemaValidationError.message(
            "Program root must not set handler (use children for subcommands)"
        )
    }
    if !root.positionals.isEmpty {
        throw CliSchemaValidationError.message(
            "Program root must not declare positionals"
        )
    }

    if root.children.contains(where: { $0.name == "completion" }) {
        throw CliSchemaValidationError.message("Reserved command name: completion")
    }
    if root.options.contains(where: { $0.name == "generate-completion-script" }) {
        throw CliSchemaValidationError.message(
            "Reserved root option name: generate-completion-script")
    }

    if root.fallbackCommand == nil {
        if root.fallbackMode == .missingOrUnknown || root.fallbackMode == .unknownOnly {
            throw CliSchemaValidationError.message("this fallbackMode requires fallbackCommand")
        }
    }
    if let want = root.fallbackCommand {
        guard root.children.contains(where: { $0.name == want }) else {
            throw CliSchemaValidationError.message(
                "fallbackCommand not found in top-level children: \(want)")
        }
    }

    var topNames = Set<String>()
    for c in root.children {
        if topNames.contains(c.name) {
            throw CliSchemaValidationError.message(
                "Duplicate top-level command name: \(c.name)"
            )
        }
        topNames.insert(c.name)
        try walkCommand(c)
    }
}
