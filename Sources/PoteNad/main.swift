import AppKit

let app = NSApplication.shared
let documentController = PoteNadDocumentController()
AppPreferences.registerDefaults()
AppPreferences.applyAppearance()
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
      fputs("Launch check failed: expected one visible untitled editor window.\n", stderr)
      exit(1)
    }
    guard let controller = NSDocumentController.shared as? PoteNadDocumentController else {
      fputs("Launch check failed: expected the PoteNad document controller.\n", stderr)
      exit(1)
    }
    controller.newWindowForTab(nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      let tabDocuments = controller.documents
      let tabWindows = tabDocuments.flatMap(\.windowControllers).compactMap(\.window)
      guard tabDocuments.count == 2, tabWindows.count == 2,
        tabWindows.allSatisfy({ $0.tabbedWindows?.count == 2 })
      else {
        fputs("Launch check failed: expected two documents in one native tab group.\n", stderr)
        exit(1)
      }
      NSApp.keyWindow?.performClose(nil)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        let remainingWindows = controller.documents.flatMap(\.windowControllers).compactMap(\.window)
        guard controller.documents.count == 1, remainingWindows.count == 1 else {
          fputs("Launch check failed: Command-W behavior did not close only the active tab.\n", stderr)
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
withExtendedLifetime((delegate, documentController)) { app.run() }
