import SwiftUI

struct ContentView: View {
    // Hardcoded for now — replace with real Google Sign-In later
    let googleId = "dev-user-001"

    var body: some View {
        TabView {
            HomeView(googleId: googleId)
                .tabItem {
                    Label("Today", systemImage: "camera.fill")
                }

            CombosView(googleId: googleId)
                .tabItem {
                    Label("Saved", systemImage: "heart.fill")
                }

            LogView(googleId: googleId)
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }

            ClosetView(googleId: googleId)
                .tabItem {
                    Label("Closet", systemImage: "tshirt.fill")
                }
        }
        .tint(.primary)
    }
}
