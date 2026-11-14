import SwiftUI
import StoreKit
import GoogleMobileAds
import UserMessagingPlatform

// Product IDs must also be created as consumables in App Store Connect.
@MainActor
final class SupportStore: ObservableObject {
    static let shared = SupportStore()
    private let ids = ["jp.boatraceanalyzer.support.small", "jp.boatraceanalyzer.support.medium", "jp.boatraceanalyzer.support.large", "jp.boatraceanalyzer.support.extra"]
    @Published var products: [Product] = []
    @Published var message = ""
    @Published var working = false
    private var updates: Task<Void, Never>?
    private init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result, self.ids.contains(transaction.productID) {
                    await transaction.finish()
                }
            }
        }
    }
    func load() async {
        do {
            products = try await Product.products(for: ids).sorted { $0.price < $1.price }
            if products.isEmpty { message = "現在、支援の購入を利用できません。時間をおいてお試しください。" }
        } catch { message = "購入情報を取得できませんでした。通信環境を確認してください。" }
    }
    func purchase(_ product: Product) async {
        working = true
        defer { working = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    message = "ご支援ありがとうございます。"
                case .unverified: message = "購入を確認できませんでした。"
                }
            case .pending: message = "購入の承認を待っています。"
            case .userCancelled: break
            @unknown default: message = "購入を完了できませんでした。"
            }
        } catch { message = "購入を完了できませんでした。時間をおいてお試しください。" }
    }
}

struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SupportStore.shared
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("開発者への任意の支援です。アプリの機能は支援の有無にかかわらず同じです。")
                    ForEach(store.products, id: \.id) { product in
                        Button { Task { await store.purchase(product) } } label: {
                            HStack { Text(product.displayName); Spacer(); Text(product.displayPrice) }
                        }.disabled(store.working)
                    }
                    if !store.message.isEmpty { Text(store.message).font(.footnote) }
                }
            }.navigationTitle("開発者を応援")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
                .task { await store.load() }
        }
    }
}

@MainActor
final class AdsConsent: ObservableObject {
    @Published var canShowAds = false
    @Published var requiresPrivacyOptions = false
    func gather() {
        ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { [weak self] _ in
            Task { @MainActor in
                do { try await ConsentForm.loadAndPresentIfRequired(from: nil) } catch { }
                self?.requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
                if ConsentInformation.shared.canRequestAds {
                    await MobileAds.shared.start()
                    self?.canShowAds = true
                }
            }
        }
    }
    func showPrivacyOptions() {
        Task { @MainActor in
            do { try await ConsentForm.presentPrivacyOptionsForm(from: nil) } catch { }
            requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            canShowAds = ConsentInformation.shared.canRequestAds
        }
    }
}

struct AdBannerContainer: View {
    @StateObject private var consent = AdsConsent()
    var body: some View {
        VStack(spacing: 0) {
            if consent.requiresPrivacyOptions {
                Button("広告のプライバシー設定") { consent.showPrivacyOptions() }.font(.caption)
            }
            if consent.canShowAds {
                AdBanner()
                    .frame(width: 320, height: 50)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }.onAppear { consent.gather() }
    }
}

// A neutral host keeps the ad's intrinsic size from stretching the SwiftUI layout.
private struct AdBanner: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        let banner = BannerView(adSize: AdSizeBanner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            banner.widthAnchor.constraint(equalToConstant: 320),
            banner.heightAnchor.constraint(equalToConstant: 50)
        ])
        banner.adUnitID = Bundle.main.object(forInfoDictionaryKey: "AdMobBannerID") as? String
        banner.load(Request())
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: 320, height: 50)
    }
}
