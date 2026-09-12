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
  private var sessionReviewDelegate: AnyObject?
  private var sessionReviewSelector: Selector?
  private var sessionReviewContext: UnsafeMutableRawPointer?

  @IBAction func newWindowForTab(_ sender: Any?) {
    let sourceWindow = NSApp.keyWindow
      ?? NSApp.mainWindow
      ?? currentDocument?.windowControllers.first?.window
    do {
      let document = try openUntitledDocumentAndDisplay(false)
      document.makeWindowControllers()
      guard let window = document.windowControllers.first?.window else {
        document.close()
        return
      }
      if let sourceWindow, sourceWindow.isVisible {
        sourceWindow.addTabbedWindow(window, ordered: .above)
      }
      document.showWindows()
    } catch {
      NSApp.presentError(error)
    }
  }

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

  override func reopenDocument(
    for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool,
    completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
  ) {
    guard AppPreferences.startupBehavior == .restorePreviousSession,
      ProcessInfo.processInfo.environment["POTENAD_SESSION_STORE"] == nil
    else {
      completionHandler(nil, false, nil)
      return
    }
    super.reopenDocument(
      for: urlOrNil, withContentsOf: contentsURL, display: displayDocument,
      completionHandler: completionHandler)
  }

  override func reviewUnsavedDocuments(
    withAlertTitle title: String?, cancellable: Bool, delegate: Any?,
    didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
  ) {
    guard AppPreferences.startupBehavior == .restorePreviousSession else {
      super.reviewUnsavedDocuments(
        withAlertTitle: title, cancellable: cancellable, delegate: delegate,
        didReviewAllSelector: didReviewAllSelector, contextInfo: contextInfo)
      return
    }
    sessionReviewDelegate = delegate as AnyObject?
    sessionReviewSelector = didReviewAllSelector
    sessionReviewContext = contextInfo
    do {
      try saveSession()
      finishSessionReview(success: true)
    } catch {
      NSApp.presentError(error)
      finishSessionReview(success: false)
    }
  }

  private func finishSessionReview(success: Bool) {
    guard let delegate = sessionReviewDelegate, let selector = sessionReviewSelector,
      let object = delegate as? NSObject
    else { return }
    let context = sessionReviewContext
    sessionReviewDelegate = nil
    sessionReviewSelector = nil
    sessionReviewContext = nil
    typealias ReviewCallback = @convention(c) (
      AnyObject, Selector, NSDocumentController, Bool, UnsafeMutableRawPointer?
    ) -> Void
    let callback = unsafeBitCast(object.method(for: selector), to: ReviewCallback.self)
    callback(object, selector, self, success, context)
  }

  func saveSession() throws {
    var visited = Set<ObjectIdentifier>()
    var groups: [StoredSession.WindowGroup] = []
    for document in documents.compactMap({ $0 as? PoteNadDocument }) {
      guard let window = document.windowControllers.first?.window else { continue }
      let windows = window.tabbedWindows ?? [window]
      let identity = ObjectIdentifier(windows[0])
      guard visited.insert(identity).inserted else { continue }
      windows.forEach { visited.insert(ObjectIdentifier($0)) }
      let groupDocuments = windows.compactMap {
        $0.windowController?.document as? PoteNadDocument
      }
      let storedDocuments = groupDocuments.map { document in
        StoredSession.Document(
          text: document.editor?.textView.string ?? document.file.text,
          filePath: document.fileURL?.path,
          encoding: document.file.encoding.rawValue,
          lineEnding: document.file.lineEnding.rawValue,
          hasMixedLineEndings: document.file.hasMixedLineEndings,
          wasEdited: document.isDocumentEdited)
      }
      guard !storedDocuments.isEmpty else { continue }
      let selectedWindow = window.tabGroup?.selectedWindow ?? window
      groups.append(
        StoredSession.WindowGroup(
          documents: storedDocuments,
          selectedDocument: windows.firstIndex(of: selectedWindow) ?? 0,
          frame: NSStringFromRect(windows[0].frame)))
    }
    try SessionState.save(StoredSession(windowGroups: groups))
  }

  @discardableResult
  func restoreSession() throws -> Bool {
    guard let session = try SessionState.loadAndRemove(), !session.windowGroups.isEmpty else {
      return false
    }
    var restoredAny = false
    for group in session.windowGroups {
      var groupDocuments: [PoteNadDocument] = []
      for stored in group.documents {
        let document = try restoreDocument(stored)
        addDocument(document)
        document.makeWindowControllers()
        if stored.wasEdited { document.updateChangeCount(.changeDone) }
        groupDocuments.append(document)
      }
      let windows = groupDocuments.compactMap { $0.windowControllers.first?.window }
      guard let firstWindow = windows.first else { continue }
      let frame = NSRectFromString(group.frame)
      if !frame.isEmpty { firstWindow.setFrame(frame, display: false) }
      for window in windows.dropFirst() { firstWindow.addTabbedWindow(window, ordered: .above) }
      groupDocuments.forEach { $0.showWindows() }
      if windows.indices.contains(group.selectedDocument) {
        firstWindow.tabGroup?.selectedWindow = windows[group.selectedDocument]
      }
      restoredAny = true
    }
    return restoredAny
  }

  private func restoreDocument(_ stored: StoredSession.Document) throws -> PoteNadDocument {
    let documentType = defaultType ?? "public.plain-text"
    if !stored.wasEdited, let path = stored.filePath,
      FileManager.default.fileExists(atPath: path),
      let document = try makeDocument(
        withContentsOf: URL(fileURLWithPath: path), ofType: documentType) as? PoteNadDocument
    {
      return document
    }
    guard let document = try makeUntitledDocument(ofType: documentType) as? PoteNadDocument else {
      throw CocoaError(.fileReadUnknown)
    }
    document.file = TextFile(
      text: stored.text,
      encoding: TextEncoding(rawValue: stored.encoding) ?? .utf8,
      lineEnding: LineEnding(rawValue: stored.lineEnding) ?? .lf,
      hasMixedLineEndings: stored.hasMixedLineEndings)
    if let path = stored.filePath { document.fileURL = URL(fileURLWithPath: path) }
    return document
  }
}
