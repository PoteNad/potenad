import AppKit
import TextCore
import UniformTypeIdentifiers

@MainActor
private final class OpenOptionsAccessory: NSView {
  let encoding = NSPopUpButton()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    encoding.addItem(withTitle: "Automatic")
    for value in TextEncoding.allCases {
      encoding.addItem(withTitle: value.displayName)
      encoding.lastItem?.representedObject = value.rawValue
    }
    let label = NSTextField(labelWithString: "Text encoding:")
    label.frame = NSRect(x: 8, y: 8, width: 100, height: 24)
    encoding.frame = NSRect(x: 112, y: 6, width: 232, height: 26)
    addSubview(label)
    addSubview(encoding)
  }

  required init?(coder: NSCoder) { fatalError() }

  var selectedEncoding: TextEncoding? {
    guard let rawValue = encoding.selectedItem?.representedObject as? String else { return nil }
    return TextEncoding(rawValue: rawValue)
  }
}

@objc(PoteNadDocumentController)
final class PoteNadDocumentController: NSDocumentController {
  private var selectedOpenEncoding: TextEncoding?

  func consumeSelectedOpenEncoding() -> TextEncoding? {
    defer { selectedOpenEncoding = nil }
    return selectedOpenEncoding
  }

  override func beginOpenPanel(
    _ openPanel: NSOpenPanel, forTypes inTypes: [String]?,
    completionHandler: @escaping (Int) -> Void
  ) {
    openPanel.allowedContentTypes = [.plainText, .text, .data]
    let accessory = OpenOptionsAccessory(frame: NSRect(x: 0, y: 0, width: 352, height: 40))
    openPanel.accessoryView = accessory
    super.beginOpenPanel(openPanel, forTypes: nil) { response in
      self.selectedOpenEncoding = accessory.selectedEncoding
      completionHandler(response)
    }
  }

  override func openDocument(
    withContentsOf url: URL, display displayDocument: Bool,
    completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
  ) {
    let transient = documents.first {
      $0.fileURL == nil && !$0.isDocumentEdited
        && (($0 as? PoteNadDocument)?.editor?.textView.string.isEmpty ?? false)
    }
    super.openDocument(withContentsOf: url, display: displayDocument) {
      document, alreadyOpen, error in
      if document != nil, transient !== document { transient?.close() }
      completionHandler(document, alreadyOpen, error)
    }
  }
}
