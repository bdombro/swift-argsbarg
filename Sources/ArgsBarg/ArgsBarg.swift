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

/// Merges the caller's program root with the reserved `completion` / `{bash,zsh}` subtree.
internal func cliRootMergedWithBuiltins(_ root: CliCommand) -> CliCommand {
    var merged = root
    merged.children.append(cliBuiltinCompletionGroup(appName: root.name))
    return merged
}


/// zsh completion file basename: leading `_`, hyphens in `appName` become `_` (matches common `_myapp` naming).
private func zshCompletionUnderscoreFileName(appName: String) -> String {
    let prefixed = "_" + appName
    return String(prefixed.map { $0 == "-" ? Character("_") : $0 })
}


/// Builds the static `completion` / `bash` / `zsh` subtree used for shell integration.
private func cliBuiltinCompletionGroup(appName: String) -> CliCommand {
    let zshFile = zshCompletionUnderscoreFileName(appName: appName)
    return CliCommand(
        name: "completion",
        description: "Generate the autocompletion script for shells.",
        children: [
            CliCommand(
                name: "bash",
                description: "Print a bash tab-completion script.",
                notes: """
                    Output is the whole script.

                    Pipe it to a file, or feed it straight into your shell.

                    To keep it across restarts, save it and source that file from ~/.bashrc. For example:

                      \(appName) completion bash > ~/.bash_completion.d/\(appName)
                      echo 'source ~/.bash_completion.d/\(appName)' >> ~/.bashrc

                    To try it only in this session (nothing written to disk):

                      source <(\(appName) completion bash)
                    """,
                handler: { _ in }
            ),
            CliCommand(
                name: "zsh",
                description: "Print a zsh tab-completion script.",
                notes: """
                    Output is the whole script.

                    Two common ways to use it:

                    Quick setup — one line for ~/.zshrc (no extra file, no fpath changes). Runs \(appName) once when the shell reads your config:

                      eval "$(\(appName) completion zsh)"

                    Same idea without eval (process substitution):

                      source <(\(appName) completion zsh)

                    File-based setup — save the script and let zsh load it from disk (skip this if you do not want \(appName) to run during shell startup):

                      \(appName) completion zsh > ~/.zsh/completions/\(zshFile)

                    Then in ~/.zshrc, before compinit:

                      fpath=(~/.zsh/completions $fpath)
                      autoload -Uz compinit && compinit
                    """,
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

        if pr.path == ["completion", "bash"] {
            print(completionBashScript(schema: merged), terminator: "")
            exit(0)
        }
        if pr.path == ["completion", "zsh"] {
            print(completionZshScript(schema: merged), terminator: "")
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

