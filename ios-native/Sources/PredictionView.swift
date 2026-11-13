import SwiftUI
import JavaScriptCore

private struct Triple: Identifiable {
    var id: String { key }
    let key: String
    let probability: Double
}
private let adjustments: [(String, String)] = [
    ("grade","等級"), ("racer","選手の全国・当地成績"),
    ("motor","モーター・ボート"), ("start","平均ST・展示ST・F/L"),
    ("exhibition","展示タイム・体重・チルト"), ("venue","会場傾向")
]
private func number(_ value: Any?) -> Double? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
}

struct PredictionView: View {
    let race: Race
    let venue: String
    let venueID: String
    @State private var weights: [String: Double] = Dictionary(uniqueKeysWithValues: adjustments.map { ($0.0, 0) })
    @State private var triples: [Triple] = []
    @State private var marginal: [[Double]] = []
    @State private var selectedAxis = 0
    @State private var issue: String?
    @State private var liveRace: [String: Any] = [:]
    @State private var odds: [String: Double] = [:]
    private var axes: [String] { ["全艇","1号艇","2号艇","3号艇","4号艇","5号艇","6号艇"] }
    private var filtered: [Triple] { selectedAxis == 0 ? triples : triples.filter { $0.key.hasPrefix("\(selectedAxis)-") } }

    var body: some View {
        List {
            if let issue { Text(issue).foregroundStyle(.red) }
            Section("1〜3着の艇ごとの予測確率") {
                if marginal.count == 6 {
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading) {
                            HStack { Text("着順").frame(width: 48); ForEach(0..<6, id: \.self) { Text("\($0+1)号艇").frame(width: 62) } }
                            ForEach(0..<3, id: \.self) { place in
                                HStack { Text("\(place+1)着").frame(width: 48); ForEach(0..<6, id: \.self) { i in Text(String(format: "%.1f%%", marginal[i][place]*100)).frame(width: 62) } }
                            }
                        }.font(.caption)
                    }
                }
            }
            Section("予測に使う指標の調整") {
                ForEach(adjustments, id: \.0) { item in
                    VStack(alignment: .leading) {
                        HStack { Text(item.1); Spacer(); Text(String(format: "%+.0f", weights[item.0] ?? 0)) }
                        Slider(value: Binding(get: { weights[item.0] ?? 0 }, set: { weights[item.0] = $0; UserDefaults.standard.set(weights, forKey: "native.weights.active"); calculate() }), in: -10...10, step: 1)
                    }
                }
                HStack {
                    Button("保存") { UserDefaults.standard.set(weights, forKey: "native.weights.preset") }
                    Button("読込") {
                        if let stored = UserDefaults.standard.dictionary(forKey: "native.weights.preset") as? [String: Double] {
                            weights = stored; UserDefaults.standard.set(stored, forKey: "native.weights.active"); calculate()
                        }
                    }
                    Button("初期値に戻す") {
                        for item in adjustments { weights[item.0] = 0 }
                        UserDefaults.standard.set(weights, forKey: "native.weights.active"); calculate()
                    }
                }
            }
            Section("3連単の予測確率") {
                ScrollView(.horizontal) {
                    HStack { ForEach(0..<7, id: \.self) { axis in Button(axes[axis]) { selectedAxis = axis }.buttonStyle(.bordered).tint(selectedAxis == axis ? .blue : .gray) } }
                }
                ForEach(Array(filtered.prefix(10))) { item in tripleRow(item) }
                if filtered.count > 10 {
                    DisclosureGroup("詳細（残り\(filtered.count - 10)通り）") {
                        ForEach(Array(filtered.dropFirst(10))) { item in tripleRow(item) }
                    }
                }
            }
        }
        .navigationTitle("\(venue) \(race.number)R")
        .navigationBarTitleDisplayMode(.inline)
        .task { if let saved = UserDefaults.standard.dictionary(forKey: "native.weights.active") as? [String: Double] { weights = saved }; liveRace = race.raw; calculate(); while !Task.isCancelled { await refreshData(); try? await Task.sleep(nanoseconds: 30_000_000_000) } }
    }
    private func tripleRow(_ item: Triple) -> some View {
        HStack { Text(item.key); Spacer(); Text(odds[item.key].map { String(format: "%.1f倍", $0) } ?? "―"); Spacer(); Text(String(format:"%.3f%%",item.probability*100)).monospacedDigit() }
    }
    private func calculate() {
        let raw = liveRace.isEmpty ? race.raw : liveRace
        guard let racers = raw["racers"] as? [String: [String: Any]],
              let path = Bundle.main.path(forResource: "PredictionEngine", ofType: "js"),
              let script = try? String(contentsOfFile: path, encoding: .utf8),
              let context = JSContext() else { issue = "予測データを読み込めません"; return }
        let preview = raw["preview"] as? [String: Any] ?? [:]
        let previews = preview["racers"] as? [String: [String: Any]] ?? [:]
        let course = [55.0,13.5,12.8,10.6,6.1,1.9]
        let gradeMap = [1:"A1",2:"A2",3:"B1",4:"B2"]
        var values: [[String: Any]] = []
        let extra = ["localwin":"local_win_rate","local2":"local_top_2_percent","local3":"local_top_3_percent","natwin":"national_win_rate","nat3":"national_top_3_percent","motor3":"motor_top_3_percent","boat2":"boat_top_2_percent","boat3":"boat_top_3_percent","flying":"flying_count","late":"late_count","age":"age","weight":"weight"]
        for i in 0..<6 {
            guard let r = racers[String(i+1)] else { issue = "６艇の情報がありません"; return }
            let p = previews[String(i+1)] ?? [:]
            let grade = gradeMap[Int(number(r["rank_number"]) ?? 0)] ?? ""
            var v: [String: Any] = ["course":course[i],"racer":number(r["national_top_2_percent"]) ?? 30,"motor":number(r["motor_top_2_percent"]) ?? 35,"st":number(r["average_start_timing"]) ?? 0.15,"ex":number(p["exhibition_time"]) ?? 0,"grade":grade,"c1":"","c2":"","c3":""]
            if number(p["exhibition_time"]) == nil { v["ex"] = "" }
            for (key, source) in extra { if let n = number(r[source]) { v[key] = n } }
            for (key,source) in ["exst":"start_timing","tilt":"tilt_adjustment","adjust":"weight_adjustment"] { if let n = number(p[source]) { v[key] = n } }
            values.append(v)
        }
        let day = raw["date"] as? String ?? ""
        var factors = Dictionary(uniqueKeysWithValues: adjustments.map { ($0.0, 100 + (weights[$0.0] ?? 0) * 10) })
        factors["wind"] = 100; factors["wave"] = 100
        let payload: [String: Any] = ["values": values, "weather": ["wind":number(preview["wind_speed"]) as Any? ?? NSNull(), "wave":number(preview["wave_height"]) as Any? ?? NSNull()], "date":day, "venue":Int(venueID) ?? 0, "weights":factors]
        context.exceptionHandler = { _, exception in print("Prediction error: \(String(describing: exception))") }
        context.evaluateScript(script)
        guard let result = context.objectForKeyedSubscript("predict").call(withArguments: [payload])?.toString(),
              let data = result.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rows = json["triples"] as? [[String: Any]],
              let margins = json["marginals"] as? [[Double]] else { issue = "予測計算に失敗しました"; return }
        triples = rows.compactMap { row in guard let k = row["key"] as? String, let p = row["p"] as? Double else { return nil }; return Triple(key:k, probability:p) }
        marginal = margins; issue = nil
        savePrediction(raw: raw, date: day)
    }
    @MainActor
    private func refreshData() async {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: "Asia/Tokyo"); formatter.dateFormat = "yyyyMMdd"
        let date = formatter.string(from: Date())
        guard let url = URL(string:"https://boatraceopenapi.github.io/api/v1/\(date.prefix(4))/\(date).json") else { return }
        do {
            var request = URLRequest(url:url); request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let programs = root["programs"] as? [String:Any],
                  let stadiums = programs["stadiums"] as? [String:Any],
                  let stadium = stadiums[String(Int(venueID) ?? 0)] as? [String:Any],
                  let races = stadium["races"] as? [String:Any],
                  let current = races[String(Int(race.number) ?? 0)] as? [String:Any] else { return }
            liveRace=current; calculate()
            await refreshOdds(date:date)
        } catch { issue = "更新できませんでした。前回のデータを表示しています。" }
    }
    @MainActor
    private func refreshOdds(date: String) async {
        let month = String(date.dropFirst(4).prefix(2)), day = String(date.suffix(2))
        guard let url = URL(string:"https://boatracecsv.github.io/data/previews/od3/\(date.prefix(4))/\(month)/\(day).csv") else { return }
        do {
            var req = URLRequest(url:url); req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for:req)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data:data, encoding:.utf8) else { return }
            let lines = text.components(separatedBy:.newlines)
            guard let first = lines.first else { return }
            let head = first.replacingOccurrences(of:"\u{FEFF}",with:"").components(separatedBy:",")
            let code = date + String(format:"%02d", Int(venueID) ?? 0) + String(format:"%02d", Int(race.number) ?? 0)
            guard let row = lines.dropFirst().map({ $0.components(separatedBy:",") }).first(where: { $0.first == code }),
                  let ti = head.firstIndex(of:"取得日時"), ti < row.count,
                  let captured = ISO8601DateFormatter().date(from:row[ti]),
                  let close = (liveRace["closed_at"] as? String).flatMap({ ISO8601DateFormatter().date(from:$0) }), captured < close else { return }
            var next: [String:Double] = [:]
            for (i,h) in head.enumerated() where h.hasPrefix("3連単_") && i < row.count {
                if let v = Double(row[i]), v > 0 { next[String(h.dropFirst(4))] = v }
            }
            if !next.isEmpty { odds=next }
        } catch { }
    }
    private func savePrediction(raw: [String:Any], date: String) {
        guard let close = raw["closed_at"] as? String,
              let deadline = ISO8601DateFormatter().date(from:close), Date() < deadline,
              let best = triples.first else { return }
        let record = PredictionRecord(id: date + "-" + venueID + "-" + race.number, date: date, venue: venue, race: race.number, prediction: best.key, actual: nil)
        HistoryStore.upsert(record)
    }

}
