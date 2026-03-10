import SwiftUI
import Combine

// MARK: - Key Combination

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var displayChar: String

    static let empty = KeyCombo(keyCode: 0, modifiers: 0, displayChar: "")
    var isEmpty: Bool { keyCode == 0 && modifiers == 0 && displayChar.isEmpty }

    /// 只保留 ⌃⌥⇧⌘ 四个修饰键位
    static let modMask: UInt =
        NSEvent.ModifierFlags.control.rawValue |
        NSEvent.ModifierFlags.option.rawValue |
        NSEvent.ModifierFlags.shift.rawValue |
        NSEvent.ModifierFlags.command.rawValue

    var displayString: String {
        if isEmpty { return "未设置" }
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(displayChar.uppercased())
        return parts.joined(separator: " ")
    }

    func matches(_ event: NSEvent) -> Bool {
        guard !isEmpty else { return false }
        let eventMods = event.modifierFlags.rawValue & Self.modMask
        return event.keyCode == keyCode && eventMods == modifiers
    }

    static func from(event: NSEvent) -> KeyCombo {
        let mods = event.modifierFlags.rawValue & modMask
        let char = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return KeyCombo(keyCode: event.keyCode, modifiers: mods, displayChar: char)
    }
}

// MARK: - Shortcut Settings

final class ShortcutSettings: ObservableObject {
    static let shared = ShortcutSettings()

    @Published var openFile: KeyCombo         { didSet { save("openFile", openFile) } }
    @Published var startScreenshot: KeyCombo   { didSet { save("startScreenshot", startScreenshot) } }
    @Published var pasteOCR: KeyCombo          { didSet { save("pasteOCR", pasteOCR) } }
    @Published var repeatScreenshot: KeyCombo  { didSet { save("repeatScreenshot", repeatScreenshot) } }
    @Published var silentScreenshot: KeyCombo  { didSet { save("silentScreenshot", silentScreenshot) } }
    @Published var scanQR: KeyCombo            { didSet { save("scanQR", scanQR) } }

    // 界面切换
    @Published var navScreenshot: KeyCombo     { didSet { save("navScreenshot", navScreenshot) } }
    @Published var navBatch: KeyCombo          { didSet { save("navBatch", navBatch) } }
    @Published var navDocument: KeyCombo       { didSet { save("navDocument", navDocument) } }
    @Published var navQR: KeyCombo             { didSet { save("navQR", navQR) } }

    private static let ctrlOpt: UInt = NSEvent.ModifierFlags([.control, .option]).rawValue & KeyCombo.modMask
    private static let opt: UInt     = NSEvent.ModifierFlags.option.rawValue & KeyCombo.modMask
    private static let cmd: UInt     = NSEvent.ModifierFlags.command.rawValue & KeyCombo.modMask

    static let defaultCombos: [String: KeyCombo] = [
        "openFile":         KeyCombo(keyCode: 31, modifiers: opt,     displayChar: "O"),
        "startScreenshot":  KeyCombo(keyCode: 8,  modifiers: ctrlOpt, displayChar: "C"),
        "pasteOCR":         KeyCombo(keyCode: 9,  modifiers: ctrlOpt, displayChar: "V"),
        "repeatScreenshot": KeyCombo(keyCode: 15, modifiers: ctrlOpt, displayChar: "R"),
        "silentScreenshot": KeyCombo(keyCode: 1,  modifiers: ctrlOpt, displayChar: "S"),
        "scanQR":           KeyCombo(keyCode: 12, modifiers: ctrlOpt, displayChar: "Q"),
        "navScreenshot":    KeyCombo(keyCode: 18, modifiers: cmd,     displayChar: "1"),
        "navBatch":         KeyCombo(keyCode: 19, modifiers: cmd,     displayChar: "2"),
        "navDocument":      KeyCombo(keyCode: 20, modifiers: cmd,     displayChar: "3"),
        "navQR":            KeyCombo(keyCode: 21, modifiers: cmd,     displayChar: "4"),
    ]

    private init() {
        openFile         = Self.load("openFile")         ?? Self.defaultCombos["openFile"]!
        startScreenshot  = Self.load("startScreenshot")  ?? Self.defaultCombos["startScreenshot"]!
        pasteOCR         = Self.load("pasteOCR")         ?? Self.defaultCombos["pasteOCR"]!
        repeatScreenshot = Self.load("repeatScreenshot") ?? Self.defaultCombos["repeatScreenshot"]!
        silentScreenshot = Self.load("silentScreenshot") ?? Self.defaultCombos["silentScreenshot"]!
        scanQR           = Self.load("scanQR")           ?? Self.defaultCombos["scanQR"]!
        navScreenshot    = Self.load("navScreenshot")    ?? Self.defaultCombos["navScreenshot"]!
        navBatch         = Self.load("navBatch")         ?? Self.defaultCombos["navBatch"]!
        navDocument      = Self.load("navDocument")      ?? Self.defaultCombos["navDocument"]!
        navQR            = Self.load("navQR")            ?? Self.defaultCombos["navQR"]!
    }

    func resetDefaults() {
        openFile         = Self.defaultCombos["openFile"]!
        startScreenshot  = Self.defaultCombos["startScreenshot"]!
        pasteOCR         = Self.defaultCombos["pasteOCR"]!
        repeatScreenshot = Self.defaultCombos["repeatScreenshot"]!
        silentScreenshot = Self.defaultCombos["silentScreenshot"]!
        scanQR           = Self.defaultCombos["scanQR"]!
        navScreenshot    = Self.defaultCombos["navScreenshot"]!
        navBatch         = Self.defaultCombos["navBatch"]!
        navDocument      = Self.defaultCombos["navDocument"]!
        navQR            = Self.defaultCombos["navQR"]!
    }

    private func save(_ key: String, _ combo: KeyCombo) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: "shortcut.\(key)")
        }
    }

    private static func load(_ key: String) -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: "shortcut.\(key)") else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }
}

// MARK: - App Notifications

extension Notification.Name {
    static let navigateTo              = Notification.Name("MapleOCR.navigateTo")
    static let triggerScreenshotOCR    = Notification.Name("MapleOCR.triggerScreenshotOCR")
    static let triggerPasteOCR         = Notification.Name("MapleOCR.triggerPasteOCR")
    static let triggerQRScan           = Notification.Name("MapleOCR.triggerQRScan")
    static let triggerOpenFileBatch       = Notification.Name("MapleOCR.triggerOpenFileBatch")
    static let triggerOpenFileDoc         = Notification.Name("MapleOCR.triggerOpenFileDoc")
    static let triggerSilentScreenshotOCR = Notification.Name("MapleOCR.triggerSilentScreenshotOCR")
}

// MARK: - Shortcut Recorder Button

struct ShortcutRecorderButton: View {
    @Binding var combo: KeyCombo
    @State private var isRecording = false
    @State private var monitorRef = MonitorRef()

    private final class MonitorRef {
        var monitor: Any?
        func remove() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }
        deinit { remove() }
    }

    var body: some View {
        Button {
            if isRecording {
                monitorRef.remove()
                isRecording = false
            } else {
                startRecording()
            }
        } label: {
            Text(isRecording ? "按下快捷键…" : combo.displayString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(isRecording ? .accentColor : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { monitorRef.remove() }
    }

    private func startRecording() {
        isRecording = true
        monitorRef.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape → 取消
                monitorRef.remove()
                isRecording = false
                return nil
            }
            let newCombo = KeyCombo.from(event: event)
            // 至少需要一个修饰键
            if newCombo.modifiers != 0 {
                combo = newCombo
                monitorRef.remove()
                isRecording = false
                return nil
            }
            return nil // 录制中，消费所有按键
        }
    }
}
