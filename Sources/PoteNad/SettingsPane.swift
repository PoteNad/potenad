import AppKit
import TextCore

enum PreferenceKey {
  static let appearance = "appearance"
  static let fontName = "fontName"
  static let fontSize = "fontSize"
  static let wrap = "wrap"
  static let status = "status"
  static let encoding = "encoding"
  static let lineEnding = "lineEnding"
  static let checkSpelling = "checkSpelling"
  static let writingTools = "writingTools"
  static let startupBehavior = "startupBehavior"
  /// Whether the status bar counts characters or words.
  static let statusCount = "statusCount"
}

enum AppAppearance: String, CaseIterable {
  case system
  case light
  case dark

  var title: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var value: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}

enum StartupBehavior: String, CaseIterable {
  case newDocument
  case restorePreviousSession

  var title: String {
    switch self {
    case .newDocument: "New document"
    case .restorePreviousSession: "Restore previous session"
    }
  }
}

extension Notification.Name {
  static let editorDefaultsDidChange = Notification.Name("EditorDefaultsDidChange")
}

enum AppPreferences {
  static func registerDefaults() {
    UserDefaults.standard.register(defaults: [
      PreferenceKey.appearance: AppAppearance.system.rawValue,
      PreferenceKey.fontName: "Menlo",
      PreferenceKey.fontSize: 12.0,
      PreferenceKey.wrap: true,
      PreferenceKey.status: true,
      PreferenceKey.encoding: TextEncoding.utf8.rawValue,
      PreferenceKey.lineEnding: LineEnding.lf.rawValue,
      PreferenceKey.checkSpelling: false,
      PreferenceKey.writingTools: false,
      PreferenceKey.startupBehavior: StartupBehavior.newDocument.rawValue,
    ])
  }

  static var appearance: AppAppearance {
    AppAppearance(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.appearance) ?? "")
      ?? .system
  }

  @MainActor static func applyAppearance() { NSApp.appearance = appearance.value }

  static var font: NSFont {
    let size = UserDefaults.standard.double(forKey: PreferenceKey.fontSize)
    let validSize = size.isFinite && (1...512).contains(size) ? size : 12
    return NSFont(
      name: UserDefaults.standard.string(forKey: PreferenceKey.fontName) ?? "Menlo",
      size: validSize) ?? .monospacedSystemFont(ofSize: validSize, weight: .regular)
  }

  static var encoding: TextEncoding {
    TextEncoding(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.encoding) ?? "")
      ?? .utf8
  }

  static var lineEnding: LineEnding {
    LineEnding(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.lineEnding) ?? "")
      ?? .lf
  }

  static var writingToolsEnabled: Bool {
    UserDefaults.standard.bool(forKey: PreferenceKey.writingTools)
  }

  static var startupBehavior: StartupBehavior {
    StartupBehavior(
      rawValue: UserDefaults.standard.string(forKey: PreferenceKey.startupBehavior) ?? "")
      ?? .newDocument
  }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSMenuDelegate {
  private let appearanceControl = NSSegmentedControl(
    labels: AppAppearance.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
  private let startupBehavior = NSPopUpButton()
  private let family = NSPopUpButton()
  private let face = NSPopUpButton()
  private let size = NSTextField()
  private let sizeStepper = NSStepper()
  private let wrapping = NSButton(
    checkboxWithTitle: "Word wrap", target: nil, action: nil)
  private let statusBar = NSButton(
    checkboxWithTitle: "Show status bar", target: nil, action: nil)
  private let spelling = NSButton(
    checkboxWithTitle: "Check spelling while typing", target: nil, action: nil)
  private let writingTools = NSButton(
    checkboxWithTitle: "Enable Writing Tools (Apple Intelligence)", target: nil, action: nil)
  private let encoding = NSPopUpButton()
  private let lineEnding = NSPopUpButton()
  private var fontNames: [String] = []
  private var familiesLoaded = false
  private var facesLoaded = false
  private let number = NumberFormatter()

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "PoteNad Settings"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
    window.standardWindowButton(.zoomButton)?.isEnabled = false

    number.numberStyle = .decimal
    number.maximumFractionDigits = 2
    number.usesGroupingSeparator = false
    size.formatter = number
    size.delegate = self
    size.toolTip = "Font size in points (1–512)"
    sizeStepper.minValue = 1
    sizeStepper.maxValue = 512
    sizeStepper.increment = 1
    sizeStepper.valueWraps = false
    sizeStepper.autorepeat = true

    appearanceControl.target = self
    appearanceControl.action = #selector(changeAppearance)
    startupBehavior.target = self
    startupBehavior.action = #selector(changeOption)
    family.menu?.delegate = self
    face.menu?.delegate = self
    family.target = self
    family.action = #selector(changeFamily)
    face.target = self
    face.action = #selector(changeFace)
    sizeStepper.target = self
    sizeStepper.action = #selector(changeSize)
    wrapping.target = self
    wrapping.action = #selector(changeOption)
    statusBar.target = self
    statusBar.action = #selector(changeOption)
    spelling.target = self
    spelling.action = #selector(changeOption)
    writingTools.target = self
    writingTools.action = #selector(changeOption)
    if #unavailable(macOS 15.2) {
      writingTools.isEnabled = false
      writingTools.toolTip = "Requires macOS 15.2 or newer"
    }
    encoding.target = self
    encoding.action = #selector(changeOption)
    lineEnding.target = self
    lineEnding.action = #selector(changeOption)

    func describe(_ control: NSView, _ text: String) {
      control.toolTip = text
      control.setAccessibilityHelp(text)
    }
    describe(appearanceControl, "Follow the system appearance or always use Light or Dark.")
    describe(
      startupBehavior,
      "Start with a new document or reopen the windows, tabs, and unsaved drafts that were open when PoteNad last quit.")
    describe(
      family,
      "Change the editor's display font without adding formatting to plain-text files.")
    describe(
      face,
      "Change the editor's typeface without adding formatting to plain-text files.")
    describe(size, "Set the editor's font size in points, from 1 to 512.")
    describe(sizeStepper, "Increase or decrease the editor's font size.")
    describe(
      encoding,
      "Set the encoding for new files. Existing files keep their detected encoding.")
    describe(
      lineEnding,
      "Set the line endings for new files. Existing files keep their detected line endings.")
    describe(wrapping, "Wrap long lines visually without modifying the file.")
    describe(
      statusBar,
      "Show the cursor position, character count, encoding, line endings, and zoom level.")
    describe(spelling, "Underline possible spelling mistakes while you type.")
    describe(
      writingTools,
      "Show Apple's Writing Tools in the Edit menu when they are available.")
    if #unavailable(macOS 15.2) {
      writingTools.toolTip = "Requires macOS 15.2 or newer."
      writingTools.setAccessibilityHelp("Requires macOS 15.2 or newer.")
    }

    for value in TextEncoding.allCases {
      encoding.addItem(withTitle: value.displayName)
      encoding.lastItem?.representedObject = value.rawValue
    }
    for value in StartupBehavior.allCases {
      startupBehavior.addItem(withTitle: value.title)
      startupBehavior.lastItem?.representedObject = value.rawValue
    }
    for value in LineEnding.allCases {
      lineEnding.addItem(withTitle: value.displayName)
      lineEnding.lastItem?.representedObject = value.rawValue
    }

    let sizeControl = NSStackView(views: [size, sizeStepper])
    sizeControl.orientation = .horizontal
    sizeControl.spacing = 6
    let generalGrid = NSGridView(views: [
      [NSTextField(labelWithString: "Appearance:"), appearanceControl],
      [NSTextField(labelWithString: "When PoteNad opens:"), startupBehavior],
    ])
    let textGrid = NSGridView(views: [
      [NSTextField(labelWithString: "Default font:"), family],
      [NSTextField(labelWithString: "Typeface:"), face],
      [NSTextField(labelWithString: "Size:"), sizeControl],
      [NSTextField(labelWithString: "Default encoding:"), encoding],
      [NSTextField(labelWithString: "Default line endings:"), lineEnding],
    ])
    for grid in [generalGrid, textGrid] {
      grid.rowSpacing = 8
      grid.columnSpacing = 12
      grid.column(at: 0).xPlacement = .trailing
      grid.column(at: 1).width = 260
    }
    size.widthAnchor.constraint(equalToConstant: 90).isActive = true

    let restore = NSButton(
      title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
    describe(restore, "Reset every setting to its original value.")
    let options = NSStackView(views: [wrapping, statusBar, spelling, writingTools])
    options.orientation = .vertical
    options.alignment = .leading
    options.spacing = 6
    let buttons = NSStackView(views: [NSView(), restore])
    buttons.orientation = .horizontal

    func group(_ title: String, _ body: NSView) -> NSStackView {
      let heading = NSTextField(labelWithString: title)
      heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
      let stack = NSStackView(views: [heading, body])
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = 8
      return stack
    }

    let general = group("General", generalGrid)
    let text = group("Text", textGrid)
    let editing = group("Editing", options)
    let content = NSStackView(views: [general, text, editing, buttons])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 16
    content.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
    window.contentView = content
    generalGrid.widthAnchor.constraint(equalTo: textGrid.widthAnchor).isActive = true
    buttons.widthAnchor.constraint(equalTo: generalGrid.widthAnchor).isActive = true
    syncControls()
  }

  required init?(coder: NSCoder) { fatalError() }

  func show() {
    syncControls()
    showWindow(nil)
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeFirstResponder(nil)
  }

  private func syncControls() {
    let font = AppPreferences.font
    appearanceControl.selectedSegment =
      AppAppearance.allCases.firstIndex(of: AppPreferences.appearance) ?? 0
    startupBehavior.selectItem(withTitle: AppPreferences.startupBehavior.title)
    family.removeAllItems()
    family.addItem(withTitle: font.familyName ?? "Menlo")
    fontNames = [font.fontName]
    face.removeAllItems()
    face.addItem(withTitle: font.fontDescriptor.object(forKey: .face) as? String ?? "Regular")
    size.stringValue = number.string(from: NSNumber(value: Double(font.pointSize))) ?? "12"
    sizeStepper.doubleValue = Double(font.pointSize)
    wrapping.state = UserDefaults.standard.bool(forKey: PreferenceKey.wrap) ? .on : .off
    statusBar.state = UserDefaults.standard.bool(forKey: PreferenceKey.status) ? .on : .off
    spelling.state = UserDefaults.standard.bool(forKey: PreferenceKey.checkSpelling) ? .on : .off
    writingTools.state = AppPreferences.writingToolsEnabled ? .on : .off
    encoding.selectItem(withTitle: AppPreferences.encoding.displayName)
    lineEnding.selectItem(withTitle: AppPreferences.lineEnding.displayName)
    familiesLoaded = false
    facesLoaded = false
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === family.menu, !familiesLoaded {
      let selected = family.titleOfSelectedItem
      family.removeAllItems()
      family.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
      if let selected { family.selectItem(withTitle: selected) }
      familiesLoaded = true
    } else if menu === face.menu, !facesLoaded {
      updateFaces()
    }
  }

  private func updateFaces() {
    let familyName = family.titleOfSelectedItem ?? "Menlo"
    let members = (NSFontManager.shared.availableMembers(ofFontFamily: familyName) ?? []).compactMap
    {
      member -> (String, String)? in
      guard let name = member[0] as? String, let title = member[1] as? String else { return nil }
      return (name, title)
    }
    face.removeAllItems()
    fontNames = members.map(\.0)
    face.addItems(withTitles: members.map(\.1))
    face.selectItem(withTitle: "Regular")
    facesLoaded = true
  }

  private func applyFont() {
    let text = size.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let points = Double(text.replacingOccurrences(of: number.decimalSeparator, with: ".")),
      points.isFinite, (1...512).contains(points),
      fontNames.indices.contains(face.indexOfSelectedItem),
      let font = NSFont(name: fontNames[face.indexOfSelectedItem], size: points)
    else { return }
    UserDefaults.standard.set(font.fontName, forKey: PreferenceKey.fontName)
    UserDefaults.standard.set(font.pointSize, forKey: PreferenceKey.fontSize)
    sizeStepper.doubleValue = Double(font.pointSize)
    notifyChange()
  }

  func controlTextDidChange(_ notification: Notification) { applyFont() }

  func controlTextDidEndEditing(_ notification: Notification) {
    size.stringValue =
      number.string(from: NSNumber(value: Double(AppPreferences.font.pointSize))) ?? "12"
    sizeStepper.doubleValue = Double(AppPreferences.font.pointSize)
  }

  func control(
    _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
  ) -> Bool {
    guard control === size else { return false }
    if commandSelector == #selector(NSResponder.moveUp(_:)) {
      adjustSize(by: 1)
      return true
    }
    if commandSelector == #selector(NSResponder.moveDown(_:)) {
      adjustSize(by: -1)
      return true
    }
    return false
  }

  @objc private func changeAppearance() {
    guard AppAppearance.allCases.indices.contains(appearanceControl.selectedSegment) else { return }
    let value = AppAppearance.allCases[appearanceControl.selectedSegment]
    UserDefaults.standard.set(value.rawValue, forKey: PreferenceKey.appearance)
    AppPreferences.applyAppearance()
  }

  @objc private func changeFamily() {
    updateFaces()
    applyFont()
  }

  @objc private func changeFace() { applyFont() }

  @objc private func changeSize() {
    size.stringValue =
      number.string(from: NSNumber(value: sizeStepper.doubleValue))
      ?? String(Int(sizeStepper.doubleValue))
    applyFont()
  }

  private func adjustSize(by amount: Double) {
    let current = Double(size.stringValue) ?? sizeStepper.doubleValue
    sizeStepper.doubleValue = min(sizeStepper.maxValue, max(sizeStepper.minValue, current + amount))
    changeSize()
  }

  @objc private func changeOption() {
    UserDefaults.standard.set(wrapping.state == .on, forKey: PreferenceKey.wrap)
    UserDefaults.standard.set(statusBar.state == .on, forKey: PreferenceKey.status)
    UserDefaults.standard.set(spelling.state == .on, forKey: PreferenceKey.checkSpelling)
    UserDefaults.standard.set(writingTools.state == .on, forKey: PreferenceKey.writingTools)
    if let value = startupBehavior.selectedItem?.representedObject as? String {
      UserDefaults.standard.set(value, forKey: PreferenceKey.startupBehavior)
    }
    if let value = encoding.selectedItem?.representedObject as? String {
      UserDefaults.standard.set(value, forKey: PreferenceKey.encoding)
    }
    if let value = lineEnding.selectedItem?.representedObject as? String {
      UserDefaults.standard.set(value, forKey: PreferenceKey.lineEnding)
    }
    notifyChange()
  }

  @objc private func restoreDefaults() {
    for key in [
      PreferenceKey.appearance, PreferenceKey.fontName, PreferenceKey.fontSize, PreferenceKey.wrap,
      PreferenceKey.status, PreferenceKey.encoding, PreferenceKey.lineEnding,
      PreferenceKey.checkSpelling, PreferenceKey.writingTools,
      PreferenceKey.startupBehavior,
    ] {
      UserDefaults.standard.removeObject(forKey: key)
    }
    AppPreferences.registerDefaults()
    AppPreferences.applyAppearance()
    syncControls()
    notifyChange()
  }

  private func notifyChange() {
    NotificationCenter.default.post(name: .editorDefaultsDidChange, object: nil)
  }
}
