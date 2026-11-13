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
                DatePicker("日付",selection:$selected,displayedComponents:.date).datePickerStyle(.graphical)
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
