import XCTest

@testable import TextCore

final class TextCoreTests: XCTestCase {
  func testUTF8RoundTrip() throws {
    let content = "café 👩🏽‍💻 中文\nsecond\n"
    let file = TextFile(text: content)
    XCTAssertEqual(try file.data(), Data(content.utf8))
    let reopened = try TextFile(data: file.data())
    XCTAssertEqual(reopened.text, content)
    XCTAssertEqual(reopened.encoding, .utf8)
    XCTAssertEqual(reopened.lineEnding, .lf)
  }

  func testUnicodeEncodingsRoundTrip() throws {
    let content = "café 中文\nsecond\n"
    for encoding in [TextEncoding.utf8BOM, .utf16LittleEndian, .utf16BigEndian] {
      let data = try TextFile(text: content, encoding: encoding).data()
      let reopened = try TextFile(data: data)
      XCTAssertEqual(reopened.text, content)
      XCTAssertEqual(reopened.encoding, encoding)
    }
  }

  func testASCIILookingUTF16WithoutBOM() throws {
    let data = try XCTUnwrap("One\r\ntwo\r\n".data(using: .utf16LittleEndian))
    let reopened = try TextFile(data: data)
    XCTAssertEqual(reopened.text, "One\ntwo\n")
    XCTAssertEqual(reopened.encoding, .utf16LittleEndian)
  }

  func testLineEndingsAreDetectedAndPreserved() throws {
    for (ending, input) in [
      (LineEnding.crlf, "a\r\nb\r\n"), (.cr, "a\rb\r"), (.lf, "a\nb\n"),
    ] {
      let loaded = try TextFile(data: Data(input.utf8))
      XCTAssertEqual(loaded.text, "a\nb\n")
      XCTAssertEqual(loaded.lineEnding, ending)
      XCTAssertFalse(loaded.hasMixedLineEndings)
      XCTAssertEqual(try loaded.data(), Data(input.utf8))
    }
  }

  func testMixedLineEndingsUseTheMostCommonStyle() throws {
    let loaded = try TextFile(data: Data("a\r\nb\r\nc\n".utf8))
    XCTAssertTrue(loaded.hasMixedLineEndings)
    XCTAssertEqual(loaded.lineEnding, .crlf)
    XCTAssertEqual(loaded.text, "a\nb\nc\n")
    XCTAssertEqual(try loaded.data(), Data("a\r\nb\r\nc\r\n".utf8))
  }

  func testLegacyEncodingFallback() throws {
    let input = Data([0x63, 0x61, 0x66, 0xE9])
    let loaded = try TextFile(data: input, encoding: .windows1252)
    XCTAssertEqual(loaded.text, "café")
    XCTAssertEqual(loaded.encoding, .windows1252)
    XCTAssertEqual(try loaded.data(), input)
  }

  func testRequestedEncodingOverridesAutomaticDetection() throws {
    let input = Data([0xC3, 0xA9])
    let automatic = try TextFile(data: input)
    let requested = try TextFile(data: input, encoding: .windows1252)
    XCTAssertEqual(automatic.text, "é")
    XCTAssertEqual(requested.text, "Ã©")
    XCTAssertEqual(requested.encoding, .windows1252)
  }

  func testBinaryDataIsRejected() {
    XCTAssertThrowsError(try TextFile(data: Data([0, 1, 2, 3, 4, 5])))
  }

  func testUnrepresentableLegacySaveIsRejected() {
    XCTAssertThrowsError(try TextFile(text: "中文", encoding: .windows1252).data())
  }

  func testIncrementalIndexAgainstFullRebuild() {
    let text = NSMutableString(string: "one\ntwo\n👋 three\n")
    var incremental = LineIndex()
    incremental.rebuild(text)
    var seed: UInt64 = 42
    func random(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1
      return Int(seed >> 32) % bound
    }
    for _ in 0..<2000 {
      let start = random(text.length + 1)
      let count = random(text.length - start + 1)
      let replacement = ["", "\n", "abc", "\n\nx\n", "long text"][random(5)]
      let length = (replacement as NSString).length
      text.replaceCharacters(in: NSRange(location: start, length: count), with: replacement)
      incremental.update(
        text, editedRange: NSRange(location: start, length: length), delta: length - count)
      var rebuilt = LineIndex()
      rebuilt.rebuild(text)
      XCTAssertEqual(incremental.starts, rebuilt.starts)
      for offset in 0...text.length {
        XCTAssertEqual(incremental.position(offset).line, rebuilt.position(offset).line)
        XCTAssertEqual(incremental.position(offset).column, rebuilt.position(offset).column)
      }
    }
  }

  func testLargeDocumentIndex() {
    let text = String(repeating: "a short line of plain text\n", count: 400_000) as NSString
    var index = LineIndex()
    index.rebuild(text)
    XCTAssertEqual(index.starts.count, 400_001)
    XCTAssertEqual(index.position(text.length).line, 400_001)
    measure { for i in stride(from: 0, to: text.length, by: 1000) { _ = index.position(i) } }
  }
}
