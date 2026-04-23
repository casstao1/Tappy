import SwiftUI

@main
struct TappyApp: App {
    @StateObject private var controller = KeyboardSoundController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Reveal Sounds Folder") {
                    controller.revealSoundsFolder()
                }

                Button("Reload Sounds") {
                    controller.reloadSounds()
                }
            }
        }
    }
}
