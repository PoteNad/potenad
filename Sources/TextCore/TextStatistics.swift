import Foundation

public enum TextStatistics {
  /// Characters as a reader counts them: an emoji or an accented letter is one.
  public static func characterCount(_ text: String) -> Int { text.count }

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
