// ArgsBarg entrypoint: single-call CLI execution from a declarative command tree.
// Apps should not reimplement argv routing; this module validates the schema, parses flags,
// renders help, and dispatches to the correct leaf handler or built-in completion tooling.
// Composes the user's root command with reserved completion commands, then runs parse → validate → act.

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation

/// Library version (semver-style).
public let cliArgsBargVersion = "0.1.0"

/// Merges the caller's program root with reserved completion commands and the completion-script option.
internal func cliRootMergedWithBuiltins(_ root: CliCommand) -> CliCommand {
    var merged = root
    merged.children.append(cliBuiltinCompletionGroup())
    merged.options.append(
        CliOption(
            name: "generate-completion-script",
            description: "Print a shell completion script and exit (bash or zsh).",
            kind: .string
        ))
    return merged
}


/// Builds the static `completion` / `bash` / `zsh` subtree used for shell integration.
private func cliBuiltinCompletionGroup() -> CliCommand {
    CliCommand(
        name: "completion",
        description: "Generate the autocompletion script for shells.",
        children: [
            CliCommand(
                name: "bash",
                description: "Generate the autocompletion script for bash.",
                notes: "Writes the completion script to stdout.\nSource it from ~/.bashrc.",
                handler: { _ in }
            ),
            CliCommand(
                name: "zsh",
                description: "Generate the autocompletion script for zsh.",
                notes:
                    "Without --print, installs to ~/.zsh/completions/_{app}. Use --print for stdout.",
                options: [
                    CliOption(
                        name: "print",
                        description: "Print script to stdout instead of installing."
                    )
                ],
                handler: { _ in }
            ),
        ]
    )
}

/// Validates the schema, parses argv, prints help or errors, runs completion or the leaf handler, then exits.
public func cliRun(_ root: CliCommand) -> Never {
    do {
        try cliValidateRoot(root)
    } catch let CliSchemaValidationError.message(msg) {
        FileHandle.standardError.write(Data("\(msg)\n".utf8))
        exit(1)
    } catch {
        FileHandle.standardError.write(Data("Invalid CLI definition.\n".utf8))
        exit(1)
    }

    let merged = cliRootMergedWithBuiltins(root)
    let argv = Array(CommandLine.arguments.dropFirst())
    var pr = parse(root: merged, argv: argv)
    pr = postParseValidate(root: merged, pr: pr)

    switch pr.kind {
    case .help:
        print(
            cliHelpRender(schema: merged, helpPath: pr.helpPath, useStderr: false), terminator: "")
        exit(pr.helpExplicit ? 0 : 1)

    case .error:
        let color = ttyFd(STDERR_FILENO)
        let line = color ? cliStyleRed(pr.errorMsg) : pr.errorMsg
        FileHandle.standardError.write(Data("\(line)\n".utf8))
        FileHandle.standardError.write(
            Data(
                cliHelpRender(schema: merged, helpPath: pr.errorHelpPath, useStderr: true).utf8)
        )
        exit(1)

    case .ok:
        guard !pr.path.isEmpty else {
            FileHandle.standardError.write(Data("Internal error: empty path.\n".utf8))
            exit(1)
        }

        if let shell = pr.opts["generate-completion-script"] {
            switch shell {
            case "bash":
                print(completionBashScript(schema: merged), terminator: "")
                exit(0)
            case "zsh":
                completionZshInstallOrPrint(schema: merged, printOnly: true)
                exit(0)
            default:
                let color = ttyFd(STDERR_FILENO)
                let msg =
                    "Unknown shell '\(shell)' for --generate-completion-script. Use bash or zsh."
                FileHandle.standardError.write(
                    Data("\(color ? cliStyleRed(msg) : msg)\n".utf8))
                exit(1)
            }
        }

        if pr.path == ["completion", "bash"] {
            print(completionBashScript(schema: merged), terminator: "")
            exit(0)
        }
        if pr.path == ["completion", "zsh"] {
            completionZshInstallOrPrint(schema: merged, printOnly: pr.opts["print"] != nil)
            exit(0)
        }

        var layer = merged.children
        var leaf: CliCommand?
        for seg in pr.path {
            guard let n = findChild(layer, seg) else {
                FileHandle.standardError.write(Data("Internal error: missing handler for path.\n".utf8))
                exit(1)
            }
            leaf = n
            layer = n.children
        }
        guard let l = leaf, let handler = l.handler else {
            FileHandle.standardError.write(Data("Internal error: missing handler for path.\n".utf8))
            exit(1)
        }

        let ctx = CliContext(
            appName: merged.name,
            commandPath: pr.path,
            args: pr.args,
            opts: pr.opts,
            schema: merged
        )
        handler(ctx)
        exit(0)
    }
}


/// Wraps a message in ANSI red for terminal error lines when stderr is a TTY.
private func cliStyleRed(_ msg: String) -> String {
    "\u{001B}[31m\(msg)\u{001B}[0m"
}


/// Prints a red error line and contextual help on stderr, then exits with status 1.
public func cliErrWithHelp(_ ctx: CliContext, _ msg: String) -> Never {
    let color = ttyFd(STDERR_FILENO)
    let line = color ? cliStyleRed(msg) : msg
    FileHandle.standardError.write(Data("\(line)\n".utf8))
    FileHandle.standardError.write(
        Data(cliHelpRender(schema: ctx.schema, helpPath: ctx.commandPath, useStderr: true).utf8)
    )
    exit(1)
}

