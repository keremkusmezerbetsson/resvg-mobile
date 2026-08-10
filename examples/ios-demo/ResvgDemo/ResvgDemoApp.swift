import SwiftUI
import ResvgMobile
import ResvgMobileUI

@main
struct ResvgDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    private let svgData: Data = {
        guard let url = Bundle.main.url(forResource: "ico.football-wc26_v4", withExtension: "svg"),
              let data = try? Data(contentsOf: url) else {
            return Data()
        }
        return data
    }()

    var body: some View {
        ZStack {
            // Match Android demo: Color(0xFF0F172A)
            Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("WC26 football icon (resvg)")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("ico.football-wc26_v4.svg")
                    .font(.caption)
                    .foregroundStyle(Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255))
                    .padding(.bottom, 16)
                if svgData.isEmpty {
                    Text("Missing SVG resource")
                        .foregroundStyle(.red)
                } else {
                    ResvgImage(data: svgData)
                        .frame(width: 192, height: 192)
                        .padding(24)
                        // Match Android demo: Color(0xFF1E293B)
                        .background(Color(red: 30 / 255, green: 41 / 255, blue: 59 / 255))
                }
            }
            .padding(24)
        }
    }
}
