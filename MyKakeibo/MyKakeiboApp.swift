import SwiftUI
import SwiftData

@main
struct MyKakeiboApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // ↓ この1行を追加するだけで、データベースが準備されます
        .modelContainer(for: ExpenseItem.self)
    }
}
