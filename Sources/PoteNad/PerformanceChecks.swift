#if PERFORMANCE
  import AppKit
  import TextCore

  @MainActor
  func benchmark() {
    func measure(_ name: String, count: Int = 20, _ action: () -> Void) {
      var samples: [Double] = []
      for _ in 0..<count {
        let start = DispatchTime.now().uptimeNanoseconds
        action()
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
      }
      let sorted = samples.sorted()
      print(
        String(
          format: "%@: first %.3f ms; median %.3f ms; p95 %.3f ms", name, samples[0],
          sorted[sorted.count / 2], sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))])
      )
      fflush(stdout)
    }
    // Include Auto Layout work, but not display scanout / WindowServer scheduling.
    for lines in [0, 10_000] {
      let doc = PoteNadDocument()
      doc.file = TextFile(
        text: String(repeating: "A line of ordinary text for latency measurements.\n", count: lines)
      )
      doc.makeWindowControllers()
      let editor = doc.editor!
      editor.wrap = true
      editor.applyWrap()
      editor.window!.contentView!.layoutSubtreeIfNeeded()
      measure("typing at start, \(lines) lines") {
        editor.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
      }
      measure("zoom 100↔110, \(lines) lines", count: 6) {
        editor.setZoom(110)
        editor.window!.contentView!.layoutSubtreeIfNeeded()
        editor.setZoom(100)
        editor.window!.contentView!.layoutSubtreeIfNeeded()
      }
      doc.close()
    }
    // The status bar counts characters or words after each edit, off the main thread; 3,000
    // lines is just under the size where counting waits for a pause in typing.
    for (lines, words) in [(3_000, false), (3_000, true), (10_000, false)] {
      UserDefaults.standard.set(words ? "words" : "characters", forKey: PreferenceKey.statusCount)
      let doc = PoteNadDocument()
      doc.file = TextFile(
        text: String(repeating: "A line of ordinary text for latency measurements.\n", count: lines)
      )
      doc.makeWindowControllers()
      let editor = doc.editor!
      editor.statusVisible = true
      editor.window!.contentView!.layoutSubtreeIfNeeded()
      measure("typing with \(words ? "word" : "character") counts, \(lines) lines") {
        editor.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        RunLoop.current.run(until: Date())
      }
      doc.close()
    }
    UserDefaults.standard.removeObject(forKey: PreferenceKey.statusCount)
    let input = String(repeating: "A line of plain text.\n", count: 100_000)
    measure("UTF-8 serialization, 2.1 MB", count: 5) {
      precondition(try! TextFile(text: input).data().count == input.utf8.count)
    }
    var index = LineIndex()
    let text = NSMutableString(string: input)
    index.rebuild(text)
    measure("line index insert at start, 100k lines", count: 50) {
      text.insert("x", at: 0)
      index.update(text, editedRange: NSRange(location: 0, length: 1), delta: 1)
    }
  }
#endif
