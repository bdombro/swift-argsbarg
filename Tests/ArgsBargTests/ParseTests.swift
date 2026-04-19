import XCTest
@testable import ArgsBarg

final class ParseTests: XCTestCase {
    func testBundledShortPresenceFlags() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            children: [
                CliCommand(
                    name: "x",
                    description: "cmd",
                    options: [
                        CliOption(name: "a", description: "", kind: .presence, shortName: "a"),
                        CliOption(name: "b", description: "", kind: .presence, shortName: "b"),
                    ],
                    handler: { _ in }
                )
            ]
        )
        try cliValidateRoot(root)
        let pr = postParseValidate(root: root, pr: parse(root: root, argv: ["x", "-ab"]))
        XCTAssertEqual(pr.kind, .ok)
        XCTAssertEqual(pr.opts["a"], "1")
        XCTAssertEqual(pr.opts["b"], "1")
    }

    func testLongOptionEquals() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            children: [
                CliCommand(
                    name: "x",
                    description: "cmd",
                    options: [CliOption(name: "name", description: "", kind: .string)],
                    handler: { _ in }
                )
            ]
        )
        try cliValidateRoot(root)
        let pr = postParseValidate(root: root, pr: parse(root: root, argv: ["x", "--name=pat"]))
        XCTAssertEqual(pr.kind, .ok)
        XCTAssertEqual(pr.opts["name"], "pat")
    }

    func testFallbackMissingOrUnknownRootFlags() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            children: [
                CliCommand(
                    name: "hello",
                    description: "Say hi.",
                    options: [CliOption(name: "name", description: "", kind: .string)],
                    handler: { _ in }
                )
            ],
            fallbackCommand: "hello",
            fallbackMode: .missingOrUnknown
        )
        try cliValidateRoot(root)
        let pr = postParseValidate(root: root, pr: parse(root: root, argv: ["--name", "bob"]))
        XCTAssertEqual(pr.kind, .ok)
        XCTAssertEqual(pr.path, ["hello"])
        XCTAssertEqual(pr.opts["name"], "bob")
    }

    func testUnknownCommand() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            children: [CliCommand(name: "hello", description: "", handler: { _ in })]
        )
        try cliValidateRoot(root)
        let pr = parse(root: root, argv: ["nope"])
        XCTAssertEqual(pr.kind, .error)
        XCTAssertTrue(pr.errorMsg.contains("Unknown command"))
    }

    func testImplicitHelpEmpty() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            children: [CliCommand(name: "x", description: "", handler: { _ in })]
        )
        try cliValidateRoot(root)
        let pr = parse(root: root, argv: [])
        XCTAssertEqual(pr.kind, .help)
        XCTAssertFalse(pr.helpExplicit)
    }

    func testInvalidNumberPostValidate() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            children: [
                CliCommand(
                    name: "x",
                    description: "",
                    options: [CliOption(name: "n", description: "", kind: .number)],
                    handler: { _ in }
                )
            ]
        )
        try cliValidateRoot(root)
        var pr = parse(root: root, argv: ["x", "--n", "notnum"])
        pr = postParseValidate(root: root, pr: pr)
        XCTAssertEqual(pr.kind, .error)
        XCTAssertTrue(pr.errorMsg.contains("Invalid number"))
    }

    func testCompletionReservedName() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            children: [CliCommand(name: "completion", description: "", handler: { _ in })]
        )
        XCTAssertThrowsError(try cliValidateRoot(root)) { err in
            XCTAssertTrue(String(describing: err).contains("Reserved command name"))
        }
    }

    func testCompletionReservedGenerateScriptOption() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            options: [
                CliOption(name: "generate-completion-script", description: "oops", kind: .string),
            ],
            children: [CliCommand(name: "hello", description: "", handler: { _ in })]
        )
        XCTAssertThrowsError(try cliValidateRoot(root)) { err in
            XCTAssertTrue(String(describing: err).contains("Reserved root option name"))
        }
    }

    func testCompletionBashScriptContainsAppName() throws {
        let root = CliCommand(
            name: "myapp",
            description: "Test",
            children: [CliCommand(name: "hello", description: "", handler: { _ in })]
        )
        try cliValidateRoot(root)
        let merged = cliRootMergedWithBuiltins(root)
        let script = completionBashScript(schema: merged)
        XCTAssertTrue(script.contains("# Generated bash completion for myapp."))
        XCTAssertTrue(script.contains("complete -F _myapp myapp"))
        XCTAssertTrue(script.contains("'hello'"))
    }

    func testCompletionZshScriptContainsAppName() throws {
        let root = CliCommand(
            name: "myapp",
            description: "Test",
            children: [CliCommand(name: "hello", description: "", handler: { _ in })]
        )
        try cliValidateRoot(root)
        let merged = cliRootMergedWithBuiltins(root)
        let script = completionZshScript(schema: merged)
        XCTAssertTrue(script.hasPrefix("#compdef myapp"))
        XCTAssertTrue(script.contains("compdef _myapp myapp"))
        XCTAssertTrue(script.contains("hello"))
    }

    func testRootMustNotHaveHandler() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            children: [CliCommand(name: "x", description: "", handler: { _ in })],
            handler: { _ in }
        )
        XCTAssertThrowsError(try cliValidateRoot(root)) { err in
            XCTAssertTrue(String(describing: err).contains("Program root must not set handler"))
        }
    }

    func testRootMustNotHavePositionals() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            positionals: [
                CliOption(name: "p", description: "", kind: .string, positional: true),
            ],
            children: [CliCommand(name: "x", description: "", handler: { _ in })]
        )
        XCTAssertThrowsError(try cliValidateRoot(root)) { err in
            XCTAssertTrue(String(describing: err).contains("Program root must not declare positionals"))
        }
    }

    func testNestedFallbackRejected() throws {
        let root = CliCommand(
            name: "app",
            description: "",
            children: [
                CliCommand(
                    name: "g",
                    description: "group",
                    children: [
                        CliCommand(name: "leaf", description: "", handler: { _ in }),
                    ],
                    fallbackCommand: "leaf",
                    fallbackMode: .missingOnly
                ),
            ]
        )
        XCTAssertThrowsError(try cliValidateRoot(root)) { err in
            XCTAssertTrue(String(describing: err).contains("Fallback is only supported on the program root"))
        }
    }
}
