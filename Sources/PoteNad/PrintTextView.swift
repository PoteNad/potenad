import AppKit
import TextCore

final class PrintTextView: NSTextView {
  var headerTemplate = "", footerTemplate = "", filename = ""
  override var pageHeader: NSAttributedString { formatted(headerTemplate) }
  override var pageFooter: NSAttributedString { formatted(footerTemplate) }
  func formatted(_ template: String) -> NSAttributedString {
    var parts = ["", "", ""]
    var alignment = 1
    let chars = Array(template)
    var i = 0
    while i < chars.count {
      if chars[i] == "&", i + 1 < chars.count {
        i += 1
        switch chars[i] {
        case "l": alignment = 0
        case "c": alignment = 1
        case "r": alignment = 2
        case "f": parts[alignment] += filename
        case "p": parts[alignment] += String(NSPrintOperation.current?.currentPage ?? 1)
        case "d":
          parts[alignment] += DateFormatter.localizedString(
            from: Date(), dateStyle: .short, timeStyle: .none)
        case "t":
          parts[alignment] += DateFormatter.localizedString(
            from: Date(), dateStyle: .none, timeStyle: .short)
        case "&": parts[alignment] += "&"
        default: parts[alignment] += "&" + String(chars[i])
        }
      } else {
        parts[alignment].append(chars[i])
      }
      i += 1
    }
    let style = NSMutableParagraphStyle()
    style.tabStops = [
      NSTextTab(textAlignment: .center, location: frame.width / 2),
      NSTextTab(textAlignment: .right, location: frame.width),
    ]
    return NSAttributedString(
      string: parts.joined(separator: "\t"),
      attributes: [.font: NSFont.systemFont(ofSize: 10), .paragraphStyle: style])
  }
}
