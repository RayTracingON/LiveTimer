# 日音 Live 日程助手 · iOS 客户端开发文档 v1

> 配套文档：《日音live日程助手-产品提案v2.md》（产品定义）、《LiveTimer-Backend-API文档.md》（后端接口）。
> 本文是给实现方的客户端开发规格。

---

## 0. 边界：客户端负责什么

后端很薄，绝大部分逻辑在客户端。明确分工：

| 能力 | 归属 | 备注 |
|---|---|---|
| 演出 / 场馆 / 艺人数据 | 后端只读 API | 客户端缓存 |
| **用户日程（增删改查）** | **客户端本地 SwiftData** | 后端完全不感知，无账号系统 |
| **巡礼地标数据** | **客户端直连 `api.anitabi.cn`** | 后端不代理、不转存 |
| **酒店 POI** | **客户端 MKLocalSearch** | 只标位置，不显示价格 |
| Apple 日历导出 | 客户端 EventKit | 见 §6.1 |
| Wallet 卡片 | 后端签发 + 客户端呈现 | 见 §6.2 |
| 本地通知 | 客户端 UserNotifications | 见 §6.3 |

**没有账号系统**意味着：换设备数据不迁移。这是 v1 的明确取舍，App 内需要有一句说明，别让用户以为丢数据是 bug。

---

## 1. 技术栈与工程约定

| 项 | 选择 | 理由 |
|---|---|---|
| 最低系统 | **iOS 18.0** | SwiftData 已趋稳定；Wallet 的 poster event ticket 需要 iOS 18；2026 年 9 月 iOS 18 已发布两年，覆盖率足够 |
| UI | SwiftUI | 地图页例外，见 §5.2 |
| 本地存储 | SwiftData | |
| 并发 | Swift Concurrency（async/await、actor） | 不要用 Combine 做网络层 |
| 状态管理 | `@Observable`（Observation 框架） | 不用 `ObservableObject`/`@Published` |
| 第三方依赖 | **零** | 所有需求都能用系统框架满足，别引 Alamofire/Kingfisher |
| 图片加载 | `AsyncImage` + 自建磁盘缓存 | 见 §7.3 |
| 本地化 | 基准语言 **ja**，另出 zh-Hans、en | 用 String Catalog（`.xcstrings`） |

**代码约定**
- 严格并发检查开启（Swift 6 language mode），所有跨 actor 的类型标注 `Sendable`
- 网络层不抛裸 `Error`，统一成 `APIError` 枚举
- 所有面向用户的字符串走 String Catalog，不要硬编码

---

## 2. 工程结构

```
LiveTimer/
├─ App/
│  ├─ LiveTimerApp.swift
│  ├─ RootTabView.swift
│  └─ RemoteConfig.swift          // §4.3 的 feature flag
├─ Core/
│  ├─ Networking/
│  │  ├─ APIClient.swift          // 通用 HTTP 层
│  │  ├─ LiveTimerAPI.swift       // 自有后端
│  │  ├─ AnitabiAPI.swift         // anitabi 直连
│  │  └─ APIError.swift
│  ├─ Persistence/
│  │  ├─ ModelContainer+Setup.swift
│  │  └─ Models/                  // §3 的 @Model
│  ├─ Calendar/CalendarExporter.swift
│  ├─ Wallet/PassManager.swift
│  ├─ Notifications/NotificationScheduler.swift
│  └─ ImageCache/
├─ Features/
│  ├─ Schedule/                   // 日程首页
│  ├─ Map/                        // 地图页
│  ├─ IPSubscription/             // IP 订阅
│  ├─ Detail/                     // 演出/酒店/巡礼点详情
│  └─ Settings/
└─ DesignSystem/
   ├─ Colors.swift
   ├─ Typography.swift
   └─ Components/
```

---

## 3. 本地数据模型（SwiftData）

### 3.1 ScheduleItem —— 核心表

**三类内容归一到一张表**，靠 `kind` + `sourceRef` 区分。周日历渲染、冲突检测、日历导出、通知调度都只针对这张表写一遍逻辑。

```swift
@Model
final class ScheduleItem {
    @Attribute(.unique) var id: UUID
    var kind: ScheduleItemKind        // live / hotel / pilgrimage / custom
    var title: String
    var subtitle: String?
    var startAt: Date
    var endAt: Date?
    var isAllDayBand: Bool            // true = 渲染在顶部横条而非时间网格，酒店恒为 true
    var note: String?

    // 地点
    var locationName: String?
    var locationAddress: String?
    var latitude: Double?
    var longitude: Double?

    // 溯源
    var sourceRef: String?            // liveId / anitabi pointId / MKMapItem 标识
    var sourceSubjectId: Int?         // 巡礼点所属的 bangumi subjectId
    var externalUrl: String?          // 购票链接 / 酒店官网

    // 系统集成回写
    var ekEventIdentifier: String?
    var passSerialNumber: String?
    var notificationIds: [String]

    var createdAt: Date
    var updatedAt: Date
}

enum ScheduleItemKind: String, Codable, CaseIterable {
    case live, hotel, pilgrimage, custom
}
```

**`isAllDayBand` 的意义**：酒店住宿是跨夜的（10/15 入住 → 10/17 退房）。如果按真实时长渲染成 48 小时的垂直色块，周日历会被它整个占满。所以酒店渲染在顶部的横条区域（类似 Apple 日历的全天事件区），只有 Live 和巡礼点进时间网格。这是周视图能不能看的关键，不要省。

### 3.2 缓存表

```swift
@Model final class CachedLive {         // 镜像后端 Live，供离线查看
    @Attribute(.unique) var id: String
    var title: String
    var venueId: String
    var openAt: Date
    var startAt: Date
    var endAt: Date?
    var priceAdvance: Int?
    var priceDoor: Int?
    var drinkFee: Int?
    var ticketUrl: String?
    var coverImageUrl: String?
    var status: String
    var lineupJSON: Data                 // 精简 lineup 直接存 JSON，不建关联表
    var updatedAt: Date
    var cachedAt: Date
}

@Model final class CachedVenue {
    @Attribute(.unique) var id: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var nearestStation: String?
    var upcomingLiveCount: Int
    var nextLiveAt: Date?
    var updatedAt: Date
}
```

### 3.3 巡礼相关

```swift
@Model final class SubscribedIP {        // 用户订阅的作品
    @Attribute(.unique) var bangumiSubjectId: Int
    var titleOriginal: String
    var titleCn: String?
    var coverUrl: String?
    var themeColorHex: String?
    var defaultLatitude: Double
    var defaultLongitude: Double
    var pointCount: Int
    var subscribedAt: Date

    var anitabiModified: Int?            // ← 缓存失效判据，见 §7.2
    var pointsFetchedAt: Date?
}

@Model final class CachedPilgrimagePoint {
    @Attribute(.unique) var id: String   // anitabi 的 point id
    var subjectId: Int
    var name: String                     // 原名
    var nameCn: String?
    var imageUrl: String?                // 不含 plan 参数的 base，用时再拼
    var episode: Int?
    var seconds: Int?
    var latitude: Double
    var longitude: Double
    var origin: String?                  // ← 署名，必填展示
    var originURL: String?               // ← 来源跳转，必填实现
}
```

`origin` / `originURL` 不是可选的展示项，是授权要求，见 §9。

### 3.4 其他

```swift
@Model final class WalletPassRecord {
    @Attribute(.unique) var serialNumber: String
    var liveId: String
    var addedAt: Date
}
```

---

## 4. 网络层

### 4.1 APIClient

一个泛型 `async` HTTP 客户端即可：

```swift
actor APIClient {
    func get<T: Decodable>(_ url: URL, headers: [String: String] = [:]) async throws -> T
    func post<B: Encodable, T: Decodable>(_ url: URL, body: B) async throws -> T
    func getData(_ url: URL) async throws -> Data   // pkpass 用
}
```

- 超时 15s，失败重试 2 次（指数退避），仅对 5xx 和网络错误重试，4xx 不重试
- 日期解码：ISO8601 带偏移量，`.iso8601` 配合 `formatOptions = [.withInternetDateTime]`

### 4.2 AnitabiAPI

```swift
// 轻量信息，用于刷新 modified 判断缓存
GET https://api.anitabi.cn/bangumi/{subjectID}/lite

// 全量地标
GET https://api.anitabi.cn/bangumi/{subjectID}/points/detail?haveImage=true
```

**三条硬性约束**（来自 anitabi 官方文档）：

1. **绝不请求主域 `https://anitabi.cn/`** —— 文档明确说明主域不保证资源地址与数据结构的稳定。只用 `api.anitabi.cn` 与 `image.anitabi.cn`。
2. **图片尺寸**：地图 Pin 与列表缩略图用 `?plan=h160`，详情页大图用 `?plan=h360`。**禁止使用去掉 plan 参数的完整尺寸图**——官方明确不建议在任何展示界面使用，大量请求会给对方服务器造成压力。
3. **署名**：每个地标展示处必须显示 `origin` 文字并实现 `originURL` 跳转。

把这三条写成代码注释放在 `AnitabiAPI.swift` 顶部。

**礼貌调用**：请求带能标识本 App 的 User-Agent；同一 subjectId 的 detail 拉取加 1 小时内的去重锁，避免用户反复进出地图触发重复请求。

### 4.3 RemoteConfig

App 启动时拉 `/api/v1/meta/config`，结果存 UserDefaults 作为下次启动的兜底。

```swift
@Observable final class RemoteConfig {
    var pilgrimageLayerEnabled: Bool = true
    var walletPassEnabled: Bool = true
    var hotelLayerEnabled: Bool = true
    var disclaimers: [String: String] = [:]
}
```

`pilgrimageLayerEnabled == false` 时：地图隐藏图层 C 开关、IP 订阅入口隐藏、已有的巡礼日程条目**保留但不再拉新数据**（不要删用户数据）。

---

## 5. 界面规格

视觉规范（配色、字体、间距）由设计稿提供，本节只定义结构与行为。

### 5.1 日程首页 —— 周视图

**这是本 App 工作量最大、也最值得投入的单个页面。**

#### 布局

```
┌─────────────────────────────────┐
│ 2026年10月      [周][月][列表] │ ← 顶部栏
├─────────────────────────────────┤
│  月 火 水 木 金 土 日            │ ← 日期行（固定）
│  13 14 15 16 17 18 19           │
├─────────────────────────────────┤
│ ▓▓▓▓ ホテル 3泊 ▓▓▓▓            │ ← 全天横条区（酒店）
├─────────────────────────────────┤
│ 09 │   │   │   │   │            │
│ 10 │   │▓巡│   │   │            │ ← 时间网格（可垂直滚动）
│ ...│   │礼▓│   │   │            │
│ 19 │   │▓▓▓│   │   │            │
│ 20 │   │Live│  │   │            │
└─────────────────────────────────┘
```

- 顶部栏 + 日期行固定，时间网格垂直滚动
- 首次进入滚动到当日的第一个事件；若当日无事件，滚到 09:00
- 左右滑动切换周（`TabView(.page)` 或 `ScrollView(.horizontal)` + paging）
- 「今天」列有背景高亮；当前时刻有一条红色指示线（仅在本周显示）

#### 事件色块

- 四类各有色（Live / 酒店 / 巡礼 / 自定义），色值取自设计 token
- 最小高度 22pt（30 分钟以下的事件也要能点中）
- 色块内容按高度降级：>44pt 显示标题+时间+地点；22–44pt 只显示标题；<22pt 只显示色块

#### 重叠布局算法

同一天内时间重叠的事件需要并排。标准做法：

```
1. 取当天所有非全天事件，按 startAt 升序排
2. 扫描分组：维护当前组的 maxEndAt，若下一个事件的 startAt < maxEndAt 则并入同组，
   否则结束当前组、开新组
3. 组内贪心分列：对每个事件，找第一个「最后一个事件已结束」的列放入，
   没有可用列则新开一列
4. 组内列数 n → 每个事件宽度 = 列宽/n，x 偏移 = 列索引 × 宽度
```

边界情况：一组内超过 3 列时，只渲染前 2 列并在第 3 列位置显示「+N」，点击展开当日列表视图。否则色块会窄到无法辨认。

#### 冲突提示

同组内**且都是 Live 类型**的事件视为真冲突（酒店和 Live 重叠是正常的），给色块加警示色描边 + 一个小图标。**不弹窗、不阻止用户添加**——用户可能就是想先都加进来再取舍。

#### 其他视图

- **月视图**：标准月历，每格显示至多 3 个事件的色点，点击日期跳到该日的列表
- **列表视图**：按日期分组的垂直列表，是周视图的无障碍降级方案，也用于「+N」展开

#### 交互

- 点击色块 → 事件详情 sheet
- 长按时间网格空白 → 新建自定义事件（预填长按位置对应的时间）
- 色块左滑 → 删除
- 顶部「今天」按钮回到当周

#### 空状态

新用户第一次打开看到的就是空日历。必须做好：一段说明 + 一个明确的「去地图看看」CTA 按钮，直接跳转地图 Tab。

### 5.2 地图页

#### 用 MKMapView 而不是 SwiftUI Map

**这是一个需要提前定下来的技术决策。** SwiftUI 的 `Map` 没有内置聚合（clustering）。用户订阅 10–20 部作品后，巡礼点总数会到数千个（单部作品就可能有近 400 个地标），SwiftUI Map 直接渲染会卡死。

因此地图页用 `UIViewRepresentable` 包 `MKMapView`：
- 用 `MKMarkerAnnotationView.clusteringIdentifier` 做原生聚合，三个图层用不同的 identifier（不要跨图层聚合）
- 只向地图添加当前可视区域 + 一定 padding 内的标注
- 巡礼点在 zoom level 低于阈值时不渲染（只显示作品级的聚合点）

#### 三个图层

| 图层 | 数据源 | Pin 样式 | 加载时机 |
|---|---|---|---|
| A · Live 场馆 | `GET /api/v1/venues?bbox=` | 场馆名 + 最近场次日期 | 地图区域变化，debounce 500ms |
| B · 酒店 | `MKLocalSearch` | 品牌图标，**无价格** | 同上，debounce 800ms |
| C · 巡礼地标 | SwiftData 本地缓存 | 截图缩略图（h160） | 本地查询，无网络 |

图层开关状态存 `@AppStorage`，跨启动保持。

#### 图层 B 的搜索细节

```swift
let request = MKLocalSearch.Request()
request.naturalLanguageQuery = query
request.region = mapView.region
request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.hotel])
```

**要点**：
- 日本地区的 POI 名称可能是日文，需要对每个品牌搜多个关键词：`"Marriott"` / `"マリオット"`、`"Hilton"` / `"ヒルトン"`，结果按 `MKMapItem` 的坐标去重
- `MKLocalSearch` 有 Apple 侧的调用频率限制，**必须 debounce**，且地图移动幅度小于阈值时不重新搜索
- 返回的 `MKMapItem` 只有名称、地址、电话、`url`，**没有价格和空房**。UI 上不要留价格占位符，直接不显示该字段
- 结果可能不完整或包含非本品牌的匹配项，详情页需注明「位置信息来自 Apple 地图，请以官网为准」

#### 底部 sheet

`.presentationDetents([.height(120), .medium, .large])` 三档：
- 收起：显示「当前视野内 N 场演出 / N 家酒店 / N 个地标」
- 中：分段控件切换三类结果的列表
- 展开：全屏列表

#### 顶部日期选择器

切换日期会刷新图层 A（该日期附近的场次）。图层 B、C 不受日期影响。

#### 搜索框

统一搜索入口，结果分三段：场馆 / 城市（地理编码）/ 已订阅作品。**不搜未订阅的作品**——订阅走 §5.3 的独立入口。

### 5.3 IP 订阅页

入口：地图页图层 C 开关旁的「管理作品」，以及「我的」页。

- 列表展示 `GET /api/v1/ip-catalog` 返回的策展作品（封面、原名、中文名、地标数、主要城市）
- 支持按都道府県筛选、按名称搜索
- 点击「添加」→ 写入 `SubscribedIP` → 后台拉取该作品的 `points/detail` → 落 `CachedPilgrimagePoint`
- 添加时显示进度（几百个点的拉取和图片预热需要几秒）
- 已订阅的作品可移除；移除时**询问是否同时删除已加入日程的该作品地标**，默认保留

> 注意：这里叫「订阅作品」不叫「收藏」。本产品没有收藏/喜欢体系，UI 上不要出现心形图标。

### 5.4 详情页

#### 演出详情

- 主视觉、演出标题、lineup（headliner 加粗）
- **开场 / 开演分两行显示**——这是日本 live 的重要惯例，不要合并成一个时间
- 票价：前売 / 当日两档 + ドリンク代单独一行
- 场馆名、地址、最近车站、地图缩略图（点击唤起系统地图导航）
- 三个动作：
  1. **加入日程**（主按钮）
  2. **添加到 Apple Wallet**（用 `PKAddPassButton`，见 §6.2）
  3. **前往购票**（外链，`SFSafariViewController`）
- `status != SCHEDULED` 时顶部显示醒目的状态横幅（中止/延期/售罄）

#### 酒店详情

- 名称、品牌、地址、电话
- 到日程中最近一场 Live 的直线距离 + 预估步行时间（用 `MKDirections` 算，可选）
- 动作：加入日程（弹出入住/退房日期选择）/ 前往官网
- **必须显示**：「本 App 不提供预订服务，房价与空房请以官网为准」

#### 巡礼地标详情

- 动画截图大图（`?plan=h360`）
- 地标原名 + 中文译名、所属作品、集数与时间点（`ep` / `s`，`s` 格式化为 `mm:ss`）
- **来源署名区块**：`origin` 文字 + 可点击的 `originURL`，位置固定在截图正下方，字号不小于 caption，不得折叠或隐藏
- 动作：加入日程 / 在地图中查看 / 导航

### 5.5 我的

- Apple 日历导出设置（见 §6.1）
- 已添加的 Wallet 卡片列表
- 通知设置（开场前提醒的提前量：15/30/60 分钟/自定义）
- 订阅作品管理入口
- 数据说明页：巡礼数据来源与授权声明、酒店位置数据来源声明、「数据仅存本地，换设备不迁移」的说明
- 关于 / 隐私政策 / 反馈

---

## 6. 系统能力集成

### 6.1 EventKit —— 有一个重要限制要先决定

**iOS 17+ 提供两种权限**：

| 权限 | API | 能做 | 不能做 |
|---|---|---|---|
| 仅写入 | `requestWriteOnlyAccessToEvents()` | 向默认日历添加事件 | **读取、更新、删除已创建的事件；创建专属日历** |
| 完全访问 | `requestFullAccessToEvents()` | 全部 | —— |

**关键后果**：仅写入权限下，你无法通过 `ekEventIdentifier` 取回事件，因此**无法实现「App 内修改日程 → 系统日历同步更新」，也无法在用户删除日程时清理系统日历里的事件**。之前提案里写的「创建专属『日音Live』日历」也需要完全访问。

**v1 建议：用仅写入权限，导出做成单向、一次性的动作。**

- 按钮文案写成「导出到 Apple 日历」而非「同步」
- 导出成功后给明确提示：「已添加到日历。之后在本 App 修改不会同步，需要重新导出。」
- 仍然记录 `ekEventIdentifier`，用于本地标记「已导出过」，避免重复导出

理由：仅写入的权限弹窗对用户友好得多（不需要交出全部日历数据的读取权），对一个还没建立信任的新 App 很重要。双向同步是明显的 v2 功能，届时再申请完全访问并说明理由。

**导出的事件内容**：

```swift
event.title = item.title
event.startDate = item.startAt
event.endDate = item.endAt ?? item.startAt.addingTimeInterval(2*3600)
event.location = "\(locationName)\n\(locationAddress)"   // 触发系统的交通时间预估
event.structuredLocation = EKStructuredLocation(...)      // 带坐标，效果更好
event.notes = "开场 18:00 / 开演 19:00\n购票：\(ticketUrl)"
event.addAlarm(EKAlarm(relativeOffset: -3600))
event.calendar = eventStore.defaultCalendarForNewEvents
```

**Info.plist**：`NSCalendarsWriteOnlyAccessUsageDescription`

### 6.2 PassKit / Apple Wallet

**流程**

```swift
// 1. 检查设备支持
guard PKAddPassesViewController.canAddPasses() else { /* 隐藏按钮 */ }

// 2. 向后端要 pkpass
let data = try await api.getData(POST /api/v1/passes, body: ["liveId": id])

// 3. 构造并呈现
let pass = try PKPass(data: data)
let vc = PKAddPassesViewController(pass: pass)!
present(vc)   // 用 UIViewControllerRepresentable 包装

// 4. delegate 回调成功后落库 WalletPassRecord
```

**要点**
- 按钮用 `PKAddPassButton`，不要自绘——Apple 对 Add to Wallet 按钮的样式有规范
- 查询卡片是否已在钱包里用 `PKPassLibrary().containsPass(_:)`，**这需要 `com.apple.developer.pass-type-identifiers` entitlement**，值填你的 Pass Type ID。忘了配会静默返回 false
- `walletPassEnabled == false`（远程配置）时整个入口隐藏

**必须做的文案处理**：卡片和 App 内都要明确这**不是入场券**。演出详情页的 Wallet 按钮下方加一行小字：「※ 这是行程提醒卡，不是入场券」。这既是审核风险规避，也是防止用户拿着它去场馆被拒。

### 6.3 本地通知

- Live 加入日程时自动排一条开场前提醒（默认提前 60 分钟，可在设置改）
- 用 `UNCalendarNotificationTrigger`
- 删除日程条目时同步移除 `notificationIds` 对应的通知
- iOS 有 64 条待处理通知的上限：只为**最近 30 天内**的事件排通知，App 每次启动时重算一遍

### 6.4 权限与 Info.plist

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>地図上に現在地を表示し、近くの会場を探すために使用します。</string>

<key>NSCalendarsWriteOnlyAccessUsageDescription</key>
<string>選んだ予定を Apple カレンダーに書き出すために使用します。</string>
```

位置权限是**可选的**——不给也能用地图，只是不显示「我的位置」。不要在启动时就弹权限请求，等用户点「定位到我」按钮时再申请。

---

## 7. 缓存与离线

### 7.1 演出数据

- 首次启动拉取未来 60 天的演出与场馆，落 `CachedLive` / `CachedVenue`
- 之后用 `?updatedSince=` 增量拉取，`updatedSince` 存 UserDefaults
- 后端返回 `"deleted": true` 的墓碑记录时，删除本地对应缓存，**但不删用户已加入日程的 ScheduleItem**——改为标记该条目为「演出信息已失效」并在 UI 上提示
- 离线时读缓存，顶部显示离线条

### 7.2 巡礼数据 —— 用 `modified` 做失效判断

anitabi 的 `/lite` 接口返回一个 `modified` 时间戳。利用它避免反复拉取几百个点的 detail：

```
刷新某个订阅作品时：
  1. GET /bangumi/{id}/lite            ← 很轻
  2. if response.modified > cached.anitabiModified {
         GET /bangumi/{id}/points/detail  ← 重，仅在数据真变了时才调
         替换该 subjectId 下的所有 CachedPilgrimagePoint
         更新 anitabiModified
     }
```

刷新时机：用户手动下拉刷新，以及每个作品每 7 天最多一次的后台检查。**不要在每次进入地图页时刷新。**

### 7.3 图片缓存

自建一个简单的磁盘缓存（`URLCache` 配大容量 + 自定义 key，或直接用 `FileManager` 按 URL hash 存）：
- 巡礼截图 h160 缓存 30 天，h360 缓存 7 天
- 总容量上限 200MB，超出按 LRU 清理
- 设置页提供「清除图片缓存」

不要引 Kingfisher/SDWebImage，需求没复杂到那个程度。

---

## 8. 实现优先级

| 阶段 | 内容 |
|---|---|
| **P0** | 工程骨架、SwiftData 模型、APIClient、RemoteConfig |
| **P0** | 周日历首页（含重叠布局算法、全天横条、空状态） |
| **P0** | 地图页 MKMapView 容器 + 图层 A（Live 场馆） |
| **P0** | 演出详情页 + 加入日程 |
| **P1** | EventKit 导出 |
| **P1** | 图层 B（酒店 MKLocalSearch） |
| **P1** | 月视图 / 列表视图 |
| **P2** | IP 订阅页 + 图层 C（巡礼）+ 巡礼详情页 |
| **P2** | Wallet 卡片 |
| **P2** | 本地通知、离线降级、图片缓存优化 |

**建议**：P0 里的周日历先做出能跑的版本（哪怕布局粗糙），因为它是首页，越早看到真实数据在上面的样子，越早能发现设计问题。

---

## 9. 硬性合规要求（不可省略）

实现时这几条不是「最好有」，是「必须有」：

1. **巡礼地标的 `origin` 署名与 `originURL` 跳转**，在每个展示地标截图的地方都要有，且不得折叠/隐藏。这是 anitabi 数据 CC BY-NC-SA 协议里 BY（署名）条款的要求。
2. **不请求 `https://anitabi.cn/` 主域**，只用 `api.anitabi.cn` / `image.anitabi.cn`。
3. **不使用 anitabi 的完整尺寸原图**，只用 `?plan=h160` / `?plan=h360`。
4. **Wallet 卡片必须标明不是入场券**。
5. **酒店页必须标明不提供预订服务、价格以官网为准**。

第 1–3 条建议在 `AnitabiAPI.swift` 顶部写成注释，并在 code review checklist 里列出来。

> 补充给你自己看的：CC BY-NC-SA 的 **NC 条款要求 App 保持免费且无内购、无广告**。哪天要商业化，先用后端的 `features.pilgrimageLayer` 开关关掉巡礼功能，再去谈授权。

---

## 10. 待你确认的决策点

1. **EventKit 用仅写入还是完全访问**（§6.1）。我建议 v1 用仅写入 + 单向导出，但这意味着用户在 App 里改了日程，系统日历不会跟着变。如果你觉得这个体验不能接受，就得申请完全访问。
2. **最低系统定 iOS 18 还是 17**。定 17 的话 Wallet 的 poster 样式要做降级分支。
3. **一次订阅作品数是否设上限**。不限的话极端用户可能订几十部，本地点位上万，地图性能需要更激进的策略。建议 v1 软上限 20 部并给提示。
