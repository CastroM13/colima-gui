import AppKit
import SwiftUI

struct ComposeFilePath: View {
    let path: String?

    private var normalizedPath: String? {
        guard let path, !path.isEmpty else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    var body: some View {
        if let normalizedPath {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: normalizedPath))
            } label: {
                Text(path ?? normalizedPath)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .underline()
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(normalizedPath)\nOpen compose file in the default editor")
            .accessibilityLabel("Open compose file in the default editor")
            .accessibilityValue(normalizedPath)
            .pointingHandCursor()
        } else {
            Text("Compose file unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
        }
    }
}
