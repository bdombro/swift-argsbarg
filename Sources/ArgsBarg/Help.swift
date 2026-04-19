// Help rendering: boxed usage, option tables, wrapping, and TTY-aware color.
// Matches the C++/Nim ArgsBarg layout so documentation looks consistent across ports.
// Uses terminal width from `TIOCGWINSZ` and strips ANSI when measuring visible width.

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation

/// ANSI and layout helpers for colored help text (no instances; use static methods only).
private final class TerminalStyle {
    private init() {}

    /// Concatenates prefix, body, and suffix (used for ANSI sequences).
    static func wrap(_ prefix: String, _ body: String, _ suffix: String) -> String {
        prefix + body + suffix
    }


    /// Red foreground for error strings.
    static func red(_ msg: String) -> String {
        wrap("\u{001B}[31m", msg, "\u{001B}[0m")
    }


    /// Dim gray foreground.
    static func gray(_ msg: String) -> String {
        wrap("\u{001B}[90m", msg, "\u{001B}[0m")
    }


    /// Bold (SGR 1).
    static func bold(_ msg: String) -> String {
        wrap("\u{001B}[1m", msg, "\u{001B}[0m")
    }


    /// White foreground for body text in tables.
    static func white(_ msg: String) -> String {
        wrap("\u{001B}[37m", msg, "\u{001B}[0m")
    }


    /// Bright cyan bold for option names in usage.
    static func aquaBold(_ msg: String) -> String {
        wrap("\u{001B}[96m\u{001B}[1m", msg, "\u{001B}[0m")
    }


    /// Bright green for short-option suffixes.
    static func greenBright(_ msg: String) -> String {
        wrap("\u{001B}[92m", msg, "\u{001B}[0m")
    }


    /// Gray bold for section titles inside boxes.
    static func grayBoldTitle(_ title: String) -> String {
        gray(bold(title))
    }
}

// UTF-8 rounded box drawing (matches cpp-argsbarg / nim-argsbarg)
private let kBoxTL = "\u{256D}" // ╭
private let kBoxTR = "\u{256E}" // ╮
private let kBoxV = "\u{2502}" // │
private let kBoxBL = "\u{2570}" // ╰
private let kBoxBR = "\u{256F}" // ╯
private let kBoxH = "\u{2500}" // ─

/// Returns the terminal column count for `fd`, or a sensible default when unknown.
func helpWidthFd(_ fd: Int32) -> Int {
    var w = winsize()
    if ioctl(fd, UInt(TIOCGWINSZ), &w) == 0 && w.ws_col > 0 {
        return max(40, Int(w.ws_col))
    }
    return 80
}


/// Returns whether `fd` refers to an interactive terminal (for color decisions).
func ttyFd(_ fd: Int32) -> Bool {
    isatty(fd) != 0
}


/// Counts display columns, skipping ANSI SGR sequences.
private func visibleWidth(_ s: String) -> Int {
    var w = 0
    var i = s.startIndex
    while i < s.endIndex {
        if s[i] == "\u{001B}", s.index(after: i) < s.endIndex, s[s.index(after: i)] == "[" {
            i = s.index(after: i)
            while i < s.endIndex, s[i] != "m" {
                i = s.index(after: i)
            }
            if i < s.endIndex {
                i = s.index(after: i)
            }
            continue
        }
        w += 1
        i = s.index(after: i)
    }
    return w
}


/// Repeats the horizontal box character `n` times.
private func repeatBoxH(_ n: Int) -> String {
    String(repeating: kBoxH, count: max(0, n))
}


/// Returns a string of `n` ASCII spaces.
private func spaces(_ n: Int) -> String {
    String(repeating: " ", count: max(0, n))
}


/// Right-pads `s` to `width` visible columns using spaces.
private func padVisible(_ s: String, _ width: Int) -> String {
    s + spaces(max(0, width - visibleWidth(s)))
}


/// Word-wraps one paragraph into lines of at most `width` columns (uses string length; notes are plain text).
private func wrapParagraph(_ text: String, _ width: Int) -> [String] {
    let available = max(1, width)
    var out: [String] = []
    var cur = ""
    for word in text.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
        if cur.isEmpty {
            cur = word
            continue
        }
        if cur.count + 1 + word.count <= available {
            cur += " " + word
        } else {
            out.append(cur)
            cur = word
        }
    }
    if !cur.isEmpty {
        out.append(cur)
    }
    return out
}


/// Wraps text for help boxes. Respects newline characters in the source; reflows each non-indented line as a paragraph.
/// Lines with leading whitespace are kept on one row (shell examples).
private func wrapText(_ text: String, _ width: Int) -> [String] {
    var out: [String] = []
    for line in text.components(separatedBy: "\n") {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append("")
            continue
        }
        if line.first?.isWhitespace == true {
            out.append(line)
            continue
        }
        out.append(contentsOf: wrapParagraph(line, width))
    }
    if out.isEmpty {
        out.append("")
    }
    return out
}


/// Suffix for `--name` in usage when the option takes a value.
private func optKindLabel(_ k: CliOptionKind) -> String {
    switch k {
    case .presence: return ""
    case .number: return " <number>"
    case .string: return " <string>"
    }
}


/// Formats one option or positional for tables and usage lines, optionally with color.
func cliOptionLabel(_ o: CliOption, color: Bool) -> String {
    if o.positional {
        if o.argMax == 1 {
            return o.argMin == 0 ? "[\(o.name)]" : "<\(o.name)>"
        }
        return o.argMin == 0 ? "[\(o.name)...]" : "<\(o.name)...>"
    }
    var r = "--\(o.name)" + optKindLabel(o.kind)
    if let s = o.shortName {
        r += ", -\(s)"
    }
    if !color {
        return r
    }
    if let range = r.range(of: ", ") {
        let left = String(r[..<range.upperBound])
        let right = String(r[range.upperBound...])
        return TerminalStyle.aquaBold(left) + " " + TerminalStyle.greenBright(String(right))
    }
    return TerminalStyle.aquaBold(r)
}


/// One row in a help table (label column and description).
private struct HelpRow {
    var label: String
    var description: String
}


/// Draws a titled box around free-form lines of text.
private func renderTextBox(title: String, lines: [String], hw: Int, color: Bool) -> [String] {
    guard !lines.isEmpty else { return [] }

    let titleLead: String
    if color {
        titleLead =
            TerminalStyle.gray(kBoxH + " ")
            + TerminalStyle.grayBoldTitle(title)
            + TerminalStyle.gray(" ")
    } else {
        titleLead = kBoxH + " " + title + " "
    }

    var contentWidth = visibleWidth(titleLead) + 1
    for line in lines {
        contentWidth = max(contentWidth, visibleWidth(line))
    }
    contentWidth = max(hw - 2, contentWidth)
    contentWidth = min(contentWidth, hw - 4)

    let borderWidth = contentWidth + 2
    let headerFill = max(1, borderWidth - visibleWidth(titleLead))

    var out: [String] = []
    out.append(
        (color ? TerminalStyle.gray(kBoxTL) : kBoxTL)
            + titleLead
            + (color ? TerminalStyle.gray(repeatBoxH(headerFill) + kBoxTR) : repeatBoxH(headerFill) + kBoxTR)
    )
    for line in lines {
        let padded = padVisible(line, contentWidth)
        out.append(
            (color ? TerminalStyle.gray(kBoxV) : kBoxV) + " " + padded + " "
                + (color ? TerminalStyle.gray(kBoxV) : kBoxV)
        )
    }
    out.append(
        (color ? TerminalStyle.gray(kBoxBL + repeatBoxH(borderWidth) + kBoxBR) : kBoxBL + repeatBoxH(borderWidth) + kBoxBR)
    )
    return out
}


/// Draws a two-column table (label + wrapped description) inside a rounded box.
private func renderTableBox(title: String, rows: [HelpRow], hw: Int, color: Bool) -> [String] {
    guard !rows.isEmpty else { return [] }

    var labelWidth = 0
    for row in rows {
        labelWidth = max(labelWidth, visibleWidth(row.label))
    }

    let titleChunk = kBoxH + " " + title + " "
    let minimumContentWidth = max(
        visibleWidth(titleChunk) + 1,
        labelWidth + 2 + 18
    )
    var contentWidth = max(hw - 2, minimumContentWidth)
    let descWidth = max(1, contentWidth - labelWidth - 2)

    var bodyLines: [String] = []
    for row in rows {
        let wrapped = wrapText(row.description, descWidth)
        let first =
            row.label + spaces(labelWidth - visibleWidth(row.label)) + "  "
            + (color ? TerminalStyle.white(wrapped[0]) : wrapped[0])
        bodyLines.append(first)
        for idx in 1 ..< wrapped.count {
            let pad = color ? TerminalStyle.gray(spaces(labelWidth)) : spaces(labelWidth)
            bodyLines.append(pad + "  " + (color ? TerminalStyle.white(wrapped[idx]) : wrapped[idx]))
        }
    }

    var titleLead: String
    if color {
        titleLead =
            TerminalStyle.gray(kBoxH + " ")
            + TerminalStyle.grayBoldTitle(title)
            + TerminalStyle.gray(" ")
    } else {
        titleLead = kBoxH + " " + title + " "
    }

    contentWidth = max(contentWidth, visibleWidth(titleLead) + 1)
    for line in bodyLines {
        contentWidth = max(contentWidth, visibleWidth(line))
    }
    contentWidth = min(contentWidth, hw - 4)

    let borderWidth = contentWidth + 2
    let headerFill = max(1, borderWidth - visibleWidth(titleLead))

    var out: [String] = []
    out.append(
        (color ? TerminalStyle.gray(kBoxTL) : kBoxTL)
            + titleLead
            + (color ? TerminalStyle.gray(repeatBoxH(headerFill) + kBoxTR) : repeatBoxH(headerFill) + kBoxTR)
    )
    for line in bodyLines {
        let padded = padVisible(line, contentWidth)
        out.append(
            (color ? TerminalStyle.gray(kBoxV) : kBoxV) + " " + padded + " "
                + (color ? TerminalStyle.gray(kBoxV) : kBoxV)
        )
    }
    out.append(
        (color ? TerminalStyle.gray(kBoxBL + repeatBoxH(borderWidth) + kBoxBR) : kBoxBL + repeatBoxH(borderWidth) + kBoxBR)
    )
    return out
}


/// Builds one or more usage synopsis lines for the current help path.
private func usageLines(
    appName: String,
    helpPath: [String],
    hasCommands: Bool,
    hasArgs: Bool,
    color: Bool
) -> [String] {
    var fullPath = appName
    for seg in helpPath {
        fullPath += " "
        fullPath += seg
    }
    let usageOpts = color ? TerminalStyle.aquaBold("[OPTIONS]") : "[OPTIONS]"
    let usageCmd = color ? TerminalStyle.aquaBold("COMMAND") : "COMMAND"
    let usageArgs = color ? TerminalStyle.aquaBold("[ARGS]...") : "[ARGS]..."

    var out: [String] = []
    if helpPath.isEmpty {
        if hasCommands {
            out.append(fullPath + " " + usageOpts + " " + usageCmd + " " + usageArgs)
        } else {
            out.append(fullPath + " " + usageOpts)
        }
        return out
    }
    out.append(fullPath + " " + usageOpts + (hasArgs ? (" " + usageArgs) : ""))
    if hasCommands {
        out.append(fullPath + " " + usageCmd + " " + usageArgs)
    }
    return out
}


/// Table rows for non-positional options, including implicit `--help` / `-h`.
private func rowsForOptions(_ defs: [CliOption], color: Bool) -> [HelpRow] {
    var rows: [HelpRow] = []
    let helpLabel =
        color
        ? TerminalStyle.aquaBold("--help, ")
            + TerminalStyle.greenBright("-h")
        : "--help, -h"
    rows.append(HelpRow(label: helpLabel, description: "Show help for this command."))
    for o in defs where !o.positional {
        rows.append(HelpRow(label: cliOptionLabel(o, color: color), description: o.description))
    }
    return rows
}


/// Table rows for positional arguments at the current command.
private func rowsForPositionals(_ defs: [CliOption], color: Bool) -> [HelpRow] {
    defs.filter(\.positional).map { HelpRow(label: cliOptionLabel($0, color: color), description: $0.description) }
}


/// Table rows for child subcommands, sorted by name.
private func rowsForSubcommands(_ cmds: [CliCommand]) -> [HelpRow] {
    cmds.sorted { $0.name < $1.name }.map { HelpRow(label: $0.name, description: $0.description) }
}


/// Joins lines with a separator (usually newline) for embedding box output in larger strings.
private func joinLines(_ lines: [String], _ sep: String) -> String {
    lines.joined(separator: sep)
}


/// Renders full help for the program root or a nested command to stdout or stderr.
public func cliHelpRender(schema: CliCommand, helpPath: [String], useStderr: Bool) -> String {
    let fd: Int32 = useStderr ? STDERR_FILENO : STDOUT_FILENO
    let hw = helpWidthFd(fd)
    let color = ttyFd(fd)

    if helpPath.isEmpty {
        var lines: [String] = []
        lines.append("")
        if !schema.description.isEmpty {
            lines.append(color ? TerminalStyle.white(schema.description) : schema.description)
            lines.append("")
        }
        lines.append(
            joinLines(
                renderTextBox(
                    title: "Usage",
                    lines: usageLines(
                        appName: schema.name,
                        helpPath: helpPath,
                        hasCommands: !schema.children.isEmpty,
                        hasArgs: false,
                        color: color
                    ),
                    hw: hw,
                    color: color
                ),
                "\n"
            )
        )
        let optBox = renderTableBox(title: "Options", rows: rowsForOptions(schema.options, color: color), hw: hw, color: color)
        if !optBox.isEmpty {
            lines.append("")
            lines.append(joinLines(optBox, "\n"))
        }
        if !schema.children.isEmpty {
            lines.append("")
            lines.append(
                joinLines(
                    renderTableBox(title: "Commands", rows: rowsForSubcommands(schema.children), hw: hw, color: color),
                    "\n"
                )
            )
        }
        return joinLines(lines, "\n") + "\n\n"
    }

    var layer = schema.children
    var node: CliCommand?
    for seg in helpPath {
        guard let ch = findChild(layer, seg) else {
            return (color ? TerminalStyle.red("Unknown help path.") : "Unknown help path.") + "\n"
        }
        node = ch
        layer = ch.children
    }
    guard let n = node else {
        return (color ? TerminalStyle.red("Unknown help path.") : "Unknown help path.") + "\n"
    }

    var lines: [String] = []
    lines.append("")
    if !n.description.isEmpty {
        lines.append(color ? TerminalStyle.white(n.description) : n.description)
        lines.append("")
    }
    lines.append(
        joinLines(
            renderTextBox(
                title: "Usage",
                lines: usageLines(
                    appName: schema.name,
                    helpPath: helpPath,
                    hasCommands: !n.children.isEmpty,
                    hasArgs: !n.positionals.isEmpty,
                    color: color
                ),
                hw: hw,
                color: color
            ),
            "\n"
        )
    )

    let optBox = renderTableBox(title: "Options", rows: rowsForOptions(n.options, color: color), hw: hw, color: color)
    if !optBox.isEmpty {
        lines.append("")
        lines.append(joinLines(optBox, "\n"))
    }

    let posBox = renderTableBox(
        title: "Arguments",
        rows: rowsForPositionals(n.positionals, color: color),
        hw: hw,
        color: color
    )
    if !posBox.isEmpty {
        lines.append("")
        lines.append(joinLines(posBox, "\n"))
    }

    let subBox = renderTableBox(title: "Subcommands", rows: rowsForSubcommands(n.children), hw: hw, color: color)
    if !subBox.isEmpty {
        lines.append("")
        lines.append(joinLines(subBox, "\n"))
    }

    if !n.notes.isEmpty {
        var resolved = n.notes
        while let r = resolved.range(of: "{app}") {
            resolved.replaceSubrange(r, with: schema.name)
        }
        lines.append("")
        lines.append(
            joinLines(
                renderTextBox(title: "Notes", lines: wrapText(resolved, hw - 4), hw: hw, color: color),
                "\n"
            )
        )
    }

    return joinLines(lines, "\n") + "\n\n"
}
