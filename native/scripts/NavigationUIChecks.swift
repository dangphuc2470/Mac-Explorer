import AppKit
import ExplorerCore

@main enum NavigationUIChecks {
  @MainActor static func main() async {
    do {
      NSApplication.shared.setActivationPolicy(.prohibited)
      NativeLanguage.load(from: URL(fileURLWithPath: CommandLine.arguments[1])); NativeLanguage.mode = "zh-CN"
      var checks: [String] = []
      checks += try await NativeNavigationStateChecks.run(showsWindows: false)
      checks += try await NativeWorkflowChecks.run(output: URL(fileURLWithPath: CommandLine.arguments[2]))
      checks += try await NativeSearchTagChecks.run()
      checks += try await NativeMemoryChecks.run()
      checks += try await NativeSidebarEjectChecks.run(output: URL(fileURLWithPath: CommandLine.arguments[2]))
      checks += try await NativeRefreshChecks.run()
      checks += try await NativeExternalOpenChecks.run()
      precondition(!NSApp.windows.contains { $0.isVisible }, "Headless checks displayed a window")
      try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: [.prettyPrinted]).write(to: URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("report.json"))
    } catch { fputs("NavigationUIChecks FAILED: \(error)\n", stderr); exit(1) }
  }
}
