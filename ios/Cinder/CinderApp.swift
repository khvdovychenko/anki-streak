import SwiftUI

@main
struct CinderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // Tapping the widget or Live Activity sends cinder://open-anki
                    if url.host == "open-anki" { UIApplication.shared.open(Config.ankiURL) }
                }
        }
    }
}
