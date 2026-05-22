import SwiftUI

@main
struct TranscriberApp: App {
    @State private var model = TranscriberModel()
    
    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(model)
        } label: {
            if let resizedIcon = getResizedMenuIcon() {
                Image(nsImage: resizedIcon)
            } else {
                Text("Icon Error")
            }
        }
        .menuBarExtraStyle(.menu)
    }
    
    private func getResizedMenuIcon() -> NSImage? {
        guard let image = NSImage(named: "Icon") else { return nil }
        image.size = NSSize(width: 17, height: 17)
        return image
    }
}
