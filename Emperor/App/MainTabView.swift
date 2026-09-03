import SwiftUI

/// The signed-in app.
///
/// Ordered by what an advocate opens the phone to find out, most urgent first: what is listed
/// today, what is happening on my matters, and only then the assistant. Chat is the deepest
/// feature but rarely the reason the app is opened between hearings.
///
/// Five entries, because a sixth makes iOS collapse the bar into a "More" list. Notifications
/// are the one that moved: the platform's own dashboard puts them in the topbar as a bell with
/// a count (`src/shell/NotificationBell.jsx`) rather than in the nav, so the Today screen
/// carries them the same way.
struct MainTabView: View {
    var body: some View {
        TabView {
            CauseListView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }

            CaseListView()
                .tabItem {
                    Label("Matters", systemImage: "folder")
                }

            CalendarView()
                .tabItem {
                    Label("Diary", systemImage: "calendar.badge.clock")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            ChatListView()
                .tabItem {
                    Label("Ask", systemImage: "bubble.left.and.text.bubble.right")
                }
        }
    }
}
