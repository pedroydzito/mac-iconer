import Foundation

enum Shell {
    struct Failure: LocalizedError {
        let command: String
        let output: String
        var errorDescription: String? { "Falha ao executar \(command): \(output)" }
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failure(command: (launchPath as NSString).lastPathComponent, output: output)
        }
        return output
    }
}
