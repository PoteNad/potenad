import Foundation

public enum TextStatistics {
  /// Words as the system's text services find them, so languages without spaces count too.
  public static func wordCount(_ text: String) -> Int {
    var count = 0
    text.enumerateSubstrings(
      in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]
    ) { _, _, _, _ in
      count += 1
    }
    return count
  }
}
