import SwiftUI

struct PredictionRecord: Codable, Identifiable {
    let id: String
    let date: String
    let venue: String
    let race: String
    var prediction: String
    var actual: String?
}

enum HistoryStore {
    private static let key = "native.predictions.v1"
    static func load() -> [PredictionRecord] {
        guard let data = UserDefaults.standard.data(forKey:key),
              let values = try? JSONDecoder().decode([PredictionRecord].self, from:data) else { return [] }
        return values
    }
    static func write(_ records: [PredictionRecord]) {
        if let data = try? JSONEncoder().encode(Array(records.suffix(500))) { UserDefaults.standard.set(data,forKey:key) }
    }
    static func upsert(_ record: PredictionRecord) {
        var items = load()
        if let i = items.firstIndex(where: { $0.id == record.id }) {
            if items[i].actual == nil { items[i] = record }
        } else { items.append(record) }
        write(items)
    }
    static func reconcile() async {
        var records = load()
        for day in Set(records.filter { $0.actual == nil }.map(\.date)).sorted().suffix(7) {
            let compact = day.replacingOccurrences(of:"-",with:"")
            guard compact.count == 8,
                  let url = URL(string:"https://boatraceopenapi.github.io/api/v1/\(compact.prefix(4))/\(compact).json"),
                  let (data, response) = try? await URLSession.shared.data(from:url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
                  let programs = root["programs"] as? [String:Any],
                  let stadiums = programs["stadiums"] as? [String:Any] else { continue }
            for i in records.indices where records[i].date == day && records[i].actual == nil {
                let parts=records[i].id.split(separator:"-")
                guard parts.count == 5,
                      let st = stadiums[String(Int(parts[3]) ?? 0)] as? [String:Any],
                      let races = st["races"] as? [String:Any],
                      let race = races[String(Int(parts[4]) ?? 0)] as? [String:Any],
                      let result = race["result"] as? [String:Any],
                      let racers = result["racers"] as? [String:[String:Any]] else { continue }
                let places = (1...3).map { position in racers.filter { ($0.value["place_number"] as? Int) == position }.map(\.key) }
                if places.allSatisfy({ $0.count == 1 }) && Set(places.flatMap { $0 }).count == 3 {
                    records[i].actual = places.map { $0[0] }.joined(separator:"-")
                }
            }
        }
        write(records)
    }
}

struct HistoryView: View {
    @State private var records: [PredictionRecord] = []
    @State private var selected = Date()
    @State private var displayedMonth = Date()
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier:"Asia/Tokyo")!; return c }
    private func key(_ date: Date) -> String { let f=DateFormatter(); f.calendar=calendar; f.timeZone=calendar.timeZone; f.dateFormat="yyyy-MM-dd"; return f.string(from:date) }
    private var monthTitle: String { let f=DateFormatter(); f.calendar=calendar; f.timeZone=calendar.timeZone; f.dateFormat="yyyy年M月"; return f.string(from:displayedMonth) }
    private var monthDays: [Date?] { guard let range=calendar.range(of:.day,in:.month,for:displayedMonth), let start=calendar.date(from:calendar.dateComponents([.year,.month],from:displayedMonth)) else { return [] }; let offset=calendar.component(.weekday,from:start)-1; return Array(repeating:nil,count:offset) + range.compactMap { calendar.date(byAdding:.day,value:$0-1,to:start) }.map { Optional($0) } }
    private let columns=Array(repeating:GridItem(.flexible(),spacing:2),count:7)
    private var day: String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier:"Asia/Tokyo"); f.dateFormat = "yyyy-MM-dd"; return f.string(from:selected)
    }
    private var checked: [PredictionRecord] { records.filter { $0.actual != nil } }
    var body: some View {
        List {
            Section("予測の振り返り") {
                if checked.isEmpty { Text("結果を照合できた予測はありません").foregroundStyle(.secondary) }
                else {
                    let hits = checked.filter { $0.prediction == $0.actual }.count
                    Text("予測精度 \(Double(hits) / Double(checked.count) * 100, specifier: "%.1f")%（\(hits)/\(checked.count)）")
                }
                HStack {
                    Button { if let d=calendar.date(byAdding:.month,value:-1,to:displayedMonth) { displayedMonth=d } } label: { Image(systemName:"chevron.left") }
                    Spacer(); Text(monthTitle).font(.headline); Spacer()
                    Button { if let d=calendar.date(byAdding:.month,value:1,to:displayedMonth) { displayedMonth=d } } label: { Image(systemName:"chevron.right") }
                }.buttonStyle(.plain)
                LazyVGrid(columns:columns,spacing:6) {
                    ForEach(["日","月","火","水","木","金","土"],id:\.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(monthDays.enumerated()),id:\.offset) { _, date in
                        if let date {
                            Button { selected=date } label: {
                                VStack(spacing:1) {
                                    Text("\(calendar.component(.day,from:date))")
                                    Text(records.contains { $0.date == key(date) } ? "🚤" : " ").font(.caption2)
                                }.frame(maxWidth:.infinity,minHeight:40)
                                    .background(calendar.isDate(date,inSameDayAs:selected) ? Color.blue.opacity(0.16) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius:8))
                            }.buttonStyle(.plain).accessibilityLabel("\(key(date))\(records.contains { $0.date == key(date) } ? " 予測あり" : "")")
                        } else { Color.clear.frame(height:40) }
                    }
                }
            }
            Section(day) {
                ForEach(records.filter { $0.date == day }) { item in
                    VStack(alignment:.leading) {
                        Text("\(item.venue) \(item.race)R").bold()
                        Text("予測 \(item.prediction)　結果 \(item.actual ?? "未確定")")
                    }
                }
            }
        }.navigationTitle("予測履歴")
        .task { await HistoryStore.reconcile(); records=HistoryStore.load() }
    }
}
