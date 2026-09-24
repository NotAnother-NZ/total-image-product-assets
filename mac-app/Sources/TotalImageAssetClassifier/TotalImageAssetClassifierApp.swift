import SwiftUI

@main
struct TotalImageAssetClassifierApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Total Image Asset Classifier") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentMinSize)
    }
}
