import AppKit
import ExplorerCore
import UniformTypeIdentifiers

@MainActor
enum NativeTerminal {
  static let preferenceKey = "terminalApplication"
  static let applications = [("Terminal", "com.apple.Terminal"), ("Warp", "dev.warp.Warp-Stable"), ("iTerm2", "com.googlecode.iterm2"), ("Ghostty", "com.mitchellh.ghostty")]

  static func options(selected: String, lookup: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) -> [(String, String)] {
    var values = [(NL("自动选择"), "")]
    for (name, identifier) in applications {
      if lookup(identifier) != nil { values.append((name, identifier)) }
      else if selected == identifier { values.append((NL("{0}（未安装）", name), identifier)) }
    }
    if !values.contains(where: { $0.1 == selected }) { values.append((NL("所选终端不可用"), selected)) }
    return values
  }

  static func request(directory: URL, selected: String, lookup: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) throws -> (directory: URL, application: URL) {
    var isDirectory: ObjCBool = false
    guard directory.isFileURL, FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw NSError(domain: "NativeTerminal", code: 1, userInfo: [NSLocalizedDescriptionKey: NL("请选择文件夹打开终端。")])
    }
    let application: URL?
    if selected.isEmpty { application = NSWorkspace.shared.urlForApplication(toOpen: UTType.unixExecutable) }
    else {
      guard applications.contains(where: { $0.1 == selected }), let installed = lookup(selected) else {
        throw NSError(domain: "NativeTerminal", code: 2, userInfo: [NSLocalizedDescriptionKey: NL("所选终端未安装，请在设置中重新选择。")])
      }
      application = installed
    }
    guard let application else { throw NSError(domain: "NativeTerminal", code: 3, userInfo: [NSLocalizedDescriptionKey: NL("没有可用的终端应用")]) }
    return (directory, application)
  }

  static func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func isTerminalAlias(_ input: String) -> Bool {
    ["cmd", "terminal", "powershell", "wt", "bash", "zsh", "sh"].contains(input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }

  static func extractCommand(from input: String, currentDirectory: URL, home: URL) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    if lower.hasPrefix("cmd /c ") { return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
    if lower.hasPrefix("cmd /k ") { return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
    if lower.hasPrefix("cmd ") { return String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces) }

    if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || lower.hasPrefix("smb:") || lower.hasPrefix("explorer:") {
      return nil
    }

    if let resolved = try? NativeAddressPath.resolve(trimmed, current: currentDirectory, home: home),
       FileManager.default.fileExists(atPath: resolved.path) {
      return nil
    }

    let prefixes = [
      "git ", "npm ", "npx ", "pnpm ", "yarn ", "bun ", "node ", "deno ",
      "python ", "python3 ", "pip ", "pip3 ", "brew ", "cargo ", "swift ", "go ",
      "docker ", "kubectl ", "code ", "cursor ", "zed ", "curl ", "wget ",
      "ssh ", "scp ", "rsync ", "make ", "cmake ", "mkdir ", "touch ",
      "rm ", "cp ", "mv ", "cat ", "ls ", "ll", "echo ", "chmod ", "chown ",
      "open ", "vi ", "vim ", "nvim ", "nano ", "flutter ", "dart ", "adb ", "claude ", "codex "
    ]
    if prefixes.contains(where: { lower == $0.trimmingCharacters(in: .whitespaces) || lower.hasPrefix($0) }) {
      return trimmed
    }

    if trimmed.contains(" && ") || trimmed.contains(" || ") || trimmed.contains(" | ") || trimmed.contains("; ") {
      return trimmed
    }

    if let firstToken = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init),
       !firstToken.isEmpty, !firstToken.contains("/") {
      let searchPaths = (ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? [])
        + ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
      let fm = FileManager.default
      if searchPaths.contains(where: { fm.isExecutableFile(atPath: ($0 as NSString).appendingPathComponent(firstToken)) }) {
        return trimmed
      }
    }

    return nil
  }

  static func runCommand(_ command: String, in directory: URL, selected: String) throws {
    var isDir: ObjCBool = false
    let targetDir: URL
    if directory.isFileURL, FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue {
      targetDir = directory
    } else {
      targetDir = FileManager.default.homeDirectoryForCurrentUser
    }

    let req = try request(directory: targetDir, selected: selected)
    let scriptURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("mac-explorer-cmd-\(UUID().uuidString)")
      .appendingPathExtension("command")
    let content = """
    #!/bin/zsh
    rm -f -- "$0"
    cd \(shellQuoted(targetDir.path)) || exit 1
    \(command)
    exec "${SHELL:-/bin/zsh}" -l
    """
    try content.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

    let terminalApp = (selected.isEmpty || selected == "com.apple.Terminal" || selected == "com.googlecode.iterm2")
      ? req.application
      : (NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") ?? req.application)
    NSWorkspace.shared.open([scriptURL], withApplicationAt: terminalApp, configuration: NSWorkspace.OpenConfiguration()) { _, error in
      if error != nil, let fallback = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal"), fallback != terminalApp {
        NSWorkspace.shared.open([scriptURL], withApplicationAt: fallback, configuration: NSWorkspace.OpenConfiguration())
      }
    }
  }
}
