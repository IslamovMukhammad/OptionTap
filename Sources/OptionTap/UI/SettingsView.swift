import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var confirmClear = false

    var body: some View {
        @Bindable var state = state
        Form {
            if !state.isTrusted {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Accessibility permission needed", systemImage: "hand.raised.fill")
                            .font(.headline)
                        Text("OptionTap needs it to notice the ⌥ gesture in any app and to paste into the app you were using.")
                            .foregroundStyle(.secondary)
                        Button("Grant Permission…") { state.requestPermission() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Open the panel") {
                Toggle("Open with a key gesture", isOn: $state.enabled)
                Picker("Gesture", selection: $state.triggerKey) {
                    ForEach(TriggerKey.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!state.enabled)
                Text("Press \(state.triggerKey.short), on its own. Any other key, click or scroll in between cancels it, and it never fires while you drag. Press it again, press Esc or click elsewhere to close.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Clipboard history") {
                Picker("Keep items for", selection: $state.historyLength) {
                    ForEach(HistoryLength.allCases) { Text($0.title).tag($0) }
                }
                SavedCount(store: state.clipboard)
                HStack {
                    Text("Pinned items are never removed. Screenshots are read from your screenshot folder and never moved or deleted unless you press ⌘⌫.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History…") { confirmClear = true }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }))
                if let error = state.launchAtLoginError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                Text("Free and open source under the MIT license.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { state.clearHistory() }
        } message: {
            Text("Every item except pinned ones is removed. Screenshot files are not touched.")
        }
    }
}

/// Observes the store directly: it's an ObservableObject, not part of AppState's observation.
private struct SavedCount: View {
    @ObservedObject var store: ClipboardStore
    var body: some View {
        LabeledContent("Saved items") {
            Text("\(store.entries.count)").monospacedDigit()
        }
    }
}
