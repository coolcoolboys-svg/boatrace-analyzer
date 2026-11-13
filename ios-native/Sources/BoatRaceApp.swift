import SwiftUI

@main
struct BoatRaceApp: App {
    var body: some Scene {
        WindowGroup { RaceListView() }
    }
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
            let iso = ISO8601DateFormatter()
            venues = stadiums.compactMap { key, value in
                guard let n = Int(key), (1...24).contains(n),
                      let stadium = value as? [String: Any],
                      let races = stadium["races"] as? [String: Any] else { return nil }
                let items: [Race] = races.compactMap { rk, rv in
                    guard let race = rv as? [String: Any],
                          let close = race["closed_at"] as? String,
                          let date = iso.date(from: close), date > Date(),
                          let racers = race["racers"] as? [String: Any], racers.count == 6 else { return nil }
                    let clock = DateFormatter()
                    clock.timeZone = TimeZone(identifier: "Asia/Tokyo")
                    clock.dateFormat = "HH:mm"
                    return Race(id: "\(n)-\(rk)", number: rk, closing: clock.string(from: date), raw: race)
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
    var body: some View {
        NavigationStack {
            List {
                if !store.status.isEmpty { Text(store.status).foregroundStyle(.secondary) }
                ForEach(store.venues) { venue in
                    DisclosureGroup("\(venue.name)  \(venue.races.count)レース") {
                        ForEach(venue.races) { race in
                            NavigationLink { PredictionView(race: race, venue: venue.name, venueID: venue.id) } label: { HStack { Text("\(race.number)R"); Spacer(); Text("締切 \(race.closing)").foregroundStyle(.secondary) } }
                        }
                    }
                }
            }
            .navigationTitle("BOAT RACE")
            .toolbar { NavigationLink("履歴") { HistoryView() } }
            .refreshable { await store.refresh() }
            .task {
                while !Task.isCancelled {
                    await store.refresh()
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                }
            }
        }
    }
}
