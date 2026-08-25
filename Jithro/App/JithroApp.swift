import SwiftUI

@main
struct JithroApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.restore() }
        }
    }
}

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView().controlSize(.large)
        case .signedOut:
            LoginView()
        case .signedIn:
            ChatListView()
        }
    }
}
