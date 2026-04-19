import ArgsBarg
import Foundation

cliRun(
    CliCommand(
        name: "nesteddemo",
        description: "Nested groups demo.",
        children: [
            CliCommand(
                name: "stat",
                description: "File metadata.",
                children: [
                    CliCommand(
                        name: "owner",
                        description: "Ownership helpers.",
                        children: [
                            CliCommand(
                                name: "lookup",
                                description: "Resolve owner info.",
                                options: [
                                    CliOption(
                                        name: "user-name",
                                        description: "User to look up.",
                                        kind: .string,
                                        shortName: "u"
                                    ),
                                ],
                                positionals: [
                                    CliOption(
                                        name: "path",
                                        description: "File or directory.",
                                        kind: .string,
                                        positional: true
                                    ),
                                ],
                                handler: { ctx in
                                    let user = ctx.stringOpt("user-name") ?? "?"
                                    guard let path = ctx.args.first else {
                                        cliErrWithHelp(ctx, "Missing path.")
                                    }
                                    print("lookup user=\(user) path=\(path)")
                                }
                            )
                        ]
                    )
                ]
            ),
            CliCommand(
                name: "read",
                description: "Print the first line of each file.",
                notes: "Pass one or more file paths. {app} prints the first line of each.",
                positionals: [
                    CliOption(
                        name: "files",
                        description: "Paths to read.",
                        kind: .string,
                        positional: true,
                        argMin: 1,
                        argMax: 0
                    ),
                ],
                handler: { ctx in
                    if ctx.args.isEmpty { cliErrWithHelp(ctx, "Missing file path.") }
                    for path in ctx.args {
                        if let data = FileManager.default.contents(atPath: path),
                            let s = String(data: data, encoding: .utf8),
                            let line = s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                            .first
                        {
                            print("\(path): \(line)")
                        } else {
                            cliErrWithHelp(ctx, "Cannot open: \(path)")
                        }
                    }
                }
            ),
        ],
        fallbackCommand: "read",
        fallbackMode: .unknownOnly
    ))
