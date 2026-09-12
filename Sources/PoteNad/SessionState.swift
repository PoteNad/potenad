import AppKit
import TextCore

struct StoredSession: Codable {
  struct WindowGroup: Codable {
    var documents: [Document]
    var selectedDocument: Int
    var frame: String
  }

  struct Document: Codable {
    var text: String
    var filePath: String?
    var encoding: String
    var lineEnding: String
    var hasMixedLineEndings: Bool
    var wasEdited: Bool
  }

  var windowGroups: [WindowGroup]
}

enum SessionState {
  private static var url: URL {
    if let path = ProcessInfo.processInfo.environment["POTENAD_SESSION_STORE"], !path.isEmpty {
      return URL(fileURLWithPath: path)
    }
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return root.appendingPathComponent("PoteNad", isDirectory: true)
      .appendingPathComponent("Previous Session.json")
  }

  static func save(_ session: StoredSession) throws {
    let data = try JSONEncoder().encode(session)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  static func loadAndRemove() throws -> StoredSession? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    let session = try JSONDecoder().decode(StoredSession.self, from: data)
    try FileManager.default.removeItem(at: url)
    return session
  }

  static func remove() { try? FileManager.default.removeItem(at: url) }
}
