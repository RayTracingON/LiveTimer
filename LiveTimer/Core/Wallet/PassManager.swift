import Foundation
import Observation
import PassKit
import SwiftData

/// Wallet 卡片的取用与状态。
///
/// PKPassLibrary 明确写了「不支持并发使用」，所以整个类锁在 MainActor 上，
/// 并且持有一个实例——PKPassLibraryDidChange 通知只由已实例化的对象发出，用完即弃的临时实例收不到变化。
@MainActor
@Observable
final class PassManager {

    enum State: Equatable {
        case idle
        case loading
        case ready(PKPass)
        case failed(String)

        static func == (l: State, r: State) -> Bool {
            switch (l, r) {
            case (.idle, .idle), (.loading, .loading): return true
            case let (.ready(a), .ready(b)): return a.serialNumber == b.serialNumber
            case let (.failed(a), .failed(b)): return a == b
            default: return false
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var isInWallet = false

    private let api: LiveTimerAPI
    private let library = PKPassLibrary()

    init(api: LiveTimerAPI = .production) {
        self.api = api
    }

    /// 设备是否支持添加卡片。模拟器和部分地区的设备不支持，这时整个入口都不该出现。
    static var canAddPasses: Bool { PKAddPassesViewController.canAddPasses() }

    /// 向后端要一张卡。失败不抛给调用方，转成可展示的状态。
    func load(liveId: String) async {
        guard Self.canAddPasses else { return }
        if case .ready = state { return }
        state = .loading
        do {
            let data = try await api.passData(liveId: liveId)
            let pass = try PKPass(data: data)
            isInWallet = library.containsPass(pass)   // containsPass 不需要 entitlement
            state = .ready(pass)
        } catch let error as APIError {
            state = .failed(error.localizedDescription)
        } catch {
            // PKPass(data:) 对未签名或损坏的包会抛错
            state = .failed("卡片数据无效")
        }
    }

    /// AddPassToWalletButton 的回调只告诉「有没有加成功」，加成功后记一笔本地记录。
    func didFinishAdding(added: Bool, liveId: String, context: ModelContext) {
        guard case .ready(let pass) = state else { return }
        isInWallet = library.containsPass(pass)
        guard added, isInWallet else { return }
        let serial = pass.serialNumber
        let existing = try? context.fetch(
            FetchDescriptor<WalletPassRecord>(predicate: #Predicate { $0.serialNumber == serial })).first
        if existing == nil {
            context.insert(WalletPassRecord(serialNumber: serial, liveId: liveId))
            try? context.save()
        }
    }

    /// 已在钱包里时，用 passURL 直接跳过去，而不是把按钮置灰——Apple 明确禁止显示变暗的按钮。
    var walletURL: URL? {
        guard case .ready(let pass) = state else { return nil }
        return pass.passURL
    }

    func reset() {
        state = .idle
        isInWallet = false
    }
}
