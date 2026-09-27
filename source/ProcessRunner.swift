import Foundation
import Darwin

struct CommandResult {
    let status: Int32
    let output: String
}

// A file-backed capture cannot deadlock on a full pipe. Only our child is terminated.
func runBoundedCommand(_ path: String, _ arguments: [String], timeout: TimeInterval = 5) -> CommandResult {
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("fixclipboard-command-" + UUID().uuidString)
    guard FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]),
          let output = try? FileHandle(forWritingTo: outputURL) else {
        return CommandResult(status: -1, output: "无法创建临时输出文件")
    }
    defer { try? output.close(); try? FileManager.default.removeItem(at: outputURL) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do {
        try process.run()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            return CommandResult(status: -2, output: "操作超时，请稍后重试")
        }
        let reader = try FileHandle(forReadingFrom: outputURL)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: 256 * 1024) ?? Data()
        return CommandResult(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "无法解析命令输出")
    } catch { return CommandResult(status: -1, output: "无法执行操作：" + error.localizedDescription) }
}

func runCommand(_ path: String, _ arguments: [String]) -> CommandResult {
    runBoundedCommand(path, arguments)
}
