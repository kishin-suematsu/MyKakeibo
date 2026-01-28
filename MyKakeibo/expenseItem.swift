import Foundation
import SwiftData

// これが「家計簿データ」の設計図です
@Model
final class ExpenseItem {
    var name: String    // 項目名（ランチとか）
    var amount: Double  // 金額
    var date: Date      // 日付
    
    init(name: String, amount: Double, date: Date = Date()) {
        self.name = name
        self.amount = amount
        self.date = date
    }
}
