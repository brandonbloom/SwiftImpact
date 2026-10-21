import Foundation

/// Runs a command found on `PATH` in `directory`, and returns its output and error streams
/// together.
@discardableResult
func command(
    _ arguments: String..., in directory: URL, environment: [String: String] = [:]
) throws -> String {
    try command(arguments, in: directory, environment: environment)
}

@discardableResult
func command(
    _ arguments: [String], in directory: URL, environment: [String: String] = [:]
) throws -> String {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CommandError(
            arguments: arguments, status: process.terminationStatus, output: output)
    }
    return output
}

struct CommandError: Error, CustomStringConvertible {
    let arguments: [String]
    let status: Int32
    let output: String
    var description: String {
        "\(arguments.joined(separator: " ")) exited with \(status):\n\(output)"
    }
}
