import AppKit
import Carbon.HIToolbox

// Plain assertion-based tests, run by tools/test.sh and by CI. No XCTest, to keep the build
// dependency-free (swiftc only, no Xcode project).

var failures = 0
func check(_ condition: Bool, _ what: String, line: UInt = #line) {
    if condition {
        print("  ok   \(what)")
    } else {
        print("  FAIL \(what)  (line \(line))")
        failures += 1
    }
}

print("Shortcut")
func key(_ code: Int, _ flags: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                     characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!
}
check(Shortcut.default.display == "⇧⌘2", "the default shortcut shows as ⇧⌘2")
check(Shortcut(event: key(kVK_ANSI_2, [.command, .shift]))?.display == "⇧⌘2", "⌘⇧2 is recorded with the unshifted key (2, not @)")
check(Shortcut(event: key(kVK_Space, [.control, .option]))?.display == "⌃⌥Space", "named keys get readable names")
check(Shortcut(event: key(kVK_F5, []))?.display == "F5", "a function key works on its own")
check(Shortcut(event: key(kVK_ANSI_A, [])) == nil, "a plain letter is rejected (it would hijack typing)")
check(Shortcut(event: key(kVK_ANSI_A, [.shift])) == nil, "⇧ alone isn't enough")

print("UpdateCheck")
check(UpdateCheck.isNewer("1.3.0", than: "1.2.9"), "1.3.0 is newer than 1.2.9")
check(UpdateCheck.isNewer("1.10.0", than: "1.9.9"), "1.10.0 is newer than 1.9.9 (not string order)")
check(UpdateCheck.isNewer("2.0.0", than: "1.99.99"), "2.0.0 is newer than 1.99.99")
check(!UpdateCheck.isNewer("1.3.1", than: "1.3.1"), "the same version is not newer")
check(!UpdateCheck.isNewer("1.2", than: "1.2.0"), "1.2 and 1.2.0 are the same")

print("Naming")
let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 13, hour: 9, minute: 5, second: 7).date!
check(Naming.fileName(date: date, app: nil, fileExtension: "png") == "Screenshot 2026-10-13 at 09.05.07.png", "no app: just the date")
check(Naming.fileName(date: date, app: "Safari", fileExtension: "jpg") == "Screenshot 2026-10-13 at 09.05.07 (Safari).jpg", "the app name goes in brackets")
check(Naming.fileName(date: date, app: "  ", fileExtension: "png") == "Screenshot 2026-10-13 at 09.05.07.png", "a blank app name is left out")
check(Naming.clean("Notes/Ideas: draft") == "Notes-Ideas- draft", "slashes and colons are replaced")
check(Naming.clean("A  very\tspaced\nname") == "A very spaced name", "whitespace collapses to single spaces")
check(Naming.clean(String(repeating: "x", count: 80)).count == 40, "long names are cut to 40 characters")

print("TextRecognition.rows")
func piece(_ x: CGFloat, _ y: CGFloat, _ text: String) -> (box: CGRect, text: String) { (CGRect(x: x, y: y, width: 0.2, height: 0.05), text) }
check(TextRecognition.rows([piece(0.1, 0.8, "Title"), piece(0.1, 0.5, "Body")]) == ["Title", "Body"], "rows go top to bottom")
check(TextRecognition.rows([piece(0.5, 0.6, "1.2.0"), piece(0.1, 0.61, "Version")]) == ["Version  1.2.0"], "pieces on one row join left to right")
check(TextRecognition.rows([piece(0.1, 0.2, "last"), piece(0.6, 0.9, "first")]) == ["first", "last"], "input order doesn't matter")
check(TextRecognition.rows([]) == [], "no text, no rows")

print(failures == 0 ? "\nAll tests passed." : "\n\(failures) test(s) failed.")
exit(failures == 0 ? 0 : 1)
