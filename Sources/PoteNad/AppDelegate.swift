import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private lazy var settingsController = SettingsWindowController()
  private let recentMenu = NSMenu(title: "Open Recent")
  private var writingToolsItems: [NSMenuItem] = []
  private var didFinishLaunching = false
  private var didFinishRestoringWindows = false

  func applicationWillFinishLaunching(_ notification: Notification) {
    NotificationCenter.default.addObserver(
      self, selector: #selector(finishedRestoringWindows),
      name: NSApplication.didFinishRestoringWindowsNotification, object: NSApp)
    if let path = ProcessInfo.processInfo.environment["POTENAD_OPEN_CHECK"] {
      NSDocumentController.shared.openDocument(
        withContentsOf: URL(fileURLWithPath: path), display: true
      ) { _, _, error in
        if let error {
          fputs("Open check failed: \(error)\n", stderr)
          exit(1)
        }
      }
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppPreferences.registerDefaults()
    NSWindow.allowsAutomaticWindowTabbing = true
    buildMenus()
    NotificationCenter.default.addObserver(
      self, selector: #selector(preferencesDidChange), name: .editorDefaultsDidChange, object: nil)
    didFinishLaunching = true
    openDocumentAfterRestorationIfNeeded()
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    AppPreferences.startupBehavior == .newDocument
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard AppPreferences.startupBehavior == .restorePreviousSession else {
      SessionState.remove()
      return .terminateNow
    }
    return .terminateNow
  }

  func buildMenus() {
    let bar = NSMenu()
    NSApp.mainMenu = bar

    func menu(_ title: String) -> NSMenu {
      let item = NSMenuItem()
      let menu = NSMenu(title: title)
      item.submenu = menu
      bar.addItem(item)
      return menu
    }

    @discardableResult
    func add(
      _ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
      modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, tag: Int? = nil
    ) -> NSMenuItem {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.target = target
      if let tag { item.tag = tag }
      menu.addItem(item)
      return item
    }

    let app = menu("PoteNad")
    add(app, "About PoteNad", #selector(showAbout(_:)), target: self)
    app.addItem(.separator())
    add(app, "Settings…", #selector(showSettings(_:)), ",", target: self)
    app.addItem(.separator())
    let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    let services = NSMenu(title: "Services")
    servicesItem.submenu = services
    app.addItem(servicesItem)
    NSApp.servicesMenu = services
    app.addItem(.separator())
    add(app, "Hide PoteNad", #selector(NSApplication.hide(_:)), "h")
    add(
      app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
      modifiers: [.command, .option])
    add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
    app.addItem(.separator())
    add(app, "Quit PoteNad", #selector(NSApplication.terminate(_:)), "q")

    let file = menu("File")
    add(file, "New Window", #selector(NSDocumentController.newDocument(_:)), "n")
    add(file, "New Tab", #selector(PoteNadDocumentController.newWindowForTab(_:)), "t")
    add(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
    let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
    recentItem.submenu = recentMenu
    recentMenu.delegate = self
    file.addItem(recentItem)
    file.addItem(.separator())
    add(file, "Close", #selector(NSWindow.performClose(_:)), "w")
    add(file, "Save", #selector(NSDocument.save(_:)), "s")
    add(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", modifiers: [.command, .shift])
    add(file, "Revert to Saved", #selector(NSDocument.revertToSaved(_:)))
    file.addItem(.separator())
    add(
      file, "Duplicate", #selector(NSDocument.duplicate(_:)), "s",
      modifiers: [.command, .shift, .option])
    add(file, "Rename…", #selector(NSDocument.rename(_:)))
    add(file, "Move To…", #selector(NSDocument.move(_:)))
    file.addItem(.separator())
    add(
      file, "Page Setup…", #selector(PoteNadDocument.pageSetup(_:)), "p",
      modifiers: [.command, .shift])
    add(file, "Print…", #selector(PoteNadDocument.printDocument(_:)), "p")

    let edit = menu("Edit")
    add(edit, "Undo", Selector(("undo:")), "z")
    add(edit, "Redo", Selector(("redo:")), "z", modifiers: [.command, .shift])
    edit.addItem(.separator())
    add(edit, "Cut", #selector(NSText.cut(_:)), "x")
    add(edit, "Copy", #selector(NSText.copy(_:)), "c")
    add(edit, "Paste", #selector(NSText.paste(_:)), "v")
    add(
      edit, "Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v",
      modifiers: [.command, .option, .shift])
    add(edit, "Delete", #selector(NSText.delete(_:)))
    add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
    edit.addItem(.separator())

    let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
    findItem.image = NSImage(
      systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
    let find = NSMenu(title: "Find")
    findItem.submenu = find
    edit.addItem(findItem)
    add(find, "Find…", #selector(Editor.showFind(_:)), "f")
    add(
      find, "Find and Replace…", #selector(Editor.showReplace(_:)), "f",
      modifiers: [.command, .option])
    add(find, "Find Next", #selector(Editor.findNext(_:)), "g")
    add(
      find, "Find Previous", #selector(Editor.findPrevious(_:)), "g", modifiers: [.command, .shift])
    find.addItem(.separator())
    add(
      find, "Use Selection for Find", #selector(NSTextView.performTextFinderAction(_:)), "e",
      tag: NSTextFinder.Action.setSearchString.rawValue)
    add(find, "Jump to Selection", #selector(NSTextView.centerSelectionInVisibleArea(_:)), "j")
    add(edit, "Go to Line…", #selector(Editor.goTo(_:)), "l")
    add(
      edit, "Select Lines…", #selector(Editor.selectLines(_:)), "l", modifiers: [.command, .shift])
    add(edit, "Time/Date", #selector(Editor.insertDate(_:)), "\u{F708}", modifiers: [])
    edit.addItem(.separator())

    if #available(macOS 15.2, *) {
      writingToolsItems = NSMenuItem.writingToolsItems
      writingToolsItems.forEach(edit.addItem)
      updateWritingToolsItem()
    }

    let spellingItem = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
    let spelling = NSMenu(title: "Spelling and Grammar")
    spellingItem.submenu = spelling
    edit.addItem(spellingItem)
    add(spelling, "Show Spelling and Grammar", #selector(NSTextView.showGuessPanel(_:)), ":")
    add(spelling, "Check Document Now", #selector(NSTextView.checkSpelling(_:)), ";")
    spelling.addItem(.separator())
    add(
      spelling, "Check Spelling While Typing",
      #selector(NSTextView.toggleContinuousSpellChecking(_:)))
    add(spelling, "Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:)))
    add(
      spelling, "Correct Spelling Automatically",
      #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)))

    let substitutionsItem = NSMenuItem(title: "Substitutions", action: nil, keyEquivalent: "")
    let substitutions = NSMenu(title: "Substitutions")
    substitutionsItem.submenu = substitutions
    edit.addItem(substitutionsItem)
    add(substitutions, "Show Substitutions", #selector(NSTextView.orderFrontSubstitutionsPanel(_:)))
    substitutions.addItem(.separator())
    add(substitutions, "Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)))
    add(substitutions, "Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:)))
    add(substitutions, "Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:)))

    let transformationsItem = NSMenuItem(title: "Transformations", action: nil, keyEquivalent: "")
    let transformations = NSMenu(title: "Transformations")
    transformationsItem.submenu = transformations
    edit.addItem(transformationsItem)
    add(transformations, "Make Upper Case", #selector(NSResponder.uppercaseWord(_:)))
    add(transformations, "Make Lower Case", #selector(NSResponder.lowercaseWord(_:)))
    add(transformations, "Capitalize", #selector(NSResponder.capitalizeWord(_:)))

    let speechItem = NSMenuItem(title: "Speech", action: nil, keyEquivalent: "")
    let speech = NSMenu(title: "Speech")
    speechItem.submenu = speech
    edit.addItem(speechItem)
    add(speech, "Start Speaking", #selector(NSTextView.startSpeaking(_:)))
    add(speech, "Stop Speaking", #selector(NSTextView.stopSpeaking(_:)))

    let format = menu("Format")
    add(
      format, "Show Fonts", #selector(NSFontManager.orderFrontFontPanel(_:)), "t",
      modifiers: [.command, .option])
    format.addItem(.separator())
    add(format, "Word Wrap", #selector(Editor.toggleWrap(_:)), "w", modifiers: [.command, .shift])
    let directionItem = NSMenuItem(title: "Writing Direction", action: nil, keyEquivalent: "")
    let direction = NSMenu(title: "Writing Direction")
    directionItem.submenu = direction
    format.addItem(directionItem)
    add(
      direction, "Default", #selector(NSResponder.makeBaseWritingDirectionNatural(_:)), "",
      modifiers: [])
    add(
      direction, "Left to Right", #selector(NSResponder.makeBaseWritingDirectionLeftToRight(_:)),
      "", modifiers: [])
    add(
      direction, "Right to Left", #selector(NSResponder.makeBaseWritingDirectionRightToLeft(_:)),
      "", modifiers: [])

    let view = menu("View")
    let zoomItem = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
    let zoom = NSMenu(title: "Zoom")
    zoomItem.submenu = zoom
    view.addItem(zoomItem)
    add(zoom, "Zoom In", #selector(Editor.zoomIn(_:)), "+")
    add(zoom, "Zoom Out", #selector(Editor.zoomOut(_:)), "-")
    add(zoom, "Actual Size", #selector(Editor.zoomReset(_:)), "0")
    view.addItem(.separator())
    add(view, "Show Status Bar", #selector(Editor.toggleStatus(_:)))
    view.addItem(.separator())
    add(
      view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f",
      modifiers: [.command, .control])

    let window = menu("Window")
    add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
    add(window, "Zoom", #selector(NSWindow.performZoom(_:)))
    window.addItem(.separator())
    add(
      window, "Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "[",
      modifiers: [.command, .shift])
    add(
      window, "Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "]",
      modifiers: [.command, .shift])
    add(window, "Move Tab to New Window", #selector(NSWindow.moveTabToNewWindow(_:)))
    add(window, "Merge All Windows", #selector(NSWindow.mergeAllWindows(_:)))
    window.addItem(.separator())
    add(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
    NSApp.windowsMenu = window

    let help = menu("Help")
    add(help, "PoteNad Help", #selector(showHelp(_:)), "?", target: self)
    help.addItem(.separator())
    add(help, "PoteNad on GitHub", #selector(openGitHub(_:)), target: self)
    NSApp.helpMenu = help
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard menu === recentMenu else { return }
    menu.removeAllItems()
    let urls = NSDocumentController.shared.recentDocumentURLs
    if urls.isEmpty {
      let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
    } else {
      for url in urls {
        let item = NSMenuItem(
          title: FileManager.default.displayName(atPath: url.path),
          action: #selector(openRecent(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        item.toolTip = url.path
        menu.addItem(item)
      }
      menu.addItem(.separator())
      let clear = NSMenuItem(
        title: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
      clear.target = self
      menu.addItem(clear)
    }
  }

  @objc func showAbout(_ sender: Any?) {
    NSApp.orderFrontStandardAboutPanel(options: [.version: ""])
  }

  @objc private func showSettings(_ sender: Any?) { settingsController.show() }

  @objc private func preferencesDidChange(_ notification: Notification) {
    updateWritingToolsItem()
  }

  @objc private func finishedRestoringWindows(_ notification: Notification) {
    didFinishRestoringWindows = true
    openDocumentAfterRestorationIfNeeded()
  }

  private func openDocumentAfterRestorationIfNeeded() {
    guard didFinishLaunching, didFinishRestoringWindows,
      let controller = NSDocumentController.shared as? PoteNadDocumentController
    else { return }
    if !controller.documents.isEmpty {
      SessionState.remove()
      return
    }
    if controller.pendingDocumentOpenCount > 0 { return }
    if AppPreferences.startupBehavior == .restorePreviousSession {
      do {
        if try controller.restoreSession() { return }
      } catch {
        if ProcessInfo.processInfo.environment["POTENAD_SESSION_STORE"] != nil {
          fputs("Session restore failed: \(error)\n", stderr)
        }
        NSApp.presentError(error)
      }
    } else {
      SessionState.remove()
    }
    controller.newDocument(nil)
  }

  private func updateWritingToolsItem() {
    if #available(macOS 15.2, *) {
      writingToolsItems.forEach { $0.isHidden = !AppPreferences.writingToolsEnabled }
    } else {
      writingToolsItems.forEach { $0.isHidden = true }
    }
  }

  @objc private func openRecent(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
      if let error { NSApp.presentError(error) }
    }
  }

  @objc private func clearRecent(_ sender: Any?) {
    NSDocumentController.shared.clearRecentDocuments(sender)
  }

  @objc private func showHelp(_ sender: Any?) {
    let alert = NSAlert()
    alert.messageText = "PoteNad Help"
    alert.informativeText =
      "Quick tips:\n\n• Press ⌘T for a new tab and ⌘N for a new window.\n• Press ⌘F to find text, or ⌥⌘F to find and replace.\n• Press ⇧⌘W to toggle word wrap.\n• Press F5 to insert the current time and date.\n• Put .LOG at the start of a file to add a timestamp when it opens."
    alert.icon = NSApp.applicationIconImage
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "View on GitHub")
    if alert.runModal() == .alertSecondButtonReturn { openGitHub(nil) }
  }

  @objc private func openGitHub(_ sender: Any?) {
    NSWorkspace.shared.open(URL(string: "https://github.com/PoteNad/potenad")!)
  }
}
