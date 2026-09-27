import SwiftUI

struct AppLifecycleModifier: ViewModifier {

    @ObservedObject var coordinator: AssistantCoordinator

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    coordinator.onBecameActive()
                case .inactive, .background:
                    coordinator.onResignActive()
                @unknown default:
                    break
                }
            }
    }
}

extension View {
    func withLifecycle(coordinator: AssistantCoordinator) -> some View {
        modifier(AppLifecycleModifier(coordinator: coordinator))
    }
}
