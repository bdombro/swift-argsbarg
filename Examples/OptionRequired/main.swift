import Foundation
import ArgsBarg

let cli = CliCommand(
    name: "ArgsBargOptionRequired",
    description: "Demo of a required option.",
    children: [
        CliCommand(
            name: "run",
            description: "Run the demo.",
            options: [
                CliOption(
                    name: "requiredAlways",
                    description: "Always required string option.",
                    kind: .string,
                    shortName: "a",
                    required: true
                ),
                CliOption(
                    name: "optional",
                    description: "optional string option.",
                    kind: .string,
                    shortName: "o"
                )
            ],
            handler: { ctx in
                let requiredAlways = ctx.reqStringOpt("requiredAlways")
                let optional = ctx.stringOpt("optional") ?? "valueWhenOmitted"
                print("requiredAlways: \(requiredAlways)")
                print("optional: \(optional)")
            }
        )
    ],
    fallbackCommand: "run",
    fallbackMode: .missingOrUnknown
)

cliRun(cli)
