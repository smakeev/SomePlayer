import SwiftUI

@main
struct SomePlayerSwiftUIMacApp: App {
    @StateObject private var model = PlayerDemoViewModel(platform: .macOS)

    var body: some Scene {
        WindowGroup {
            PlayerDemoView(model: model)
                .frame(minWidth: 860, minHeight: 620)
        }
    }
}
