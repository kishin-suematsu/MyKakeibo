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
                                Text(item.amount, format: .currency(code: "JPY"))
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
                    Text(totalAmount, format: .currency(code: "JPY"))
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
    @State private var selectedDate: Date? = nil
    @State private var showDatePicker = false
    @State private var showAddSheet = false
    
    // ★変更1: 予算変数を @State に変更 (月ごとに読み込むため)
    @State private var monthlyBudget: Double = 1000.0
    @State private var showBudgetEdit = false

    let daysOfWeek = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        NavigationStack {
            VStack {
                // --- 月の切り替えエリア ---
                HStack {
                    Button(action: { changeMonth(by: -1) }) {
                        Image(systemName: "chevron.left").padding()
                    }
                    Spacer()
                    Button(action: { showDatePicker = true }) {
                        HStack {
                            Text(currentMonth, format: .dateTime.year().month())
                                .font(.title2.bold()).foregroundColor(.primary)
                            Image(systemName: "chevron.down").font(.caption).foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    Button(action: { changeMonth(by: 1) }) {
                        Image(systemName: "chevron.right").padding()
                    }
                }
                .padding(.horizontal).padding(.top, 10)
                
                // --- 予算と残高の表示エリア (デザインはそのまま) ---
                VStack(spacing: 8) {
                    let total = totalForMonth()
                    let remaining = monthlyBudget - total
                    let progress = min(total / monthlyBudget, 1.0)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("今月の予算: \(monthlyBudget, format: .currency(code: "JPY"))")
                                .font(.caption).foregroundStyle(.gray)
                            
                            if remaining >= 0 {
                                Text("残り: \(remaining, format: .currency(code: "JPY"))")
                                    .font(.headline).bold().foregroundStyle(.blue)
                            } else {
                                Text("超過: \(abs(remaining), format: .currency(code: "JPY"))")
                                    .font(.headline).bold().foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        Button("予算設定") { showBudgetEdit = true }
                            .font(.caption).buttonStyle(.bordered)
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5)
                                .frame(height: 10).foregroundStyle(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 5)
                                .frame(width: geometry.size.width * progress, height: 10)
                                .foregroundStyle(remaining >= 0 ? Color.blue : Color.red)
                        }
                    }
                    .frame(height: 10)
                }
                .padding(.horizontal).padding(.bottom, 10)

                // --- 曜日のヘッダー ---
                HStack {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Text(day).font(.caption).fontWeight(.bold).frame(maxWidth: .infinity)
                            .foregroundColor(day == "日" ? .red : (day == "土" ? .blue : .primary))
                    }
                }

                // --- カレンダーのマス目 ---
                let days = daysInMonth()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                    ForEach(days, id: \.self) { date in
                        if let date = date {
                            VStack(spacing: 4) {
                                Text(date, format: .dateTime.day())
                                    .font(.caption).foregroundColor(textColor(for: date))
                                let total = totalFor(date)
                                if total > 0 {
                                    Text("\(Int(total))").font(.caption2).foregroundColor(textColor(for: date))
                                        .lineLimit(1).minimumScaleFactor(0.5)
                                } else {
                                    Text("-").font(.caption2).foregroundColor(.clear)
                                }
                            }
                            .frame(height: 50).frame(maxWidth: .infinity)
                            .background(backgroundColor(for: date)).cornerRadius(8)
                            .onTapGesture { selectedDate = date }
                        } else {
                            Color.clear.frame(height: 50)
                        }
                    }
                }
                .padding(.horizontal)
              
                // --- 下部のリスト表示 ---
                List {
                    if let selected = selectedDate {
                        Section(header: HStack {
                            Text(selected, format: .dateTime.month().day().weekday())
                            Spacer()
                            Button { showAddSheet = true } label: {
                                Label("追加", systemImage: "plus.circle.fill").font(.body)
                            }.padding(.trailing, 10)
                            Button { selectedDate = nil } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
                            }
                        }) {
                            let itemsForDay = items.filter { Calendar.current.isDate($0.date, inSameDayAs: selected) }
                            if itemsForDay.isEmpty {
                                Text("履歴はありません")
                            } else {
                                ForEach(itemsForDay) { item in
                                    NavigationLink(destination: EditExpenseView(item: item)) {
                                        HStack {
                                            Text(item.name.isEmpty ? "No Name" : item.name)
                                            Spacer()
                                            Text(item.amount, format: .currency(code: "JPY"))
                                        }
                                    }
                                }
                                .onDelete { indexSet in
                                    for index in indexSet { modelContext.delete(itemsForDay[index]) }
                                }
                            }
                        }
                    } else {
                        Section {
                            HStack {
                                Text("今月の出費合計")
                                Spacer()
                                Text(totalForMonth(), format: .currency(code: "JPY")).bold()
                            }
                        }
                    }
                }
            }
            .navigationTitle("月間レポート")
            .navigationBarTitleDisplayMode(.inline)
            
            // --- シートとアラート ---
            .sheet(isPresented: $showDatePicker) {
                VStack {
                    Text("年月を選択").font(.headline).padding(.top)
                    DatePicker("", selection: $currentMonth, displayedComponents: [.date])
                        .datePickerStyle(.wheel).labelsHidden()
                    Button("完了") { selectedDate = nil; showDatePicker = false }
                        .buttonStyle(.borderedProminent).padding()
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showAddSheet) {
                if let selected = selectedDate {
                    SimpleInputView(date: selected).presentationDetents([.medium])
                }
            }
            // ★変更2: 予算保存処理
            .alert("予算を設定", isPresented: $showBudgetEdit) {
                TextField("金額", value: $monthlyBudget, format: .number)
                    .keyboardType(.decimalPad)
                Button("OK") {
                    saveBudgetForCurrentMonth() // 保存を実行
                }
                Button("キャンセル", role: .cancel) {
                    loadBudgetForCurrentMonth() // キャンセルしたら元の値に戻す
                }
            } message: {
                Text("\(currentMonth, format: .dateTime.month())月の目標金額を入力してください")
            }
        }
        // ★変更3: 画面が表示されたり、月が変わったりした時に予算を読み込む
        .onAppear {
            loadBudgetForCurrentMonth()
        }
        .onChange(of: currentMonth) {
            loadBudgetForCurrentMonth()
        }
    }
    
    // --- ★追加: 月ごとの予算管理ロジック ---
    
    // その月の「保存用キー」を作る関数 (例: "budget_2026_02")
    private func budgetKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return "budget_\(components.year!)_\(components.month!)"
    }
    
    // 予算を保存する
    private func saveBudgetForCurrentMonth() {
        let key = budgetKey(for: currentMonth)
        UserDefaults.standard.set(monthlyBudget, forKey: key)
    }
    
    // 予算を読み込む (データがなければデフォルト1000)
    private func loadBudgetForCurrentMonth() {
        let key = budgetKey(for: currentMonth)
        let savedValue = UserDefaults.standard.double(forKey: key)
        if savedValue > 0 {
            monthlyBudget = savedValue
        } else {
            monthlyBudget = 1000.0 // デフォルト値
        }
    }

    // --- 以下、既存のロジック (変更なし) ---
    private func backgroundColor(for date: Date) -> Color {
        if let selected = selectedDate, Calendar.current.isDate(date, inSameDayAs: selected) { return Color.orange }
        if Calendar.current.isDateInToday(date) { return Color.blue.opacity(0.3) }
        return Color(uiColor: .secondarySystemBackground).opacity(0.5)
    }
    private func textColor(for date: Date) -> Color {
        if let selected = selectedDate, Calendar.current.isDate(date, inSameDayAs: selected) { return .white }
        return .primary
    }
    private func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newDate; selectedDate = nil
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
            if let date = Calendar.current.date(byAdding: .day, value: day - 1, to: monthStart) { days.append(date) }
        }
        return days
    }
    private func totalFor(_ date: Date) -> Double {
        items.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.amount }
    }
    private func totalForMonth() -> Double {
        items.filter { Calendar.current.isDate($0.date, equalTo: currentMonth, toGranularity: .month) }.reduce(0) { $0 + $1.amount }
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

// 日付を指定してサッと入力するための簡易画面
struct SimpleInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var date: Date // カレンダーから受け取った日付
    
    @State private var name = ""
    @State private var amount = ""
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("使ったもの", text: $name)
                TextField("金額", text: $amount)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("追加: \(date, format: .dateTime.month().day())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let amountVal = Double(amount) {
                            let newItem = ExpenseItem(name: name, amount: amountVal, date: date)
                            modelContext.insert(newItem)
                            dismiss()
                        }
                    }
                    .disabled(amount.isEmpty)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
