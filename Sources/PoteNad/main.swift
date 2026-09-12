import AppKit

let app = NSApplication.shared
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
    print(
      "Launch check passed: \(documents.count) document(s), \(windows.count) visible editor window(s)."
    )
    fflush(stdout)
    app.terminate(nil)
  }
}
withExtendedLifetime(delegate) { app.run() }
