import SwiftUI

struct PublishedPortLinks: View {
    let portDescription: String

    private var ports: [Int] {
        var seen = Set<Int>()
        return portDescription
            .split(separator: ",")
            .compactMap { entry in
                guard let mapping = entry.split(separator: "->", maxSplits: 1).first else { return nil }
                let hostPortText = mapping.split(separator: ":", omittingEmptySubsequences: false).last
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let hostPortText,
                      let port = Int(hostPortText),
                      (1...65_535).contains(port),
                      seen.insert(port).inserted else { return nil }
                return port
            }
    }

    var body: some View {
        if ports.isEmpty {
            Text("—")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 7) {
                ForEach(ports, id: \.self) { port in
                    Link(destination: URL(string: "http://localhost:\(port)")!) {
                        Text(verbatim: ":\(port)")
                    }
                    .help(Text(verbatim: "Open localhost:\(port) in your browser"))
                    .pointingHandCursor()
                }
            }
            .font(.caption.monospaced())
            .lineLimit(1)
        }
    }
}
