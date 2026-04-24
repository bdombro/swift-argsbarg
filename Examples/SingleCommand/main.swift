import Foundation
import ArgsBarg

let cli = CliCommand(
    name: "ArgsBargSingleCommand",
    description: "A simple single-command CLI.",
    options: [
        CliOption(
            name: "verbose",
            description: "Enable verbose output.",
            shortName: "v"
        )
    ],
    positionals: [
        CliOption(
            name: "target",
            description: "The target file or directory.",
            positional: true
        )
    ],
    handler: { ctx in
        let target = ctx.args[0]
        let verbose = ctx.flag("verbose")
        print("Running single-command CLI...")
        print("Target: \(target)")
        print("Verbose: \(verbose)")
    }
)

cliRun(cli)
