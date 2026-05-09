import SwiftUI
import UIKit

extension View {
    func dismissKeyboardOnBackgroundTap() -> some View {
        modifier(KeyboardDismissOnTapModifier())
    }
}

private struct KeyboardDismissOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KeyboardDismissGestureInstaller())
    }
}

private struct KeyboardDismissGestureInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        // 只借这个 UIView 找到 window，不参与 SwiftUI 的点击命中。
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private weak var recognizer: UITapGestureRecognizer?

        deinit {
            if let recognizer {
                installedWindow?.removeGestureRecognizer(recognizer)
            }
        }

        func installIfNeeded(from view: UIView) {
            guard let window = view.window, installedWindow !== window else {
                return
            }

            if let recognizer {
                installedWindow?.removeGestureRecognizer(recognizer)
            }

            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tapRecognizer.cancelsTouchesInView = false
            tapRecognizer.delegate = self
            window.addGestureRecognizer(tapRecognizer)
            installedWindow = window
            recognizer = tapRecognizer
        }

        @objc private func handleTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else {
                return true
            }

            // 点输入框和按钮时保留原交互，只在普通空白/文本区域收起键盘。
            return !touchedView.isKeyboardDismissExcluded
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private extension UIView {
    var isKeyboardDismissExcluded: Bool {
        var currentView: UIView? = self
        while let view = currentView {
            if view is UITextField || view is UITextView || view is UIControl {
                return true
            }
            currentView = view.superview
        }
        return false
    }
}
