import AppKit
import SwiftUI

struct InteractiveCursorModifier: ViewModifier {
    let isEnabled: Bool

    @State private var pointerIsInside = false
    @State private var cursorIsPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isInside in
                pointerIsInside = isInside
                updateCursor()
            }
            .onChange(of: isEnabled) { _ in
                updateCursor()
            }
            .onDisappear {
                pointerIsInside = false
                popCursorIfNeeded()
            }
    }

    private func updateCursor() {
        let shouldUsePointingHand = isEnabled && pointerIsInside
        guard shouldUsePointingHand != cursorIsPushed else { return }

        if shouldUsePointingHand {
            NSCursor.pointingHand.push()
            cursorIsPushed = true
        } else {
            popCursorIfNeeded()
        }
    }

    private func popCursorIfNeeded() {
        guard cursorIsPushed else { return }
        NSCursor.pop()
        cursorIsPushed = false
    }
}

extension View {
    func pointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(InteractiveCursorModifier(isEnabled: isEnabled))
    }
}
