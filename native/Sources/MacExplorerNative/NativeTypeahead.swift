import AppKit
import ExplorerCore

public struct TypeaheadCandidate: Sendable {
  public let row: Int
  public let entry: FileEntry
  public let displayName: String
  public let normalizedName: String

  public init(row: Int, entry: FileEntry, displayName: String) {
    self.row = row
    self.entry = entry
    self.displayName = displayName
    self.normalizedName = displayName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }
}

@MainActor
public final class NativeTypeahead {
  public var buffer = ""
  public var lastInputTime: TimeInterval = 0
  public let timeout: TimeInterval

  public init(timeout: TimeInterval = 0.85) {
    self.timeout = timeout
  }

  public func reset() {
    buffer = ""
    lastInputTime = 0
  }

  public func matchKey(
    _ event: NSEvent,
    candidates: [TypeaheadCandidate],
    selectedPaths: Set<String>
  ) -> (row: Int, entry: FileEntry)? {
    guard !candidates.isEmpty else { return nil }
    guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
    guard let chars = event.characters, !chars.isEmpty else { return nil }
    let scalar = chars.unicodeScalars.first!
    guard scalar.value >= 32, scalar.value != 127, !(0xF700...0xF8FF).contains(scalar.value) else { return nil }

    let typedChar = String(chars)
    let now = Date().timeIntervalSinceReferenceDate
    let isExpired = (now - lastInputTime) > timeout

    // Space key (keyCode 49): only accepted if continuing an active multi-character buffer
    if event.keyCode == 49 {
      guard !buffer.isEmpty, !isExpired else { return nil }
    }

    let normalizedChar = typedChar.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let selectedCandidateIndex = candidates.firstIndex(where: { selectedPaths.contains($0.entry.id) })

    // Check if user is typing the same character to cycle:
    // Either repeating the single-character buffer within timeout, OR pressing the character
    // that matches the already selected item's starting character.
    let isSameCharAsBuffer = !isExpired && buffer.count == 1 && buffer.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalizedChar
    let currentMatchesChar = selectedCandidateIndex.map { candidates[$0].normalizedName.hasPrefix(normalizedChar) } == true
    let isCycling = isSameCharAsBuffer || (isExpired && currentMatchesChar)

    if isCycling {
      let matches = candidates.enumerated().filter { $0.element.normalizedName.hasPrefix(normalizedChar) }
      guard !matches.isEmpty else { return nil }

      let target: TypeaheadCandidate
      if let currentIndex = selectedCandidateIndex,
         let nextMatch = matches.first(where: { $0.offset > currentIndex }) {
        target = nextMatch.element
      } else {
        target = matches.first!.element
      }

      buffer = typedChar
      lastInputTime = now
      return (target.row, target.entry)
    }

    // If typing within timeout and not cycling, try multi-character prefix
    if !isExpired && !buffer.isEmpty {
      let newBuffer = buffer + typedChar
      let normalizedNew = newBuffer.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      if let match = candidates.first(where: { $0.normalizedName.hasPrefix(normalizedNew) }) {
        buffer = newBuffer
        lastInputTime = now
        return (match.row, match.entry)
      }
    }

    // Fresh match: match the typed character from the top
    let matches = candidates.enumerated().filter { $0.element.normalizedName.hasPrefix(normalizedChar) }
    guard let first = matches.first else {
      reset()
      return nil
    }

    buffer = typedChar
    lastInputTime = now
    return (first.element.row, first.element.entry)
  }
}
