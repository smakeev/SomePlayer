import SwiftUI

@main
struct SomePlayerSwiftUIiOSApp: App {
    @StateObject private var model = PlayerDemoViewModel(platform: .iOS)

    var body: some Scene {
        WindowGroup {
            PlayerDemoView(model: model)
        }
    }
}
