// Print the window id of the Connect IQ simulator's device window.
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list {
    let name = w[kCGWindowName as String] as? String ?? ""
    if name.hasPrefix("CIQ Simulator - ") {
        print(w[kCGWindowNumber as String]!)
        break
    }
}
