#if os(macOS)
import SwiftUI
import AppKit

/// Bridges the underlying `NSWindow` lifecycle into SwiftUI so we can detect actual close events.
struct WindowObserver: NSViewRepresentable {
    let onWindowAttached: (NSWindow) -> Void
    let onWindowClosed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowAttached: onWindowAttached, onWindowClosed: onWindowClosed)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.attach(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                context.coordinator.attach(to: window)
            }
        }
    }

    final class Coordinator: NSObject {
        let onWindowAttached: (NSWindow) -> Void
        let onWindowClosed: () -> Void
        private weak var observedWindow: NSWindow?
        private var closeObserver: NSObjectProtocol?

        init(onWindowAttached: @escaping (NSWindow) -> Void, onWindowClosed: @escaping () -> Void) {
            self.onWindowAttached = onWindowAttached
            self.onWindowClosed = onWindowClosed
        }

        func attach(to window: NSWindow) {
            guard observedWindow !== window else { return }

            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
                self.closeObserver = nil
            }

            observedWindow = window
            onWindowAttached(window)

            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.onWindowClosed()
            }
        }

        deinit {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
        }
    }
}
#endif

