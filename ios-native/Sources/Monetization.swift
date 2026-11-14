import SwiftUI
import StoreKit
import GoogleMobileAds
import UserMessagingPlatform

// Product IDs must also be created as consumables in App Store Connect.
@MainActor
final class SupportStore: ObservableObject {
    static let shared = SupportStore()
    private let ids = ["jp.boatraceanalyzer.support.small", "jp.boatraceanalyzer.support.medium", "jp.boatraceanalyzer.support.large"]
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
                    MobileAds.shared.start()
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
    @State private var bannerHeight: CGFloat = 50
    var body: some View {
        VStack(spacing: 0) {
            if consent.requiresPrivacyOptions {
                Button("広告のプライバシー設定") { consent.showPrivacyOptions() }.font(.caption)
            }
            if consent.canShowAds {
                GeometryReader { proxy in
                    let size = largeAnchoredAdaptiveBanner(width: proxy.size.width)
                    AdBanner(size: size).frame(width: size.size.width, height: size.size.height)
                        .onAppear { bannerHeight = size.size.height }
                        .onChange(of: proxy.size.width) { width in
                            bannerHeight = largeAnchoredAdaptiveBanner(width: width).size.height
                        }
                }.frame(height: bannerHeight)
            }
        }.onAppear { consent.gather() }
    }
}
private struct AdBanner: UIViewRepresentable {
    let size: AdSize
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: size)
        banner.adUnitID = Bundle.main.object(forInfoDictionaryKey: "AdMobBannerID") as? String
        banner.load(Request())
        return banner
    }
    func updateUIView(_ banner: BannerView, context: Context) {
        if banner.adSize.size.width != size.size.width {
            banner.adSize = size
            banner.load(Request())
        }
    }
}
