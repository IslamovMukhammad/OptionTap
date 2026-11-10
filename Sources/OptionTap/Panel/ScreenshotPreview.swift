import AppKit
import SwiftUI

@MainActor
final class PreviewState: ObservableObject {
    @Published var index = 0
    @Published var shown = false
}

/// Full-screen screenshot viewer over the panel: ← → to step, Space or Esc to close,
/// drag the image into any app.
@MainActor
final class ScreenshotPreviewController {
    private let store: ScreenshotStore
    private var panel: KeyPanel?
    private let state = PreviewState()
    private var closeWork: DispatchWorkItem?

    init(store: ScreenshotStore) { self.store = store }

    func open(_ item: ScreenshotItem) {
        closeWork?.cancel()
        state.index = store.items.firstIndex(of: item) ?? 0
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.ignoresMouseEvents = false
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.frame { panel.setFrame(frame, display: false) }
        panel.makeKeyAndOrderFront(nil)
        state.shown = true
    }

    /// A drag started: turn invisible and let clicks through (closed afterwards).
    func fadeForDrag() {
        guard state.shown else { return }
        state.shown = false
        panel?.ignoresMouseEvents = true
    }

    func close() {
        if !state.shown, panel?.isVisible == true {
            panel?.orderOut(nil)
            panel?.ignoresMouseEvents = false
            return
        }
        guard state.shown else { return }
        state.shown = false
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func step(_ delta: Int) {
        let count = store.items.count
        guard count > 0 else { return }
        state.index = min(max(0, state.index + delta), count - 1)
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        panel.level = .popUpMenu   // above the quick panel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.onKey = { [weak self] event in
            guard let self else { return false }
            switch event.keyCode {
            case 53, 49: self.close(); return true          // Esc, Space
            case 123: self.step(-1); return true            // ←
            case 124: self.step(1); return true             // →
            default: return false
            }
        }
        panel.contentView = NSHostingView(rootView: PreviewView(
            store: store, state: state,
            onClose: { [weak self] in self?.close() },
            onStep: { [weak self] in self?.step($0) }))
        return panel
    }
}

private struct PreviewView: View {
    @ObservedObject var store: ScreenshotStore
    @ObservedObject var state: PreviewState
    let onClose: () -> Void
    let onStep: (Int) -> Void
    @State private var image: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: ScreenshotItem? {
        store.items.indices.contains(state.index) ? store.items[state.index] : nil
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop; a click closes the preview.
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            if let item {
                VStack(spacing: 14) {
                    Group {
                        if let image {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05))
                                .aspectRatio(16 / 10, contentMode: .fit)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                    .onDrag {
                        DragOut.began()
                        return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
                    }

                    toolbar(item)
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
                .task(id: item.id) { image = await Thumbnail.load(item.url, maxPixel: 2600) }
            }
        }
        .environment(\.colorScheme, .dark)
        .opacity(state.shown ? 1 : 0)
        .scaleEffect(state.shown || reduceMotion ? 1 : 0.97)
        .animation(state.shown ? QP.easeOut : QP.exit, value: state.shown)
    }

    /// Bottom controls: ← n of N →, time, Move to Trash, close.
    private func toolbar(_ item: ScreenshotItem) -> some View {
        HStack(spacing: 14) {
            Button { onStep(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(state.index == 0)
            Text("\(state.index + 1) of \(store.items.count)")
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
            Button { onStep(1) } label: { Image(systemName: "chevron.right") }
                .disabled(state.index >= store.items.count - 1)

            Divider().frame(height: 16)

            Text(QP.time.string(from: item.createdAt))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))

            Divider().frame(height: 16)

            Button { store.trash(item); onStep(0) } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .foregroundStyle(QP.red)
            Button(action: onClose) { Image(systemName: "xmark") }
                .help("Close (Esc)")
        }
        .font(.system(size: 13, weight: .medium))
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 18)
        .frame(height: 40)
        .glassEffect(.regular, in: .capsule)
    }
}
