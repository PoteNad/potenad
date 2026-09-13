import AppKit

let app = NSApplication.shared
let documentController = PoteNadDocumentController()
AppPreferences.registerDefaults()
AppPreferences.applyAppearance()
if let path = ProcessInfo.processInfo.environment["POTENAD_OPEN_CHECK"] {
  do {
    try Data("Opened from Finder\n".utf8).write(to: URL(fileURLWithPath: path))
  } catch {
    fputs("Open check failed to create its fixture: \(error)\n", stderr)
    exit(1)
  }
}
#if PERFORMANCE
  if CommandLine.arguments.contains("--benchmark") {
    benchmark()
    exit(0)
  }
#endif
#if DEBUG
  if CommandLine.arguments.contains("--smoke-test") {
    do {
      try smokeTest()
      exit(0)
    } catch {
      fputs("Smoke test failed: \(error)\n", stderr)
      exit(1)
    }
  }
#endif
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
if ProcessInfo.processInfo.environment["POTENAD_LAUNCH_CHECK"] == "1" {
  DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    let documents = NSDocumentController.shared.documents
    let windows = documents.flatMap(\.windowControllers).compactMap(\.window)
    guard documents.count == 1, windows.count == 1,
      windows.allSatisfy({ $0.isVisible && $0.frame.width > 100 && $0.frame.height > 100 })
    else {
      fputs(
        "Launch check failed: expected one visible untitled editor window; found \(documents.count) documents and \(windows.count) windows.\n",
        stderr)
      exit(1)
    }
    guard let controller = NSDocumentController.shared as? PoteNadDocumentController else {
      fputs("Launch check failed: expected the PoteNad document controller.\n", stderr)
      exit(1)
    }
    windows[0].makeKeyAndOrderFront(nil)
    controller.newWindowForTab(nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      let tabDocuments = controller.documents
      let tabWindows = tabDocuments.flatMap(\.windowControllers).compactMap(\.window)
      guard tabDocuments.count == 2, tabWindows.count == 2,
        tabWindows.allSatisfy({ $0.tabbedWindows?.count == 2 })
      else {
        let tabCounts = tabWindows.map { $0.tabbedWindows?.count ?? 1 }
        fputs(
          "Launch check failed: expected two documents in one native tab group; found \(tabDocuments.count) documents, \(tabWindows.count) windows, and tab counts \(tabCounts).\n",
          stderr)
        exit(1)
      }
      (tabWindows[0].tabGroup?.selectedWindow ?? NSApp.keyWindow)?.performClose(nil)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        let remainingWindows = controller.documents.flatMap(\.windowControllers).compactMap(\.window)
        guard controller.documents.count == 1, remainingWindows.count == 1 else {
          fputs(
            "Launch check failed: Command-W behavior left \(controller.documents.count) documents and \(remainingWindows.count) windows.\n",
            stderr)
          exit(1)
        }
        remainingWindows[0].performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
          guard controller.documents.isEmpty else {
            fputs("Launch check failed: closing the final tab did not close the window.\n", stderr)
            exit(1)
          }
          print("Launch check passed: native tabs open and close before their containing window.")
          fflush(stdout)
          app.terminate(nil)
        }
      }
    }
  }
}
if let path = ProcessInfo.processInfo.environment["POTENAD_SAVE_CHECK"] {
  DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    guard let document = documentController.documents.first as? PoteNadDocument,
      let editor = document.editor
    else {
      fputs("Save check failed: expected an initial document.\n", stderr)
      exit(1)
    }
    editor.textView.insertText(
      "Saved without crashing\n", replacementRange: editor.textView.selectedRange())
    let url = URL(fileURLWithPath: path)
    document.save(
      to: url, ofType: documentController.defaultType ?? "public.plain-text",
      for: .saveAsOperation
    ) { error in
      if let error {
        fputs("Save check failed: \(error)\n", stderr)
        exit(1)
      }
      editor.loadText("Saved without crashing\nSaved again\n")
      document.updateChangeCount(.changeDone)
      document.save(
        to: url, ofType: document.fileType ?? "public.plain-text", for: .saveOperation
      ) { error in
        if let error {
          fputs("Save check failed: \(error)\n", stderr)
          exit(1)
        }
        guard !document.isDocumentEdited,
          document.windowControllers.allSatisfy({ $0.window?.isDocumentEdited == false })
        else {
          fputs("Save check failed: the edited indicator remained visible.\n", stderr)
          exit(1)
        }
        do {
          guard
            try String(contentsOf: url, encoding: .utf8)
              == "Saved without crashing\nSaved again\n"
          else {
            fputs("Save check failed: saved contents did not match.\n", stderr)
            exit(1)
          }
          try FileManager.default.removeItem(at: url.deletingLastPathComponent())
        } catch {
          fputs("Save check failed: \(error)\n", stderr)
          exit(1)
        }
        print("Save check passed: new and existing documents save without crashing.")
        fflush(stdout)
        document.close()
        app.terminate(nil)
      }
    }
  }
}
if let path = ProcessInfo.processInfo.environment["POTENAD_OPEN_CHECK"] {
  DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    let url = URL(fileURLWithPath: path)
    let documents = documentController.documents.compactMap { $0 as? PoteNadDocument }
    guard documents.count == 1,
      documents[0].fileURL?.standardizedFileURL == url.standardizedFileURL,
      documents[0].editor?.textView.string == "Opened from Finder\n"
    else {
      let names = documents.map(\.displayName)
      fputs(
        "Open check failed: expected only the requested file; found \(documents.count) documents named \(names).\n",
        stderr)
      exit(1)
    }
    documents[0].close()
    do {
      try FileManager.default.removeItem(at: url.deletingLastPathComponent())
    } catch {
      fputs("Open check failed to clean up: \(error)\n", stderr)
      exit(1)
    }
    print("Open check passed: opening a file at launch does not leave an untitled tab.")
    fflush(stdout)
    app.terminate(nil)
  }
}
if ProcessInfo.processInfo.environment["POTENAD_SESSION_PREPARE"] == "1" {
  guard AppPreferences.startupBehavior == .restorePreviousSession else {
    fputs("Session check failed: restore preference was not applied.\n", stderr)
    exit(1)
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    guard let first = documentController.documents.first as? PoteNadDocument,
      let firstEditor = first.editor
    else {
      fputs("Session check failed: expected an initial document.\n", stderr)
      exit(1)
    }
    firstEditor.textView.insertText(
      "First restored draft", replacementRange: firstEditor.textView.selectedRange())
    first.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
    documentController.newWindowForTab(nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      guard documentController.documents.count == 2,
        let second = documentController.documents.first(where: { $0 !== first })
          as? PoteNadDocument,
        let secondEditor = second.editor
      else {
        fputs("Session check failed: expected a second tab.\n", stderr)
        exit(1)
      }
      secondEditor.textView.insertText(
        "Second restored draft", replacementRange: secondEditor.textView.selectedRange())
      app.terminate(nil)
    }
  }
}
if ProcessInfo.processInfo.environment["POTENAD_SESSION_VERIFY"] == "1" {
  DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    let documents = documentController.documents.compactMap { $0 as? PoteNadDocument }
    let contents = Set(documents.compactMap { $0.editor?.textView.string })
    let windows = documents.flatMap(\.windowControllers).compactMap(\.window)
    guard contents == ["First restored draft", "Second restored draft"],
      windows.count == 2, windows.allSatisfy({ $0.tabbedWindows?.count == 2 })
    else {
      fputs(
        "Session check failed: expected two restored drafts in one tab group; found \(documents.count) documents and \(windows.count) windows.\n",
        stderr)
      exit(1)
    }
    documents.forEach { $0.close() }
    print("Session check passed: unsaved drafts and their native tab group were restored.")
    fflush(stdout)
    app.terminate(nil)
  }
}
if ProcessInfo.processInfo.environment["POTENAD_SESSION_VERIFY_EMPTY"] == "1" {
  DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    let documents = documentController.documents.compactMap { $0 as? PoteNadDocument }
    let contents = documents.compactMap { $0.editor?.textView.string }
    guard documents.count == 1, contents == [""] else {
      fputs("Session check failed: explicitly closed drafts returned on the next launch.\n", stderr)
      exit(1)
    }
    documents.forEach { $0.close() }
    print("Session cleanup check passed: explicitly closed drafts stayed closed.")
    fflush(stdout)
    app.terminate(nil)
  }
}
withExtendedLifetime((delegate, documentController)) { app.run() }
