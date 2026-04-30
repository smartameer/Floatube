import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            APIConfigTab()
                .tabItem { Label("API Config", systemImage: "key") }
        }
        .frame(width: 440, height: 320)
    }
}

// MARK: - Appearance

enum PlayerPlacement: String, CaseIterable {
    case center = "Center"
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
}

struct AppearanceTab: View {
    @State private var recorder = ShortcutRecorder()
    @State private var opacity: Double = {
        let stored = UserDefaults.standard.double(forKey: "floatube.playerOpacity")
        return stored > 0 ? stored : 1.0
    }()
    @State private var placement: PlayerPlacement = {
        let stored = UserDefaults.standard.string(forKey: "floatube.playerPlacement") ?? "Center"
        return PlayerPlacement(rawValue: stored) ?? .center
    }()
    @State private var showLastPlayed = UserDefaults.standard.object(forKey: "floatube.showLastPlayed") == nil ? true : UserDefaults.standard.bool(forKey: "floatube.showLastPlayed")
    @State private var defaultMode: String = UserDefaults.standard.string(forKey: "floatube.defaultMode") ?? "Search"
    @State private var playerMode: String = UserDefaults.standard.string(forKey: "floatube.playerMode") ?? "Inline"

    var body: some View {
        Form {
            Section("General") {
                Picker("Open", selection: $defaultMode) {
                    Text("Search").tag("Search")
                    Text("Playlist").tag("Playlist")
                }
                .onChange(of: defaultMode) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "floatube.defaultMode")
                }
                
                Toggle("Last Played", isOn: $showLastPlayed)
                    .onChange(of: showLastPlayed) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "floatube.showLastPlayed")
                    }
            }

            Section("Player") {
                Picker("Mode", selection: $playerMode) {
                    Text("Inline").tag("Inline")
                    Text("Detached").tag("Detached")
                }
                .onChange(of: playerMode) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "floatube.playerMode")
                }

                Picker("Placement", selection: $placement) {
                    ForEach(PlayerPlacement.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .onChange(of: placement) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: "floatube.playerPlacement")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Opacity")
                        Spacer()
                        Text("\(Int(opacity * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $opacity, in: 0.3...1.0, step: 0.1)
                        .onChange(of: opacity) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "floatube.playerOpacity")
                            NotificationCenter.default.post(name: .floatubeOpacityChanged, object: nil)
                        }
                }
            }

            Section("Shortcut") {
                HStack {
                    Text("Open Floatube")
                    Spacer()
                    Button {
                        if recorder.isRecording {
                            recorder.cancelRecording()
                        } else {
                            recorder.startRecording()
                        }
                    } label: {
                        Text(recorder.isRecording ? "Press shortcut…" : recorder.displayText)
                            .frame(minWidth: 110)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(recorder.isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Record Shortcut")
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            recorder.cancelRecording()
        }
    }
}

// MARK: - API Config

struct APIConfigTab: View {
    @State private var newKey = ""
    @State private var keys: [String] = KeychainService.loadAPIKeys()
    @State private var showingHelp = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("YouTube Data API")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("How to get an API key")
                }

                if showingHelp {
                    VStack(alignment: .leading, spacing: 6) {
                        helpStep("1", "Go to console.cloud.google.com")
                        helpStep("2", "Create a new project (or select existing)")
                        helpStep("3", "Go to APIs & Services → Library")
                        helpStep("4", "Search \"YouTube Data API v3\" and enable it")
                        helpStep("5", "Go to APIs & Services → Credentials")
                        helpStep("6", "Click Create Credentials → API Key")
                        helpStep("7", "Copy the key and paste it below")
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                EmptyView()
            }

            Section("Keys") {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.secondary)
                        Text(maskedKey(key))
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button {
                            KeychainService.removeAPIKey(at: index)
                            keys = KeychainService.loadAPIKeys()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Remove API Key")
                    }
                }

                HStack {
                    SecureField("Enter API key", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addKey() }

                    Button("Add") { addKey() }
                        .buttonStyle(.borderedProminent)
                        .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Add API Key")
                }

                Text("Add multiple keys for automatic fallback when quota is exceeded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func helpStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addKey() {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainService.addAPIKey(trimmed)
        keys = KeychainService.loadAPIKeys()
        newKey = ""
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)•••\(suffix)"
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            Text("Floatube")
                .font(.title.bold())

            Text("A lightweight macOS menu bar app for searching and watching YouTube videos. Summon it with a keyboard shortcut, search, and watch inline or in a floating detached player that stays on top of your other windows.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("v1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(width: 320, height: 240)
    }
}

// MARK: - Shortcut Recorder

@Observable
class ShortcutRecorder {
    var isRecording = false
    var displayText: String
    private var monitor: Any?

    init() {
        let keyCode = UserDefaults.standard.integer(forKey: "floatube.hotkeyKeyCode")
        let modRaw = UserDefaults.standard.integer(forKey: "floatube.hotkeyModifiers")
        if keyCode == 0 && modRaw == 0 {
            displayText = "⌘⇧Y"
        } else {
            displayText = Self.formatShortcut(
                keyCode: UInt16(keyCode),
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(modRaw))
            )
        }
    }

    func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 {
                self.cancelRecording()
                return nil
            }

            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !mods.isEmpty else { return event }

            UserDefaults.standard.set(Int(event.keyCode), forKey: "floatube.hotkeyKeyCode")
            UserDefaults.standard.set(Int(mods.rawValue), forKey: "floatube.hotkeyModifiers")
            self.displayText = Self.formatShortcut(keyCode: event.keyCode, modifiers: mods)
            self.isRecording = false
            self.removeMonitor()
            NotificationCenter.default.post(name: .floatubeHotkeyChanged, object: nil)
            return nil
        }
    }

    func cancelRecording() {
        isRecording = false
        removeMonitor()
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    static func formatShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += keyName(for: keyCode)
        return result
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            51: "⌫", 53: "⎋",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 105: "F13", 109: "F10", 111: "F12", 118: "F4",
            120: "F2", 122: "F1",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}
