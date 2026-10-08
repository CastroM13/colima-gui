import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Colima Manager")
                .font(.title2.weight(.semibold))
            Text("A lightweight control center for your local containers.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
