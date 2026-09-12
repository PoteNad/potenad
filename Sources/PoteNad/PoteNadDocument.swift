import AppKit
import TextCore
import UniformTypeIdentifiers

@MainActor
private final class SaveOptionsAccessory: NSView {
  weak var document: PoteNadDocument?
  let encoding = NSPopUpButton()
  let lineEnding = NSPopUpButton()

  init(document: PoteNadDocument) {
    self.document = document
    super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 76))
    for value in TextEncoding.allCases {
      encoding.addItem(withTitle: value.displayName)
      encoding.lastItem?.representedObject = value.rawValue
    }
    for value in LineEnding.allCases {
      lineEnding.addItem(withTitle: value.displayName)
      lineEnding.lastItem?.representedObject = value.rawValue
    }
    encoding.selectItem(withTitle: document.file.encoding.displayName)
    lineEnding.selectItem(withTitle: document.file.lineEnding.displayName)
    encoding.target = self
    encoding.action = #selector(changeOptions)
    lineEnding.target = self
    lineEnding.action = #selector(changeOptions)
    let grid = NSGridView(views: [
      [NSTextField(labelWithString: "Text encoding:"), encoding],
      [NSTextField(labelWithString: "Line endings:"), lineEnding],
    ])
    grid.rowSpacing = 8
    grid.columnSpacing = 10
    grid.column(at: 0).xPlacement = .trailing
    grid.frame = bounds.insetBy(dx: 8, dy: 6)
    grid.autoresizingMask = [.width, .height]
    addSubview(grid)
  }

  required init?(coder: NSCoder) { fatalError() }

  @objc private func changeOptions() {
    guard let document else { return }
    if let rawValue = encoding.selectedItem?.representedObject as? String,
      let value = TextEncoding(rawValue: rawValue)
    {
      document.file.encoding = value
    }
    if let rawValue = lineEnding.selectedItem?.representedObject as? String,
      let value = LineEnding(rawValue: rawValue)
    {
      document.file.lineEnding = value
      document.file.hasMixedLineEndings = false
    }
    document.editor?.updateStatus()
  }
}

@objc(PoteNadDocument)
final class PoteNadDocument: NSDocument {
  var header = "&f"
  var footer = "Page &p"
  var file: TextFile
  var editor: Editor?
  private var saveOptionsAccessory: SaveOptionsAccessory?

  override init() {
    file = TextFile(encoding: AppPreferences.encoding, lineEnding: AppPreferences.lineEnding)
    super.init()
  }

  override class var autosavesInPlace: Bool { true }
  override class var autosavesDrafts: Bool { true }
  override class var preservesVersions: Bool { true }

  override var isDocumentEdited: Bool {
    if fileURL == nil && (editor?.textView.string ?? file.text).isEmpty { return false }
    return super.isDocumentEdited
  }

  func syncEditedIndicator() {
    for controller in windowControllers { controller.window?.isDocumentEdited = isDocumentEdited }
  }

  override func updateChangeCount(_ change: NSDocument.ChangeType) {
    super.updateChangeCount(change)
    syncEditedIndicator()
  }

  override func makeWindowControllers() {
    guard windowControllers.isEmpty else { return }
    let isLog = file.text.hasPrefix(".LOG")
    let controller = Editor(document: self)
    editor = controller
    addWindowController(controller)
    if isLog {
      controller.textView.setSelectedRange(
        NSRange(location: controller.textView.string.utf16.count, length: 0))
      controller.textView.insertText(
        "\n" + Editor.timestamp() + "\n", replacementRange: controller.textView.selectedRange())
    }
  }

  override func read(from data: Data, ofType typeName: String) throws {
    let requestedEncoding = MainActor.assumeIsolated {
      (NSDocumentController.shared as? PoteNadDocumentController)?.consumeSelectedOpenEncoding()
    }
    let loaded = try TextFile(data: data, encoding: requestedEncoding)
    MainActor.assumeIsolated {
      file = loaded
      editor?.loadText(loaded.text)
      if editor != nil { file.text = "" }
    }
  }

  override func data(ofType typeName: String) throws -> Data {
    var output = file
    if let editor { output.text = editor.textView.string }
    return try output.data()
  }

  override func write(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
    originalContentsURL absoluteOriginalContentsURL: URL?
  ) throws {
    try super.write(
      to: url, ofType: typeName, for: saveOperation,
      originalContentsURL: absoluteOriginalContentsURL)
    MainActor.assumeIsolated {
      file.hasMixedLineEndings = false
      editor?.updateStatus()
    }
  }

  override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
    savePanel.allowedContentTypes = [.plainText]
    savePanel.allowsOtherFileTypes = true
    savePanel.isExtensionHidden = false
    let accessory = SaveOptionsAccessory(document: self)
    saveOptionsAccessory = accessory
    savePanel.accessoryView = accessory
    return true
  }

  @objc func pageSetup(_ sender: Any?) {
    let accessory = NSViewController()
    let headerField = NSTextField(string: header)
    let footerField = NSTextField(string: footer)
    let stack = NSStackView(views: [
      NSTextField(labelWithString: "Header:"), headerField,
      NSTextField(labelWithString: "Footer:"), footerField,
      NSTextField(
        labelWithString:
          "&f filename · &p page · &d date · &t time · &l left · &c center · &r right"),
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    headerField.widthAnchor.constraint(equalToConstant: 420).isActive = true
    footerField.widthAnchor.constraint(equalToConstant: 420).isActive = true
    accessory.view = stack
    accessory.title = "Headers and Footers"
    let layout = NSPageLayout()
    layout.addAccessoryController(accessory)
    if layout.runModal(with: printInfo) == NSApplication.ModalResponse.OK.rawValue {
      header = headerField.stringValue
      footer = footerField.stringValue
    }
  }

  override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws
    -> NSPrintOperation
  {
    let info = printInfo.copy() as! NSPrintInfo
    info.horizontalPagination = .fit
    info.isVerticallyCentered = false
    let width = info.paperSize.width - info.leftMargin - info.rightMargin
    let view = PrintTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
    view.headerTemplate = header
    view.footerTemplate = footer
    view.filename = displayName
    info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = true
    view.isRichText = false
    view.string = editor?.textView.string ?? file.text
    view.font = editor?.baseFont ?? AppPreferences.font
    view.defaultParagraphStyle = editor?.textView.defaultParagraphStyle
    if let style = view.defaultParagraphStyle {
      view.textStorage?.addAttribute(
        .paragraphStyle, value: style, range: NSRange(location: 0, length: view.string.utf16.count))
    }
    view.textContainer?.containerSize = NSSize(
      width: width, height: CGFloat.greatestFiniteMagnitude)
    view.layoutManager?.ensureLayout(for: view.textContainer!)
    let height = view.layoutManager!.usedRect(for: view.textContainer!).height + 20
    view.setFrameSize(NSSize(width: width, height: height))
    return NSPrintOperation(view: view, printInfo: info)
  }
}
