// Hold to move the cursor, as on the iPhone keyboard. A UIKit long press (UIKit's standard
// 0.5 s) on the whole window: on a field it puts the cursor under the finger and follows it;
// on the keypad (but ⌫, which keeps its own hold) it turns the keys into a trackpad. It runs
// alongside the key's or field's own gesture and cancels it when it begins, so nothing is typed.
// SwiftUI's long press followed by a drag did not do this on the phone.
import SwiftUI
import UIKit

enum HoldTarget: Equatable {
    case field(Field)
    case keypad
}

/// Frames of the fields and keys in window coordinates, by name, for `HoldToMoveCursor`.
struct TouchFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's frame in window coordinates under `name` ("row-inches",
    /// "text-inches", "keypad", "delete").
    func reportsTouchFrame(_ name: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: TouchFramesKey.self, value: [name: proxy.frame(in: .global)])
            }
        }
    }
}

struct HoldToMoveCursor: UIViewRepresentable {
    var frames: [String: CGRect]
    var isEnabled: Bool
    var onBegin: (HoldTarget, CGPoint) -> Void
    var onMove: (HoldTarget, CGPoint) -> Void
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WindowHookView {
        let view = WindowHookView()
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        view.onWindow = { window in coordinator.attach(to: window) }
        return view
    }

    func updateUIView(_ view: WindowHookView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.recognizer.isEnabled = isEnabled
    }

    static func dismantleUIView(_ view: WindowHookView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Tells when it is in a window, to put the long press on the window itself.
    final class WindowHookView: UIView {
        var onWindow: (@MainActor (UIWindow) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HoldToMoveCursor?
        let recognizer = UILongPressGestureRecognizer()
        private var target: HoldTarget?
        /// The app's own gestures on the same touch (a key's press), cancelled when the hold
        /// begins so that the key is not typed.
        private let rivals = NSHashTable<UIGestureRecognizer>.weakObjects()

        override init() {
            super.init()
            recognizer.addTarget(self, action: #selector(handle(_:)))
            recognizer.delegate = self
        }

        func attach(to window: UIWindow) {
            guard recognizer.view !== window else { return }
            recognizer.view?.removeGestureRecognizer(recognizer)
            window.addGestureRecognizer(recognizer)
        }

        func detach() {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }

        /// Only touches on a field or on the keypad (but ⌫); everything else is left alone.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            hitTarget(at: touch.location(in: nil)) != nil
        }

        /// A key's button starts tracking its touch as the finger lands. Were the two exclusive,
        /// the button would win and the hold would never begin (1.3.1: the keypad did not
        /// become a trackpad). So both run, and the hold cancels the button when it begins.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // The window's own (system) gestures are left alone.
            if let view = other.view, view !== recognizer.view { rivals.add(other) }
            return true
        }

        @objc private func handle(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: nil)
            switch recognizer.state {
            case .began:
                target = hitTarget(at: point)
                if let target {
                    cancelRivals()
                    parent?.onBegin(target, point)
                }
            case .changed:
                if let target { parent?.onMove(target, point) }
            default:
                if target != nil { parent?.onEnd() }
                target = nil
                rivals.removeAllObjects()
            }
        }

        /// Turning a gesture off and on again cancels it: the key under the finger lets go,
        /// unhighlighted, and types nothing.
        private func cancelRivals() {
            for other in rivals.allObjects where other !== recognizer && other.isEnabled {
                other.isEnabled = false
                other.isEnabled = true
            }
            rivals.removeAllObjects()
        }

        private func hitTarget(at point: CGPoint) -> HoldTarget? {
            guard let frames = parent?.frames else { return nil }
            for field in Field.allCases where frames["row-\(field.rawValue)"]?.contains(point) == true {
                return .field(field)
            }
            if frames["delete"]?.contains(point) == true { return nil }
            if frames["keypad"]?.contains(point) == true { return .keypad }
            return nil
        }
    }
}
