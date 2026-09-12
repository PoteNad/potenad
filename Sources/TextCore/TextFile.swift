import Foundation

public enum TextEncoding: String, CaseIterable, Sendable {
  case utf8
  case utf8BOM
  case utf16LittleEndian
  case utf16BigEndian
  case windows1252
  case macOSRoman

  public var displayName: String {
    switch self {
    case .utf8: "UTF-8"
    case .utf8BOM: "UTF-8 with BOM"
    case .utf16LittleEndian: "UTF-16 LE"
    case .utf16BigEndian: "UTF-16 BE"
    case .windows1252: "Western (Windows 1252)"
    case .macOSRoman: "Western (Mac OS Roman)"
    }
  }

  fileprivate var foundationEncoding: String.Encoding {
    switch self {
    case .utf8, .utf8BOM: .utf8
    case .utf16LittleEndian: .utf16LittleEndian
    case .utf16BigEndian: .utf16BigEndian
    case .windows1252: .windowsCP1252
    case .macOSRoman: .macOSRoman
    }
  }
}

public enum LineEnding: String, CaseIterable, Sendable {
  case lf
  case crlf
  case cr

  public var displayName: String { rawValue.uppercased() }

  fileprivate var characters: String {
    switch self {
    case .lf: "\n"
    case .crlf: "\r\n"
    case .cr: "\r"
    }
  }
}

public struct TextFile: Sendable {
  public var text: String
  public var encoding: TextEncoding
  public var lineEnding: LineEnding
  public var hasMixedLineEndings: Bool

  public init(
    text: String = "", encoding: TextEncoding = .utf8, lineEnding: LineEnding = .lf,
    hasMixedLineEndings: Bool = false
  ) {
    self.text = Self.normalize(text)
    self.encoding = encoding
    self.lineEnding = lineEnding
    self.hasMixedLineEndings = hasMixedLineEndings
  }

  public init(data: Data, encoding requestedEncoding: TextEncoding? = nil) throws {
    let decoded = try Self.decode(data, requestedEncoding: requestedEncoding)
    guard !Self.looksBinary(decoded.text) else {
      throw CocoaError(
        .fileReadCorruptFile,
        userInfo: [NSLocalizedDescriptionKey: "The selected file does not appear to be plain text."]
      )
    }
    let endings = Self.detectLineEndings(decoded.text)
    text = Self.normalize(decoded.text)
    encoding = decoded.encoding
    lineEnding = endings.preferred
    hasMixedLineEndings = endings.mixed
  }

  public func data(
    encoding outputEncoding: TextEncoding? = nil, lineEnding outputLineEnding: LineEnding? = nil
  ) throws -> Data {
    let encoding = outputEncoding ?? encoding
    let ending = outputLineEnding ?? lineEnding
    let output = Self.normalize(text).replacingOccurrences(of: "\n", with: ending.characters)
    guard var data = output.data(using: encoding.foundationEncoding, allowLossyConversion: false)
    else {
      throw CocoaError(
        .fileWriteInapplicableStringEncoding,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Some characters cannot be represented using \(encoding.displayName). Choose a Unicode encoding instead."
        ])
    }
    switch encoding {
    case .utf8BOM:
      data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0)
    case .utf16LittleEndian:
      data.insert(contentsOf: [0xFF, 0xFE], at: 0)
    case .utf16BigEndian:
      data.insert(contentsOf: [0xFE, 0xFF], at: 0)
    default:
      break
    }
    return data
  }

  private static func decode(_ data: Data, requestedEncoding: TextEncoding?) throws -> (
    text: String, encoding: TextEncoding
  ) {
    if let requestedEncoding {
      let bytes: Data.SubSequence
      switch requestedEncoding {
      case .utf8, .utf8BOM:
        bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
      case .utf16LittleEndian:
        bytes = data.starts(with: [0xFF, 0xFE]) ? data.dropFirst(2) : data[...]
      case .utf16BigEndian:
        bytes = data.starts(with: [0xFE, 0xFF]) ? data.dropFirst(2) : data[...]
      default:
        bytes = data[...]
      }
      guard let text = String(data: bytes, encoding: requestedEncoding.foundationEncoding) else {
        throw CocoaError(
          .fileReadInapplicableStringEncoding,
          userInfo: [
            NSLocalizedDescriptionKey:
              "The file is not valid (requestedEncoding.displayName) text."
          ])
      }
      return (text, requestedEncoding)
    }

    if data.starts(with: [0xEF, 0xBB, 0xBF]),
      let text = String(data: data.dropFirst(3), encoding: .utf8)
    {
      return (text, .utf8BOM)
    }
    if data.starts(with: [0xFF, 0xFE]),
      let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
    {
      return (text, .utf16LittleEndian)
    }
    if data.starts(with: [0xFE, 0xFF]),
      let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
    {
      return (text, .utf16BigEndian)
    }
    let bytes = [UInt8](data.prefix(512))
    if bytes.count >= 4 {
      let evenZeros = stride(from: 0, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
      let oddZeros = stride(from: 1, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
      let pairs = max(1, bytes.count / 2)
      if oddZeros * 2 > pairs,
        let text = String(data: data, encoding: .utf16LittleEndian)
      {
        return (text, .utf16LittleEndian)
      }
      if evenZeros * 2 > pairs,
        let text = String(data: data, encoding: .utf16BigEndian)
      {
        return (text, .utf16BigEndian)
      }
    }

    if let text = String(data: data, encoding: .utf8) { return (text, .utf8) }

    for encoding in [TextEncoding.windows1252, .macOSRoman] {
      if let text = String(data: data, encoding: encoding.foundationEncoding) {
        return (text, encoding)
      }
    }
    throw CocoaError(
      .fileReadInapplicableStringEncoding,
      userInfo: [NSLocalizedDescriptionKey: "PoteNad could not determine the file's text encoding."]
    )
  }

  private static func detectLineEndings(_ text: String) -> (preferred: LineEnding, mixed: Bool) {
    var crlf = 0
    var lf = 0
    var cr = 0
    let scalars = text.unicodeScalars
    var index = scalars.startIndex
    while index < scalars.endIndex {
      if scalars[index].value == 13 {
        let next = scalars.index(after: index)
        if next < scalars.endIndex, scalars[next].value == 10 {
          crlf += 1
          index = scalars.index(after: next)
          continue
        }
        cr += 1
      } else if scalars[index].value == 10 {
        lf += 1
      }
      index = scalars.index(after: index)
    }
    let counts: [(LineEnding, Int)] = [(.crlf, crlf), (.lf, lf), (.cr, cr)]
    let used = counts.filter { $0.1 > 0 }
    return (used.max(by: { $0.1 < $1.1 })?.0 ?? .lf, used.count > 1)
  }

  private static func looksBinary(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    var controls = 0
    var checked = 0
    for scalar in text.unicodeScalars.prefix(4096) {
      checked += 1
      if scalar.value == 0 { return true }
      if scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t"
        && scalar.value != 0x0C
      {
        controls += 1
      }
    }
    return checked > 0 && controls * 50 > checked
  }

  private static func normalize(_ text: String) -> String {
    guard text.utf8.contains(13) else { return text }
    return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r", with: "\n")
  }
}

/// Sorted UTF-16 line offsets; selection changes use binary search, never a document scan.
public struct LineIndex {
  public private(set) var starts = [0]
  public init() {}
  public mutating func rebuild(_ text: NSString) {
    starts = [0]
    for i in 0..<text.length where text.character(at: i) == 10 { starts.append(i + 1) }
  }
  public mutating func update(_ text: NSString, editedRange: NSRange, delta: Int) {
    let oldEnd = NSMaxRange(editedRange) - delta
    let lower = upperBound(editedRange.location)
    let upper = upperBound(oldEnd)
    let added = (editedRange.location..<NSMaxRange(editedRange)).compactMap {
      text.character(at: $0) == 10 ? $0 + 1 : nil
    }
    starts.replaceSubrange(lower..<upper, with: added)
    if delta != 0 {
      for i in (lower + added.count)..<starts.count { starts[i] += delta }
    }
  }
  private func upperBound(_ offset: Int) -> Int {
    var lo = 0
    var hi = starts.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if starts[mid] <= offset { lo = mid + 1 } else { hi = mid }
    }
    return lo
  }
  public func position(_ offset: Int) -> (line: Int, column: Int) {
    let i = max(0, upperBound(offset) - 1)
    return (i + 1, offset - starts[i] + 1)
  }
}
