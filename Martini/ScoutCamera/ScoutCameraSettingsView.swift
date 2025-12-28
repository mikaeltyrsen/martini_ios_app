import SwiftUI

struct ScoutCameraSettingsView: View {
    var body: some View {
        Form {
            ProjectKitSettingsView()
        }
        .navigationTitle("Scout Camera")
        .navigationBarTitleDisplayMode(.inline)
    }
}
