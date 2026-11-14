import SwiftUI

@main
struct BoatRaceApp: App {
    var body: some Scene {
        WindowGroup { AnalyzerAppRoot().onAppear { _ = SupportStore.shared } }
    }
}

func parseRaceDate(_ input: String) -> Date? {
    var value = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "T")
    if value.range(of: #"(?:Z|[+-]\d\d:\d\d)$"#, options: .regularExpression) == nil { value += "+09:00" }
    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: value) { return date }
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return iso.date(from: value)
}

struct Race: Identifiable {
    let id: String
    let number: String
    let closing: String
    let raw: [String: Any]
}
struct Venue: Identifiable {
    let id: String
    let name: String
    let races: [Race]
}

@MainActor
final class RaceStore: ObservableObject {
    @Published var venues: [Venue] = []
    @Published var status = "読み込み中"
    private let names = ["桐生","戸田","江戸川","平和島","多摩川","浜名湖","蒲郡","常滑","津","三国","びわこ","住之江","尼崎","鳴門","丸亀","児島","宮島","徳山","下関","若松","芦屋","福岡","唐津","大村"]

    func refresh() async {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyyMMdd"
        let day = formatter.string(from: Date())
        guard let url = URL(string: "https://boatraceopenapi.github.io/api/v1/\(day.prefix(4))/\(day).json") else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let programs = root["programs"] as? [String: Any],
                  let stadiums = programs["stadiums"] as? [String: Any] else {
                status = "レース情報を取得できませんでした"
                return
            }
            let readableDay = "\(day.prefix(4))-\(day.dropFirst(4).prefix(2))-\(day.suffix(2))"
            venues = stadiums.compactMap { key, value in
                guard let n = Int(key), (1...24).contains(n),
                      let stadium = value as? [String: Any],
                      let races = stadium["races"] as? [String: Any] else { return nil }
                let items: [Race] = races.compactMap { rk, rv in
                    guard let race = rv as? [String: Any],
                          let close = race["closed_at"] as? String,
                          let date = parseRaceDate(close), date > Date(),
                          let racers = race["racers"] as? [String: Any],
                          (1...6).allSatisfy({ (racers[String($0)] as? [String: Any])?["name"] as? String != nil }),
                          !["中止", "順延", "途中中止"].contains(where: { String(describing: race["day_number_source"] ?? "").contains($0) }),
                          !((race["result"] as? [String: Any])?["racers"] as? [String: [String: Any]] ?? [:]).values.contains(where: { (($0["place_number"] as? Int) ?? 0) > 0 }) else { return nil }
                    let clock = DateFormatter()
                    clock.timeZone = TimeZone(identifier: "Asia/Tokyo")
                    clock.dateFormat = "HH:mm"
                    var withDate = race; withDate["date"] = readableDay
                    return Race(id: "\(n)-\(rk)", number: rk, closing: clock.string(from: date), raw: withDate)
                }.sorted { (Int($0.number) ?? 0) < (Int($1.number) ?? 0) }
                return items.isEmpty ? nil : Venue(id: key, name: names[n-1], races: items)
            }.sorted { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
            status = venues.isEmpty ? "予測できるレースがありません" : ""
        } catch {
            status = "レース情報を取得できませんでした"
        }
    }
}

struct RaceListView: View {
    @StateObject private var store = RaceStore()
    private let aqua = Color(red: 0.09, green: 0.54, blue: 0.65)
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "sailboat.fill").font(.system(size: 28)).foregroundStyle(.white, .yellow)
                        Text("BOAT RACE\nANALYZER").font(.system(size: 19, weight: .black, design: .rounded)).lineLimit(2).minimumScaleFactor(0.65).fixedSize(horizontal: false, vertical: true).layoutPriority(1).foregroundStyle(.white)
                        Spacer()
                        NavigationLink { SettingsView() } label: {
                            Image(systemName: "gearshape.fill").font(.title3.bold()).padding(12).background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(aqua)
                        }.accessibilityLabel("設定")
                    }.padding(16).background(LinearGradient(colors: [.blue, aqua], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 14) {
                        Label("本日の予測可能レース一覧", systemImage: "circle.fill").font(.headline).foregroundStyle(aqua)
                        HStack { Button("一覧を更新") { Task { await store.refresh() } }.buttonStyle(.borderedProminent).tint(aqua); Spacer() }
                        if !store.status.isEmpty { Text(store.status).foregroundStyle(.secondary) }
                        ForEach(store.venues) { venue in
                            DisclosureGroup {
                                ForEach(venue.races) { race in
                                    NavigationLink { PredictionView(race: race, venue: venue.name, venueID: venue.id) } label: {
                                        HStack { Text("\(race.number)R").fontWeight(.bold); Spacer(); Text("締切 \(race.closing)").foregroundStyle(.secondary); Image(systemName: "chevron.right") }.padding(.vertical, 8)
                                    }.foregroundStyle(Color(red: 0.12, green: 0.29, blue: 0.39))
                                }
                            } label: {
                                HStack { Text(venue.name).fontWeight(.bold); Text("\(venue.races.count)レース"); Spacer(); Text(venue.races.first.map { "\($0.number)R \($0.closing)" } ?? "").font(.caption).foregroundStyle(.secondary) }
                            }.padding(15).background(Color(red: 0.91, green: 0.97, blue: 0.98), in: RoundedRectangle(cornerRadius: 17))
                        }
                    }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 22))
                }.padding(14)
            }
            .background(Color(red: 0.945, green: 0.976, blue: 0.988))
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refresh() }
            .task {
                while !Task.isCancelled {
                    await store.refresh()
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { break }
                }
            }
        }.preferredColorScheme(.light)
    }
}

struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink { HistoryView() } label: { Label("予測履歴・カレンダー", systemImage: "calendar") }
            Section("取扱説明書") {
                Text("レース一覧から会場を開き、レースを選ぶと予測を表示します。")
                Text("指標のスライダーを動かすと予測確率を再計算します。調整した設定は保存・読込ができます。")
                Text("表示した予測を締切前に保存し、確定結果と照合します。")
            }
        }.navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
    }
}
