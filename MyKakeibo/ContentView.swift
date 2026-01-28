import SwiftUI
import SwiftData

// --- アプリ全体の枠組み (タブで切り替え) ---
struct ContentView: View {
    var body: some View {
        TabView {
            // 1つ目の画面: 入力とリスト
            ExpenseInputListView()
                .tabItem {
                    Label("入力・履歴", systemImage: "list.bullet")
                }
            
            // 2つ目の画面: カレンダーレポート
            CalendarReportView()
                .tabItem {
                    Label("カレンダー", systemImage: "calendar")
                }
        }
    }
}

// ==========================================
//  1. 入力・履歴リスト画面 (変更なし)
// ==========================================
struct ExpenseInputListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseItem.date, order: .reverse) private var items: [ExpenseItem]

    @State private var name = ""
    @State private var amount = ""
    @State private var selectedMode = "日別"
    @FocusState private var isInputActive: Bool
    
    let modes = ["日別", "月別"]

    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    Section(header: Text("入力")) {
                        TextField("使ったもの (例: カフェ)", text: $name)
                            .focused($isInputActive)

                        TextField("金額", text: $amount)
                            .keyboardType(.decimalPad)
                            .focused($isInputActive)
                          
                        Button("保存") {
                            addItem()
                        }
                        .disabled(amount.isEmpty)
                    }
                    
                    Picker("表示モード", selection: $selectedMode) {
                        ForEach(modes, id: \.self) { mode in
                            Text(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                }
                .frame(height: 200)
                .scrollDisabled(true)

                if selectedMode == "日別" {
                    dailyListView
                } else {
                    monthlyListView
                }
            }
            .navigationTitle("家計簿")
            .toolbar {
                if isInputActive {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完了") { isInputActive = false }
                    }
                }
            }
        }
    }
    
    // --- リストの見た目パーツ ---
    private var dailyListView: some View {
        List {
            ForEach(dailyGroups, id: \.0) { (date, itemsInDay) in
                Section(header: Text(date, format: .dateTime.month().day().weekday())) {
                    ForEach(itemsInDay) { item in
                        NavigationLink(destination: EditExpenseView(item: item)) {
                            HStack {
                                Text(item.name.isEmpty ? "No Name" : item.name)
                                Spacer()
                                Text(item.amount, format: .currency(code: "USD"))
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            modelContext.delete(itemsInDay[index])
                        }
                    }
                }
            }
        }
    }

    private var monthlyListView: some View {
        List {
            ForEach(monthlyGroups, id: \.0) { (date, totalAmount) in
                HStack {
                    Text(date, format: .dateTime.year().month())
                        .font(.headline)
                    Spacer()
                    Text(totalAmount, format: .currency(code: "USD"))
                        .bold()
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    // --- データ処理ロジック ---
    private var dailyGroups: [(Date, [ExpenseItem])] {
        let grouped = Dictionary(grouping: items) { item in
            Calendar.current.startOfDay(for: item.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private var monthlyGroups: [(Date, Double)] {
        let grouped = Dictionary(grouping: items) { item in
            let components = Calendar.current.dateComponents([.year, .month], from: item.date)
            return Calendar.current.date(from: components) ?? Date()
        }
        let monthlyTotals = grouped.map { (date, items) in
            (date, items.reduce(0) { $0 + $1.amount })
        }
        return monthlyTotals.sorted { $0.0 > $1.0 }
    }

    private func addItem() {
        if let actualAmount = Double(amount) {
            let title = name.isEmpty ? "No Name" : name
            let newItem = ExpenseItem(name: title, amount: actualAmount)
            modelContext.insert(newItem)
            name = ""
            amount = ""
            isInputActive = false
        }
    }
}

// ==========================================
//  2. カレンダーレポート画面 (★ここを進化させました)
// ==========================================
struct CalendarReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [ExpenseItem]
    
    @State private var currentMonth = Date()
    @State private var selectedDate: Date? = nil // ★追加: 選んだ日付を保存する変数

    let daysOfWeek = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        NavigationStack {
            VStack {
                // --- 月の切り替えエリア ---
                HStack {
                    Button(action: { changeMonth(by: -1) }) {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(currentMonth, format: .dateTime.year().month())
                        .font(.title2.bold())
                    Spacer()
                    Button(action: { changeMonth(by: 1) }) {
                        Image(systemName: "chevron.right")
                    }
                }
                .padding()

                // --- 曜日のヘッダー ---
                HStack {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Text(day)
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(day == "日" ? .red : (day == "土" ? .blue : .primary))
                    }
                }

                // --- カレンダーのマス目 ---
                let days = daysInMonth()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                    ForEach(days, id: \.self) { date in
                        if let date = date {
                            // --- 日付マスのデザイン ---
                            VStack(spacing: 4) {
                                Text(date, format: .dateTime.day())
                                    .font(.caption)
                                    .foregroundColor(textColor(for: date))
                                
                                let total = totalFor(date)
                                if total > 0 {
                                    Text("\(Int(total))")
                                        .font(.caption2)
                                        .foregroundColor(textColor(for: date)) // 文字色も合わせる
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                } else {
                                    Text("-").font(.caption2).foregroundColor(.clear)
                                }
                            }
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(backgroundColor(for: date)) // ★背景色を変える
                            .cornerRadius(8)
                            .onTapGesture {
                                // ★タップしたらその日を選択
                                selectedDate = date
                            }
                        } else {
                            Color.clear.frame(height: 50)
                        }
                    }
                }
                .padding(.horizontal)
              
                // --- 下部のリスト表示 ---
                List {
                    // ★日付が選択されていたら、その日の詳細を表示
                    if let selected = selectedDate {
                        Section(header: HStack {
                            Text(selected, format: .dateTime.month().day().weekday())
                            Spacer()
                            // 選択解除ボタン (×)
                            Button {
                                selectedDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.gray)
                            }
                        }) {
                            // その日のデータだけを抽出
                            let itemsForDay = items.filter { Calendar.current.isDate($0.date, inSameDayAs: selected) }
                            
                            if itemsForDay.isEmpty {
                                Text("履歴はありません")
                            } else {
                                ForEach(itemsForDay) { item in
                                    // ★ここで編集画面へ移動
                                    NavigationLink(destination: EditExpenseView(item: item)) {
                                        HStack {
                                            Text(item.name.isEmpty ? "No Name" : item.name)
                                            Spacer()
                                            Text(item.amount, format: .currency(code: "USD"))
                                        }
                                    }
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        modelContext.delete(itemsForDay[index])
                                    }
                                }
                            }
                        }
                    } else {
                        // ★日付が選ばれていない時は、今月の合計を表示
                        Section {
                            HStack {
                                Text("今月の出費合計")
                                Spacer()
                                Text(totalForMonth(), format: .currency(code: "USD"))
                                    .bold()
                            }
                        }
                    }
                }
            }
            .navigationTitle("月間レポート")
        }
    }

    // --- 色とデザインのロジック ---
    private func backgroundColor(for date: Date) -> Color {
        // 選択中の日付ならオレンジ
        if let selected = selectedDate, Calendar.current.isDate(date, inSameDayAs: selected) {
            return Color.orange
        }
        // 今日なら青
        if Calendar.current.isDateInToday(date) {
            return Color.blue.opacity(0.3)
        }
        // それ以外は薄いグレー
        return Color(uiColor: .secondarySystemBackground).opacity(0.5)
    }
    
    private func textColor(for date: Date) -> Color {
        // 選択中の日付なら白文字が見やすい
        if let selected = selectedDate, Calendar.current.isDate(date, inSameDayAs: selected) {
            return .white
        }
        return .primary
    }

    // --- カレンダー計算ロジック ---
    private func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newDate
            selectedDate = nil // 月を変えたら選択解除
        }
    }

    private func daysInMonth() -> [Date?] {
        guard let monthInterval = Calendar.current.dateInterval(of: .month, for: currentMonth) else { return [] }
        let monthStart = monthInterval.start
        let startWeekday = Calendar.current.component(.weekday, from: monthStart)
        guard let range = Calendar.current.range(of: .day, in: .month, for: currentMonth) else { return [] }
        var days: [Date?] = []
        for _ in 1..<startWeekday { days.append(nil) }
        for day in range {
            if let date = Calendar.current.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(date)
            }
        }
        return days
    }

    private func totalFor(_ date: Date) -> Double {
        items.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.amount }
    }
    
    private func totalForMonth() -> Double {
        items.filter {
            Calendar.current.isDate($0.date, equalTo: currentMonth, toGranularity: .month)
        }
        .reduce(0) { $0 + $1.amount }
    }
}

// ==========================================
//  3. 編集画面 (変更なし)
// ==========================================
struct EditExpenseView: View {
    @Bindable var item: ExpenseItem
    
    var body: some View {
        Form {
            Section(header: Text("編集")) {
                TextField("項目名", text: $item.name)
                TextField("金額", value: $item.amount, format: .number)
                    .keyboardType(.decimalPad)
                DatePicker("日付", selection: $item.date, displayedComponents: .date)
            }
        }
        .navigationTitle("詳細・編集")
        .navigationBarTitleDisplayMode(.inline)
    }
}
