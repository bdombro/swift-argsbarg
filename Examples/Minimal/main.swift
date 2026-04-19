import ArgsBarg

cliRun(
    CliCommand(
        name: "helloapp",
        description: "Tiny demo.",
        children: [
            CliCommand(
                name: "hello",
                description: "Say hello.",
                options: [
                    CliOption(
                        name: "name",
                        description: "Who to greet.",
                        kind: .string,
                        shortName: "n"
                    ),
                    CliOption(
                        name: "verbose",
                        description: "Enable extra logging.",
                        shortName: "v"
                    ),
                ],
                handler: { ctx in
                    let name = ctx.stringOpt("name") ?? "world"
                    if ctx.flag("verbose") { print("verbose mode") }
                    print("hello \(name)")
                }
            )
        ],
        fallbackCommand: "hello",
        fallbackMode: .missingOrUnknown
    ))
