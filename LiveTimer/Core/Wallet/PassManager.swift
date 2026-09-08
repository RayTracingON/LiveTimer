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
    /// 改座位期间置位，用来把填写页的保存按钮转圈。
    private(set) var isUpdatingSeat = false

    private let api: LiveTimerAPI
    private let library = PKPassLibrary()

    init(api: LiveTimerAPI = .production) {
        self.api = api
    }

    /// 设备是否支持添加卡片。模拟器和部分地区的设备不支持，这时整个入口都不该出现。
    static var canAddPasses: Bool { PKAddPassesViewController.canAddPasses() }

    /// 取这场演出的卡。已经加进钱包的直接复用钱包里那张，没有才向后端要一张新的。
    ///
    /// 不能每次进详情页都签发：后端每次签发都是一张新序列号的卡，那样既会在库里堆废记录，
    /// 也会让已经加过卡的用户又看到「添加到钱包」，一路加出好几张重复的卡。
    func load(liveId: String, seat: PassSeatInput?, context: ModelContext) async {
        guard Self.canAddPasses else { return }
        if case .ready = state { return }
        state = .loading

        if let existing = existingPass(liveId: liveId, context: context) {
            isInWallet = true
            state = .ready(existing)
            return
        }
        await issue(liveId: liveId, seat: seat)
    }

    /// 用户改了座位。已经加进钱包的卡就地更新（后端会推送刷新），还没加的重新签发一张带座位的。
    func applySeat(_ seat: PassSeatInput?, liveId: String, context: ModelContext) async {
        guard Self.canAddPasses else { return }
        isUpdatingSeat = true
        defer { isUpdatingSeat = false }

        if isInWallet, case .ready(let pass) = state, let token = pass.authenticationToken {
            do {
                try await api.updatePassSeat(serialNumber: pass.serialNumber,
                                             authenticationToken: token, seat: seat)
            } catch let error as APIError {
                state = .failed(error.localizedDescription)
            } catch {
                state = .failed("座位更新失败")
            }
            return
        }
        await issue(liveId: liveId, seat: seat)
    }

    private func issue(liveId: String, seat: PassSeatInput?) async {
        state = .loading
        do {
            let data = try await api.passData(liveId: liveId, seat: seat?.isEmpty == true ? nil : seat)
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

    /// 本地记过序列号、且那张卡还在钱包里，就复用它。
    /// 按序列号在 passes() 里找，而不是 pass(withPassTypeIdentifier:serialNumber:)——
    /// 后者要把 Pass Type ID 再写一遍，和 entitlement 里的值对不上时会静默返回 nil。
    private func existingPass(liveId: String, context: ModelContext) -> PKPass? {
        let serials = Set((try? context.fetch(
            FetchDescriptor<WalletPassRecord>(predicate: #Predicate { $0.liveId == liveId })))?
            .map(\.serialNumber) ?? [])
        guard !serials.isEmpty else { return nil }
        return library.passes().first { serials.contains($0.serialNumber) }
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
