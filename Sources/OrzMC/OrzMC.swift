import ConsoleKit
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct OrzMC {
    static func main() async {
        let console = Terminal()
        let input = CommandInput(arguments: CommandLine.arguments)
        let context = CommandContext(console: console, input: input)
        do {
            try await console.run(CommandGroup(), with: context)
        } catch {
            // B11：归一化用户可读信息到 stderr，退出码 1（不裸抛底层异常）。
            let message = ErrorPresentation.message(for: error)
            FileHandle.standardError.write(Data("错误：\(message)\n".utf8))
            exit(1)
        }
    }
}
