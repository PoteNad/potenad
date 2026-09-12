import AppKit
import TextCore

final class PlainTextView: NSTextView {
  weak var editor: Editor?

  override func magnify(with event: NSEvent) {
    guard let editor else {
      super.magnify(with: event)
      return
    }
    editor.setZoom(editor.zoomPercent + Int((event.magnification * 100).rounded()))
  }

  override func changeFont(_ sender: Any?) {
    guard let editor, let manager = sender as? NSFontManager else {
      super.changeFont(sender)
      return
    }
    editor.setBaseFont(manager.convert(editor.baseFont))
  }
}

final class EditorScrollView: NSScrollView {
  override func tile() {
    super.tile()
    guard let text = documentView as? NSTextView else { return }
    text.minSize = contentSize
    if !text.isHorizontallyResizable {
      let size = NSSize(
        width: contentSize.width, height: max(contentSize.height, text.frame.height))
      if text.frame.size != size { text.setFrameSize(size) }
    }
  }
}

extension PlainTextView {
  override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool
  {
    guard let value = pboard.string(forType: .string) else { return false }
    insertText(
      value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"),
      replacementRange: selectedRange())
    return true
  }
}

final class Editor: NSWindowController, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate,
  NSMenuItemValidation
{
  let textView = PlainTextView(frame: NSRect(x: 0, y: 0, width: 850, height: 556))
  let scroll = EditorScrollView()
  let status = NSTextField(labelWithString: "")
  let statusDetails = NSTextField(labelWithString: "")
  let statusBar = NSVisualEffectView()
  private lazy var statusHeight = statusBar.heightAnchor.constraint(equalToConstant: 24)
  var index = LineIndex()
  var wrap = UserDefaults.standard.bool(forKey: PreferenceKey.wrap)
  var statusVisible = UserDefaults.standard.bool(forKey: PreferenceKey.status)
  private(set) var zoomPercent = 100
  private(set) var baseFont = AppPreferences.font
  private let paragraph: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byCharWrapping
    return style
  }()
  private(set) lazy var displayFont = baseFont
  private(set) lazy var displayAttributes: [NSAttributedString.Key: Any] = [
    .font: displayFont, .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor,
  ]
  private var lastStatus = ""
  unowned let note: PoteNadDocument

  init(document: PoteNadDocument) {
    note = document
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 850, height: 580),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    super.init(window: window)
    textView.editor = self
    window.minSize = NSSize(width: 420, height: 240)
    window.center()
    window.setFrameAutosaveName("PoteNadDocumentWindow")

    let root = NSView()
    window.contentView = root
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    textView.usesFontPanel = true
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = UserDefaults.standard.bool(
      forKey: PreferenceKey.checkSpelling)
    textView.isGrammarCheckingEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.isAutomaticTextCompletionEnabled = false
    updateWritingToolsBehavior()
    textView.textContainerInset = NSSize(width: 6, height: 6)
    textView.font = baseFont
    textView.isVerticallyResizable = true
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.layoutManager?.allowsNonContiguousLayout = true
    loadText(document.file.text)
    document.file.text = ""
    textView.delegate = self
    textView.textStorage?.delegate = self
    scroll.documentView = textView

    statusBar.material = .headerView
    statusBar.blendingMode = .withinWindow
    statusBar.state = .followsWindowActiveState
    status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    statusDetails.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    status.textColor = .secondaryLabelColor
    statusDetails.textColor = .secondaryLabelColor
    status.lineBreakMode = .byTruncatingTail
    statusDetails.alignment = .right
    statusDetails.lineBreakMode = .byTruncatingHead

    root.addSubview(scroll)
    root.addSubview(statusBar)
    statusBar.addSubview(status)
    statusBar.addSubview(statusDetails)
    for view in [scroll, statusBar, status, statusDetails] {
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: root.topAnchor),
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
      statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      statusHeight,
      status.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 8),
      status.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
      statusDetails.leadingAnchor.constraint(
        greaterThanOrEqualTo: status.trailingAnchor, constant: 12),
      statusDetails.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -8),
      statusDetails.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
    ])
    setStatusVisible(statusVisible)
    applyWrap()
    updateStatus()
    NotificationCenter.default.addObserver(
      self, selector: #selector(defaultsDidChange), name: .editorDefaultsDidChange, object: nil)
    window.makeFirstResponder(textView)
  }

  required init?(coder: NSCoder) { fatalError() }

  deinit { NotificationCenter.default.removeObserver(self) }

  func loadText(_ text: String) {
    textView.textStorage?.setAttributedString(
      NSAttributedString(string: text, attributes: displayAttributes))
    textView.defaultParagraphStyle = paragraph
    textView.typingAttributes = displayAttributes
    index.rebuild(text as NSString)
    textView.undoManager?.removeAllActions()
    updateStatus()
  }

  func textStorage(
    _ storage: NSTextStorage, willProcessEditing mask: NSTextStorageEditActions, range: NSRange,
    changeInLength delta: Int
  ) {
    if mask.contains(.editedCharacters), range.length > 0 {
      storage.setAttributes(displayAttributes, range: range)
    }
  }

  func textStorage(
    _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange, changeInLength delta: Int
  ) {
    if editedMask.contains(.editedCharacters) {
      index.update(textStorage.mutableString, editedRange: editedRange, delta: delta)
    }
  }

  func undoManager(for view: NSTextView) -> UndoManager? { note.undoManager }

  func textDidChange(_ notification: Notification) {
    note.syncEditedIndicator()
    updateStatus()
  }

  func textViewDidChangeSelection(_ notification: Notification) { updateStatus() }

  func updateStatus() {
    guard statusVisible else { return }
    let position = index.position(textView.selectedRange().location)
    let ending = note.file.hasMixedLineEndings ? "Mixed" : note.file.lineEnding.displayName
    let value =
      "Ln \(position.line), Col \(position.column)|\(ending)|\(note.file.encoding.displayName)|\(zoomPercent)%"
    guard value != lastStatus else { return }
    lastStatus = value
    status.stringValue = "Ln \(position.line), Col \(position.column)"
    statusDetails.stringValue = "\(ending)   \(note.file.encoding.displayName)   \(zoomPercent)%"
  }

  func applyWrap() {
    scroll.hasHorizontalScroller = !wrap
    textView.isHorizontallyResizable = !wrap
    textView.autoresizingMask = wrap ? [.width] : []
    textView.textContainer?.widthTracksTextView = wrap
    textView.textContainer?.containerSize =
      wrap
      ? NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
      : NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    scroll.tile()
  }

  @objc func toggleWrap(_ sender: Any?) {
    wrap.toggle()
    applyWrap()
  }

  @objc func toggleStatus(_ sender: Any?) { setStatusVisible(!statusVisible) }

  private func setStatusVisible(_ visible: Bool) {
    statusVisible = visible
    statusBar.isHidden = !visible
    statusHeight.constant = visible ? 24 : 0
    updateStatus()
  }

  func setBaseFont(_ font: NSFont) {
    guard font.pointSize.isFinite, (1...512).contains(font.pointSize), baseFont != font else {
      return
    }
    baseFont = font
    applyFont()
  }

  func applyFont() {
    displayFont =
      NSFont(
        descriptor: baseFont.fontDescriptor, size: baseFont.pointSize * CGFloat(zoomPercent) / 100)
      ?? baseFont
    displayAttributes[.font] = displayFont
    textView.font = displayFont
    textView.defaultParagraphStyle = paragraph
    textView.typingAttributes = displayAttributes
    if let storage = textView.textStorage, storage.length > 0 {
      storage.addAttribute(
        .font, value: displayFont, range: NSRange(location: 0, length: storage.length))
    }
    textView.scrollRangeToVisible(textView.selectedRange())
    updateStatus()
  }

  @objc func zoomIn(_ sender: Any?) { setZoom(zoomPercent + 10) }
  @objc func zoomOut(_ sender: Any?) { setZoom(zoomPercent - 10) }
  @objc func zoomReset(_ sender: Any?) { setZoom(100) }

  func setZoom(_ percent: Int) {
    let clamped = min(500, max(10, percent))
    guard clamped != zoomPercent else { return }
    zoomPercent = clamped
    applyFont()
  }

  static func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: Date())
  }

  @objc func insertDate(_ sender: Any?) {
    textView.insertText(Self.timestamp(), replacementRange: textView.selectedRange())
  }

  @objc func goTo(_ sender: Any?) {
    let alert = NSAlert()
    alert.messageText = "Go to Line"
    alert.addButton(withTitle: "Go")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(string: String(index.position(textView.selectedRange().location).line))
    field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    guard let line = Int(field.stringValue), line > 0, line <= index.starts.count else {
      NSSound.beep()
      return
    }
    let range = NSRange(location: index.starts[line - 1], length: 0)
    textView.setSelectedRange(range)
    textView.scrollRangeToVisible(range)
  }

  @objc func selectLines(_ sender: Any?) {
    let alert = NSAlert()
    alert.messageText = "Select Lines"
    alert.informativeText = "Enter a line number or range, such as 5 or 10-20."
    alert.addButton(withTitle: "Select")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(string: String(index.position(textView.selectedRange().location).line))
    field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let parts = field.stringValue.split(separator: "-", maxSplits: 1).compactMap {
      Int($0.trimmingCharacters(in: .whitespaces))
    }
    guard let first = parts.first, first > 0, first <= index.starts.count else {
      NSSound.beep()
      return
    }
    let last = parts.count == 2 ? parts[1] : first
    guard last >= first, last <= index.starts.count else {
      NSSound.beep()
      return
    }
    let start = index.starts[first - 1]
    let end = last < index.starts.count ? index.starts[last] : textView.string.utf16.count
    let range = NSRange(location: start, length: end - start)
    textView.setSelectedRange(range)
    textView.scrollRangeToVisible(range)
  }

  @objc func showFind(_ sender: Any?) { performFind(.showFindInterface) }
  @objc func showReplace(_ sender: Any?) { performFind(.showReplaceInterface) }
  @objc func findNext(_ sender: Any?) { performFind(.nextMatch) }
  @objc func findPrevious(_ sender: Any?) { performFind(.previousMatch) }

  private func performFind(_ action: NSTextFinder.Action) {
    let item = NSMenuItem()
    item.tag = action.rawValue
    textView.performTextFinderAction(item)
  }

  @objc private func defaultsDidChange(_ notification: Notification) {
    setBaseFont(AppPreferences.font)
    wrap = UserDefaults.standard.bool(forKey: PreferenceKey.wrap)
    setStatusVisible(UserDefaults.standard.bool(forKey: PreferenceKey.status))
    textView.isContinuousSpellCheckingEnabled = UserDefaults.standard.bool(
      forKey: PreferenceKey.checkSpelling)
    updateWritingToolsBehavior()
    applyWrap()
  }

  private func updateWritingToolsBehavior() {
    if #available(macOS 15.0, *) {
      textView.allowedWritingToolsResultOptions = .plainText
    }
    if #available(macOS 15.2, *) {
      textView.writingToolsBehavior = AppPreferences.writingToolsEnabled ? .default : .none
    } else if #available(macOS 15.0, *) {
      textView.writingToolsBehavior = .none
    }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(toggleWrap(_:)) { menuItem.state = wrap ? .on : .off }
    if menuItem.action == #selector(toggleStatus(_:)) {
      menuItem.state = statusVisible ? .on : .off
    }
    if menuItem.action == #selector(zoomIn(_:)) { return zoomPercent < 500 }
    if menuItem.action == #selector(zoomOut(_:)) { return zoomPercent > 10 }
    if menuItem.action == #selector(goTo(_:)) { return !wrap }
    return true
  }
}
