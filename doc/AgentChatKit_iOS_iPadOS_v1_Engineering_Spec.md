# AgentChatKit — iOS / iPadOS 生产级开源组件工程规格

> 文档状态：Implementation Baseline  
> 规格版本：1.0-draft  
> 核对日期：2026-08-10  
> 仓库建议：`agent-chat-kit`  
> Swift Package：`AgentChatKit`  
> 首发平台：iOS 17+、iPadOS 17+  
> 技术路线：UIKit-first、Swift Concurrency、Swift Package Manager  
> 许可证：Apache-2.0  
> v1.0 不包含：原生 macOS / AppKit、Agent Loop、模型调用、Shell 执行器、文件系统实现、网络传输实现

---

## 0. 给 Codex 的执行要求

本文件是 `AgentChatKit` v1.0 的规范性工程文档。研发时必须遵守以下规则：

1. 先完整阅读本文件，再开始创建代码。
2. 严格按照“阶段计划”逐步实现，不先堆砌 UI，不从截图硬编码 Cell。
3. 每个阶段必须同时交付：
   - 可编译代码；
   - 可运行 Demo；
   - 对应测试；
   - 对应文档更新；
   - `IMPLEMENTATION_STATUS.md` 中的完成记录。
4. 不允许用空实现、`fatalError("TODO")`、占位返回值或注释假装完成功能。
5. 不允许实现 Agent Loop、模型请求、Shell、文件操作、MCP Host 或业务数据库。
6. 不允许把任何具体 Runtime 协议写死在 Core 或 UIKit 中。
7. 不允许为了赶进度把一整条 Assistant 回复塞入一个巨大 Cell。
8. 不允许在流式过程中调用 `reloadData()` 或每个 token 重建完整 Diffable Snapshot。
9. 不允许在 Core、Runtime SPI、Reducer 中导入 UIKit。
10. v1.0 不实现 AppKit；但公共模型和 Runtime SPI 必须保持平台无关，为后续 macOS 复用。
11. 所有 public API 必须有 DocC 注释；所有 public 类型必须显式评估 `Sendable`。
12. 每次改动公共 API，都必须同步更新示例、测试、README 和 Changelog。
13. 完成标准以本文“v1.0 验收清单”为准，而不是以“页面看起来能运行”为准。
14. 如规范中的示例代码存在轻微 Swift 语法问题，可以做最小修正；不得改变架构边界。
15. 最终交付前必须执行完整构建、单元测试、UI 测试、性能场景和无障碍检查，并输出结果。

---

## 1. 结论与范围决策

### 1.1 为什么 v1.0 只做 iOS + iPadOS

iPhone 与 iPad 共享 UIKit、`UICollectionView`、同一套 Cell、Diffable Data Source、键盘系统和大部分交互代码。iPad 的增量工作主要是宽屏布局、尺寸变化、外接键盘、指针、拖放、Split View 和 Stage Manager。

原生 macOS 则需要单独实现 AppKit 展示层，包括 `NSCollectionView`、文本系统、菜单、窗口、快捷键、拖放、滚动锚点和桌面交互。它不是给 UIKit 代码加几个条件编译即可完成。

因此首发范围确定为：

```text
AgentChatKit v1.0
├── iPhone
├── iPad
├── UIKit
├── Runtime Adapter SPI
├── 生产级 Agent 会话 UI
└── 完整测试与文档

后续版本
├── AgentChatAppKit
├── 原生 macOS 会话 UI
└── CodexMac 真实示例
```

### 1.2 工作量规划估算

以下为工程规划估算，不是承诺工期：

| 范围 | 相对工作量 |
|---|---:|
| iPhone 基础版 | 100 |
| 完整 iPad 适配 | +15% ～ 25% |
| 可运行的 Mac Catalyst 验证版 | +10% ～ 20% |
| 生产级原生 AppKit 版 | 在 iOS+iPadOS 基础上再增加约 50% ～ 80% 的 UI/测试工作 |

v1.0 不把 Mac Catalyst 或 AppKit 作为验收项。

---

## 2. 产品定位

### 2.1 一句话定位

> A production-grade, block-based UIKit conversation UI for mobile AI agents.

中文：

> 面向 iPhone 与 iPad 的生产级 UIKit AI Agent 会话组件。

### 2.2 开发者获得什么

接入方只需实现一个 Runtime Adapter，将现有 Agent Loop 的事件映射为 AgentChatKit 的标准前端事件，即可获得：

- 用户输入与 Assistant 回合；
- 流式 Markdown；
- Activity / 状态摘要；
- 通用 Tool Call；
- Shell Command 展示与流式输出；
- 文件搜索与文件操作展示；
- Unified Diff；
- Approval / 人工确认；
- Artifact；
- 错误、停止、重试；
- 历史分页；
- 输入区与附件入口；
- 长会话滚动与位置保持；
- 自定义 Tool Renderer；
- iPhone / iPad 自适应；
- Light / Dark、Dynamic Type、VoiceOver；
- 测试工具和 Mock Runtime。

### 2.3 AgentChatKit 不负责什么

以下均由宿主 App 或 Runtime 负责：

- Agent Loop；
- LLM 请求；
- SSE、WebSocket、JSON-RPC、XPC、stdio 等传输；
- Shell 命令执行；
- 文件读取与写入；
- Git；
- 浏览器；
- MCP Host；
- 权限策略；
- 用户登录；
- 会话数据库；
- 项目/仓库选择；
- 侧边栏和 App Shell；
- Runtime 安装、升级与进程管理；
- 远程 Mac Bridge；
- 原始私有思维链展示。

AgentChatKit 只接收结构化状态、渲染 UI，并将用户动作回传给 Runtime Adapter 或宿主。

---

## 3. 核心设计原则

### 3.1 窄入口，宽架构

对外名称保持简单：

```text
AgentChatKit
```

内部能力按完整 Agent Frontend 设计，不把项目限制为“用户气泡 + AI 气泡”。

### 3.2 Runtime 无关

不得绑定：

- OpenAI；
- Codex；
- Claude；
- Qwen；
- OpenCode；
- AG-UI；
- 任意公司自研协议。

具体 Runtime 通过 Adapter 接入。

### 3.3 Block-first，而不是 Message-first

普通聊天模型：

```text
Message(role, text)
```

不足以表达 Agent 工作过程。

AgentChatKit 使用：

```text
Conversation
└── Turn
    └── Block
```

一轮 Assistant 内容可以是：

```text
Markdown
→ File Search
→ Activity
→ Command
→ Command Output
→ File Change
→ Diff
→ Approval
→ Markdown
```

### 3.4 一次回合一个 Section，一个 Block 一个 Item

UICollectionView 结构必须是：

```text
Turn = Section
Block = Item
```

禁止：

```text
一整轮 Assistant = 一个巨大 UICollectionViewCell
```

### 3.5 Core 与 UIKit 分离

```text
AgentChatCore
├── 模型
├── Runtime SPI
├── Reducer
├── Store Snapshot
└── 事件归并

AgentChatMarkdown
├── Markdown AST 转换
└── 平台无关 Render Document

AgentChatUIKit
├── UIViewController
├── UICollectionView
├── Cell / Renderer
├── Composer
├── 键盘
└── iPad 交互
```

### 3.6 默认安全

- 不执行任何 Tool；
- 不解析并执行 HTML；
- 不自动打开未知 URL；
- 不把 Command Output 当成富 HTML；
- 不记录用户内容和工具输出；
- Approval 默认只能响应一次；
- 未知 Block 必须安全回退，不能崩溃。

---

## 4. 技术基线

### 4.1 平台

```swift
platforms: [
    .iOS(.v17)
]
```

iPadOS 使用同一 iOS Package 平台声明。

### 4.2 Swift

- `swift-tools-version: 6.0`
- 开启 Swift 6 严格并发检查；
- UIKit API 标记 `@MainActor`；
- Core actor 不依赖主线程；
- 禁止无审计地使用 `@unchecked Sendable`。

### 4.3 主要依赖

正式依赖：

1. `ChatLayout`
   - 仅在 `AgentChatUIKit` 内部使用；
   - 不在 public API 暴露其类型；
   - 使用 `CollectionViewChatLayout` 驱动 UICollectionView；
   - 依赖版本固定到经过 CI 验证的稳定版本。

2. `swift-markdown`
   - 仅负责 Markdown 解析；
   - 不直接把其 AST 类型暴露为 public API；
   - 转换为 AgentChatKit 自有的不可变 Render Document。

测试依赖可包含：

- `swift-snapshot-testing`，仅用于测试；
- 其他测试依赖必须是 test-only。

### 4.4 禁止的实现捷径

- 禁止使用 `WKWebView` 渲染整条 Markdown；
- 禁止使用 HTML 转 `NSAttributedString` 作为主渲染路径；
- 禁止把 Tool 信息编码进 Markdown 特殊标签再解析；
- 禁止业务层持有 UICollectionView IndexPath 作为稳定 ID；
- 禁止让 ChatLayout 类型泄漏到 public API；
- 禁止依赖单例屏幕尺寸或单例 Session；
- 禁止在 Cell 内直接发起 Runtime 命令。

---

## 5. 仓库与 Package 结构

```text
agent-chat-kit/
├── Package.swift
├── README.md
├── LICENSE
├── NOTICE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── IMPLEMENTATION_STATUS.md
│
├── Sources/
│   ├── AgentChatCore/
│   │   ├── IDs/
│   │   ├── Models/
│   │   ├── Runtime/
│   │   ├── Events/
│   │   ├── Reducer/
│   │   ├── Store/
│   │   ├── Logging/
│   │   └── Utilities/
│   │
│   ├── AgentChatMarkdown/
│   │   ├── Parser/
│   │   ├── RenderDocument/
│   │   ├── Diff/
│   │   └── Utilities/
│   │
│   ├── AgentChatUIKit/
│   │   ├── Conversation/
│   │   ├── DataSource/
│   │   ├── Layout/
│   │   ├── Scrolling/
│   │   ├── Rendering/
│   │   ├── Cells/
│   │   ├── Blocks/
│   │   ├── Markdown/
│   │   ├── Composer/
│   │   ├── Keyboard/
│   │   ├── Theme/
│   │   ├── Accessibility/
│   │   └── Resources/
│   │
│   └── AgentChatTesting/
│       ├── MockRuntime/
│       ├── Fixtures/
│       ├── EventBuilder/
│       ├── ScenarioRunner/
│       └── Assertions/
│
├── Tests/
│   ├── AgentChatCoreTests/
│   ├── AgentChatMarkdownTests/
│   ├── AgentChatUIKitTests/
│   ├── AgentChatIntegrationTests/
│   └── AgentChatPerformanceTests/
│
├── Examples/
│   └── AgentChatDemo/
│       ├── AgentChatDemo.xcodeproj
│       ├── App/
│       ├── Scenarios/
│       └── CustomRenderers/
│
└── Documentation/
    ├── Architecture.md
    ├── Integration.md
    ├── RuntimeAdapter.md
    ├── CustomBlocks.md
    ├── Markdown.md
    ├── Performance.md
    ├── Accessibility.md
    ├── Security.md
    └── Migration.md
```

### 5.1 Package 产品

```swift
.library(name: "AgentChatCore", targets: ["AgentChatCore"])
.library(name: "AgentChatMarkdown", targets: ["AgentChatMarkdown"])
.library(name: "AgentChatUIKit", targets: ["AgentChatUIKit"])
.library(name: "AgentChatTesting", targets: ["AgentChatTesting"])
.library(
    name: "AgentChatKit",
    targets: [
        "AgentChatCore",
        "AgentChatMarkdown",
        "AgentChatUIKit"
    ]
)
```

---

## 6. Core 公共模型

以下接口为规范方向。实现时可做最小语法调整，但不得改变职责边界。

### 6.1 强类型 ID

禁止在内部到处裸用 `String`。

```swift
public struct AgentConversationID:
    RawRepresentable,
    Hashable,
    Codable,
    Sendable,
    ExpressibleByStringLiteral
{
    public let rawValue: String
}

public struct AgentTurnID:
    RawRepresentable,
    Hashable,
    Codable,
    Sendable,
    ExpressibleByStringLiteral
{
    public let rawValue: String
}

public struct AgentBlockID:
    RawRepresentable,
    Hashable,
    Codable,
    Sendable,
    ExpressibleByStringLiteral
{
    public let rawValue: String
}

public struct AgentApprovalID:
    RawRepresentable,
    Hashable,
    Codable,
    Sendable,
    ExpressibleByStringLiteral
{
    public let rawValue: String
}
```

还应包含：

- `AgentRunID`
- `AgentEventID`
- `AgentArtifactID`
- `AgentAttachmentID`

### 6.2 JSONValue

自定义 Runtime 元数据不得使用 `[String: Any]`。

```swift
public enum JSONValue: Hashable, Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}
```

### 6.3 Conversation

```swift
public struct AgentConversationSnapshot:
    Hashable,
    Codable,
    Sendable
{
    public var id: AgentConversationID
    public var title: String?
    public var turns: [AgentTurn]
    public var state: AgentConversationState
    public var earlierHistoryCursor: AgentHistoryCursor?
    public var hasEarlierHistory: Bool
    public var metadata: [String: JSONValue]
}
```

### 6.4 Turn

```swift
public struct AgentTurn:
    Identifiable,
    Hashable,
    Codable,
    Sendable
{
    public var id: AgentTurnID
    public var role: AgentTurnRole
    public var blocks: [AgentBlock]
    public var state: AgentTurnState
    public var createdAt: Date
    public var completedAt: Date?
    public var metadata: [String: JSONValue]
}

public enum AgentTurnRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public enum AgentTurnState: Hashable, Codable, Sendable {
    case pending
    case streaming
    case running
    case waitingForApproval
    case completed
    case failed(AgentFailure)
    case cancelled
}
```

### 6.5 Block

```swift
public struct AgentBlock:
    Identifiable,
    Hashable,
    Codable,
    Sendable
{
    public var id: AgentBlockID
    public var kind: AgentBlockKind
    public var content: AgentBlockContent
    public var state: AgentBlockState
    public var revision: Int64
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: JSONValue]
}
```

`revision` 必须单调递增，用于阻止旧更新覆盖新状态。

### 6.6 BlockKind

使用可扩展字符串类型，而不是封闭 enum：

```swift
public struct AgentBlockKind:
    RawRepresentable,
    Hashable,
    Codable,
    Sendable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public static let userText = Self(rawValue: "user.text")
    public static let markdown = Self(rawValue: "assistant.markdown")
    public static let activity = Self(rawValue: "agent.activity")
    public static let tool = Self(rawValue: "tool.generic")
    public static let command = Self(rawValue: "tool.command")
    public static let fileSearch = Self(rawValue: "tool.file-search")
    public static let fileOperation = Self(rawValue: "tool.file-operation")
    public static let diff = Self(rawValue: "tool.diff")
    public static let approval = Self(rawValue: "agent.approval")
    public static let artifact = Self(rawValue: "agent.artifact")
    public static let image = Self(rawValue: "content.image")
    public static let error = Self(rawValue: "agent.error")
}
```

企业工具可以使用：

```text
company.calendar.event
github.pull-request
mcp.database.query
```

### 6.7 BlockContent

```swift
public enum AgentBlockContent:
    Hashable,
    Codable,
    Sendable
{
    case userText(UserTextBlock)
    case markdown(MarkdownBlock)
    case activity(ActivityBlock)
    case tool(ToolBlock)
    case command(CommandBlock)
    case fileSearch(FileSearchBlock)
    case fileOperation(FileOperationBlock)
    case diff(DiffBlock)
    case approval(ApprovalBlock)
    case artifact(ArtifactBlock)
    case image(ImageBlock)
    case error(ErrorBlock)
    case custom(CustomBlock)
}
```

Reducer 必须校验 `kind` 与内置 `content` 是否匹配；不匹配时记录错误并回退到 Generic Renderer，不能崩溃。

### 6.8 BlockState

```swift
public enum AgentBlockState: Hashable, Codable, Sendable {
    case queued
    case streaming
    case running(progress: Double?)
    case waitingForApproval
    case succeeded
    case failed(AgentFailure)
    case cancelled
}
```

### 6.9 内置 Block 模型

#### UserTextBlock

```swift
public struct UserTextBlock: Hashable, Codable, Sendable {
    public var text: String
    public var attachments: [AgentAttachment]
}
```

#### MarkdownBlock

```swift
public struct MarkdownBlock: Hashable, Codable, Sendable {
    public var markdown: String
    public var isFinal: Bool
}
```

#### ActivityBlock

只用于适合用户阅读的执行摘要，不用于暴露模型私有思维链。

```swift
public struct ActivityBlock: Hashable, Codable, Sendable {
    public var title: String
    public var detail: String?
}
```

#### ToolBlock

```swift
public struct ToolBlock: Hashable, Codable, Sendable {
    public var toolName: String
    public var title: String
    public var summary: String?
    public var input: JSONValue?
    public var output: JSONValue?
    public var displayMode: AgentToolDisplayMode
}
```

#### CommandBlock

```swift
public struct CommandBlock: Hashable, Codable, Sendable {
    public var command: String
    public var workingDirectory: String?
    public var output: AgentTextBuffer
    public var exitCode: Int?
    public var duration: TimeInterval?
}
```

`AgentTextBuffer` 必须使用分块存储，禁止每个输出增量直接对超长 `String` 做无限重复拼接。

#### FileSearchBlock

```swift
public struct FileSearchBlock: Hashable, Codable, Sendable {
    public var query: String
    public var root: String?
    public var matches: [AgentFileMatch]
    public var totalCount: Int?
}
```

#### FileOperationBlock

```swift
public enum AgentFileOperation: String, Codable, Sendable {
    case read
    case create
    case update
    case delete
    case move
}

public struct FileOperationBlock: Hashable, Codable, Sendable {
    public var operation: AgentFileOperation
    public var path: String
    public var destinationPath: String?
    public var summary: String?
}
```

#### DiffBlock

```swift
public struct DiffBlock: Hashable, Codable, Sendable {
    public var title: String?
    public var files: [AgentDiffFile]
    public var rawUnifiedDiff: String?
}
```

#### ApprovalBlock

```swift
public enum AgentApprovalRisk: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct ApprovalBlock: Hashable, Codable, Sendable {
    public var approvalID: AgentApprovalID
    public var title: String
    public var message: String?
    public var risk: AgentApprovalRisk
    public var choices: [AgentApprovalChoice]
    public var resolution: AgentApprovalResolution?
}
```

#### ArtifactBlock

```swift
public struct ArtifactBlock: Hashable, Codable, Sendable {
    public var id: AgentArtifactID
    public var title: String
    public var mediaType: String?
    public var reference: AgentResourceReference
    public var summary: String?
}
```

#### CustomBlock

```swift
public struct CustomBlock: Hashable, Codable, Sendable {
    public var kind: String
    public var payload: JSONValue
    public var fallbackTitle: String
    public var fallbackSummary: String?
}
```

---

## 7. Runtime Adapter SPI

### 7.1 目标

不得要求现有 Agent Loop 修改内部实现。接入方只需写 Adapter：

```text
现有 Agent Runtime 原生事件
→ Runtime Adapter
→ AgentRuntimeEvent
→ AgentConversationReducer
→ AgentChatUIKit
```

### 7.2 Adapter

```swift
public protocol AgentRuntimeAdapter: Sendable {
    func connect(
        configuration: AgentRuntimeConfiguration
    ) async throws -> any AgentRuntimeConnection
}
```

### 7.3 Connection

```swift
public protocol AgentRuntimeConnection: Sendable {
    var capabilities: AgentRuntimeCapabilities { get }

    func makeEventStream()
        -> AsyncThrowingStream<AgentRuntimeEvent, Error>

    func send(_ command: AgentRuntimeCommand) async throws

    func close() async
}
```

约束：

- `makeEventStream()` 每个连接只允许消费一次；
- `close()` 必须幂等；
- 连接释放时必须取消底层任务；
- Adapter 不得持有 UIViewController；
- Runtime 线程不得直接更新 UIKit。

### 7.4 Capabilities

```swift
public struct AgentRuntimeCapabilities:
    OptionSet,
    Codable,
    Sendable
{
    public let rawValue: UInt64

    public static let streamingText
    public static let tools
    public static let commands
    public static let fileOperations
    public static let diffs
    public static let approvals
    public static let attachments
    public static let history
    public static let retry
    public static let interrupt
    public static let customBlocks
}
```

UI 必须依据 capabilities 隐藏或禁用不支持的入口。

### 7.5 Runtime Command

```swift
public enum AgentRuntimeCommand: Hashable, Codable, Sendable {
    case createConversation(CreateConversationRequest)
    case resumeConversation(AgentConversationID)
    case submit(AgentSubmitRequest)
    case interrupt(AgentInterruptRequest)
    case retry(AgentRetryRequest)
    case approve(AgentApprovalResponse)
    case reject(AgentApprovalResponse)
    case answer(AgentStructuredAnswer)
    case loadEarlier(AgentHistoryRequest)
    case requestSnapshot(AgentConversationID)
    case custom(CustomRuntimeCommand)
}
```

### 7.6 Input

```swift
public struct AgentSubmitRequest: Hashable, Codable, Sendable {
    public var conversationID: AgentConversationID
    public var text: String
    public var attachments: [AgentAttachment]
    public var metadata: [String: JSONValue]
}
```

### 7.7 Runtime Event Envelope

所有 Adapter 都必须为内部前端事件生成稳定 Envelope：

```swift
public struct AgentRuntimeEvent:
    Hashable,
    Codable,
    Sendable
{
    public var id: AgentEventID
    public var sequence: Int64
    public var conversationID: AgentConversationID
    public var timestamp: Date
    public var payload: AgentRuntimeEventPayload
}
```

要求：

- `id` 在一次会话生命周期中唯一；
- `sequence` 在同一连接中单调递增；
- 原 Runtime 没有 sequence 时，由 Adapter 合成；
- 重连后的 Snapshot 可以重新建立基线；
- 不允许用到达 UI 的时间代替 Runtime 事件时间。

### 7.8 Event Payload

```swift
public enum AgentRuntimeEventPayload:
    Hashable,
    Codable,
    Sendable
{
    case snapshot(AgentConversationSnapshot)
    case conversationStateChanged(AgentConversationState)

    case turnInserted(AgentTurn)
    case turnUpdated(AgentTurn)
    case turnRemoved(AgentTurnID)

    case blockInserted(turnID: AgentTurnID, block: AgentBlock)
    case blockReplaced(turnID: AgentTurnID, block: AgentBlock)
    case blockDelta(AgentBlockDelta)
    case blockRemoved(turnID: AgentTurnID, blockID: AgentBlockID)

    case approvalRequested(turnID: AgentTurnID, block: AgentBlock)
    case approvalResolved(AgentApprovalResolution)

    case historyPage(AgentHistoryPage)
    case recoverableError(AgentRuntimeNotice)
    case terminalError(AgentFailure)
}
```

### 7.9 Block Delta

```swift
public struct AgentBlockDelta:
    Hashable,
    Codable,
    Sendable
{
    public var turnID: AgentTurnID
    public var blockID: AgentBlockID
    public var baseRevision: Int64?
    public var nextRevision: Int64
    public var operation: AgentBlockDeltaOperation
}

public enum AgentBlockDeltaOperation:
    Hashable,
    Codable,
    Sendable
{
    case appendMarkdown(String)
    case appendCommandOutput(String)
    case replaceContent(AgentBlockContent)
    case setState(AgentBlockState)
    case setProgress(Double?)
    case mergeMetadata([String: JSONValue])
}
```

---

## 8. AgentChatSession、Reducer 与 Store

### 8.1 分层

```text
AgentRuntimeConnection
        │
        ▼
AgentConversationReducer actor
├── 去重
├── 排序
├── 乱序缓存
├── revision 校验
├── Delta 合并
├── Snapshot 恢复
└── 生成 Presentation Patch
        │
        ▼
AgentConversationStore @MainActor
├── 当前 Snapshot
├── 发布 UI Patch
└── 驱动 ViewController
```

### 8.2 Reducer

```swift
public actor AgentConversationReducer {
    public init(configuration: AgentReducerConfiguration)

    public func consume(
        _ event: AgentRuntimeEvent
    ) async -> AgentReductionResult

    public func replaceSnapshot(
        _ snapshot: AgentConversationSnapshot
    ) async -> AgentReductionResult
}
```

### 8.3 必须实现的归并规则

1. 按 `event.id` 去重；
2. 缓存最近至少 4096 个 event ID，使用有界 LRU；
3. 按 `sequence` 处理事件；
4. 最多缓存 512 个乱序事件；
5. sequence 缺口超过配置时间后请求 Snapshot；
6. 旧 `revision` 不得覆盖新 Block；
7. Delta 类型与 Block 类型不匹配时：
   - 保持已有状态；
   - 发出可恢复 Notice；
   - 不崩溃；
8. 已完成或已取消的 Approval 不得再次响应；
9. 删除不存在的 Block 是幂等 no-op；
10. Snapshot 到达时必须清理不再有效的乱序缓存；
11. Reducer 必须完全确定性：相同初始状态 + 相同事件序列 = 相同结果。

### 8.4 Store

```swift
@MainActor
public final class AgentConversationStore {
    public private(set) var snapshot: AgentConversationSnapshot

    public func makePatchStream()
        -> AsyncStream<AgentPresentationPatch>

    public func apply(
        _ result: AgentReductionResult
    )
}
```

不得把 `UICollectionViewDiffableDataSource` 放入 Core Store。

### 8.5 AgentChatSession

提供高层协调器：

```swift
public actor AgentChatSession {
    public init(
        adapter: any AgentRuntimeAdapter,
        configuration: AgentRuntimeConfiguration,
        reducerConfiguration: AgentReducerConfiguration
    )

    public func start() async throws
    public func send(_ command: AgentRuntimeCommand) async throws
    public func stop() async
}
```

要求：

- 管理连接生命周期；
- 消费事件流；
- 将 Reduction Result 投递给 MainActor Store；
- 网络断开不丢失当前 UI Snapshot；
- 支持取消；
- 不强引用 ViewController；
- 不在 Session 中实现业务导航。

---

## 9. UIKit 会话页面

### 9.1 主控制器

```swift
@MainActor
public final class AgentConversationViewController: UIViewController {
    public init(
        store: AgentConversationStore,
        configuration: AgentConversationConfiguration = .init(),
        theme: AgentChatTheme = .system,
        rendererRegistry: AgentBlockRendererRegistry = .default
    )

    public weak var delegate:
        (any AgentConversationViewControllerDelegate)?

    public var actionHandler: AgentActionHandler?
}
```

### 9.2 层级

```text
AgentConversationViewController
├── UICollectionView
│   └── CollectionViewChatLayout
├── JumpToLatestButton
├── ConnectionBanner
└── ComposerContainer
    └── AgentComposerView
```

### 9.3 UICollectionView 结构

```text
SectionIdentifier = AgentTurnID
ItemIdentifier = AgentBlockID
```

一个 Turn 一个 Section，一个 Block 一个 Item。

Assistant Header、时间、状态等使用 Supplementary View，不创建伪 Block。

### 9.4 ChatLayout

- 使用 `CollectionViewChatLayout`；
- 仅作为私有实现；
- 不向接入方公开；
- Cell 使用 Auto Layout 自适应高度；
- 为常见 Block 提供估算高度；
- 使用 ChatLayout 的位置保持能力；
- 所有布局更新通过稳定 ID 和 Patch 驱动。

### 9.5 Diffable Data Source

必须使用：

```swift
UICollectionViewDiffableDataSource<
    AgentTurnID,
    AgentBlockID
>
```

更新规则：

- 新 Turn：插入 Section；
- 新 Block：插入 Item；
- 流式 Delta：`reconfigureItems([blockID])`；
- 状态变化：只 reconfigure 目标 Block；
- 删除：按稳定 ID 删除；
- 历史分页：在顶部 prepend Sections；
- 禁止 token 级完整 Snapshot apply；
- 禁止流式阶段 `reloadData()`。

### 9.6 UI 更新合并

Store 可以高频更新，UIKit 层必须做合并：

- 同一显示帧最多提交一次可见 UI 更新；
- 低频状态事件可立即更新；
- 连续文字 Delta 合并后刷新目标 Block；
- Background 时暂停动画；
- 回到 Foreground 后以最新 Snapshot 校准。

可以使用：

- `CADisplayLink`；
- MainActor coalescer；
- 或等价的帧级调度器。

### 9.7 滚动规则

必须区分三种状态：

```text
followingLatest
readingHistory
programmaticNavigation
```

规则：

1. 用户距底部不超过 80pt，视为 following；
2. 用户主动向上拖动后进入 readingHistory；
3. readingHistory 时新内容不得强制拉回底部；
4. readingHistory 收到新内容时显示“回到最新”按钮；
5. 点击按钮滚到最新并恢复 following；
6. prepend 历史时保持顶部可见 Block ID 和相对偏移；
7. Block 展开、收起和流式变高时保持阅读锚点；
8. 键盘出现与消失时保持当前语义位置；
9. 旋转和窗口尺寸变化时按 Block ID 恢复位置；
10. 不依赖 IndexPath 作为长期锚点。

### 9.8 宽度与对齐

默认：

- User Block：trailing，最大宽度 78%；
- Assistant Markdown：full width；
- Tool / Command / Diff / Approval：full width；
- iPhone 页面水平安全间距：16pt；
- iPad 内容列居中，默认最大宽度 900pt，可配置；
- 代码块、表格可以横向滚动；
- 整个会话不允许横向滚动。

### 9.9 Cell 复用

每个 Renderer 必须正确处理：

- 重用前取消异步任务；
- 图片请求取消；
- Markdown parse task 取消；
- 状态重置；
- Accessibility 重建；
- Theme 变化；
- Dynamic Type 变化。

不得在 Cell 中保留 Runtime Connection。

---

## 10. Renderer Registry

### 10.1 目的

AgentChatKit 不可能预知所有企业 Tool。必须支持宿主注册 Renderer。

### 10.2 Renderer 接口

```swift
@MainActor
public protocol AgentBlockRenderer: AnyObject {
    var supportedKinds: Set<AgentBlockKind> { get }

    func register(in collectionView: UICollectionView)

    func dequeueConfiguredCell(
        from collectionView: UICollectionView,
        at indexPath: IndexPath,
        context: AgentBlockRenderContext
    ) -> UICollectionViewCell
}
```

### 10.3 Render Context

```swift
@MainActor
public struct AgentBlockRenderContext {
    public let conversationID: AgentConversationID
    public let turn: AgentTurn
    public let block: AgentBlock
    public let availableWidth: CGFloat
    public let theme: AgentChatTheme
    public let environment: AgentRenderEnvironment
    public let actionSink: AgentBlockActionSink
}
```

### 10.4 Registry

```swift
@MainActor
public final class AgentBlockRendererRegistry {
    public static var `default`: AgentBlockRendererRegistry { get }

    public func register(
        _ renderer: any AgentBlockRenderer
    )

    public func renderer(
        for kind: AgentBlockKind
    ) -> any AgentBlockRenderer
}
```

### 10.5 回退

未知 kind 必须使用 `GenericToolBlockRenderer`，显示：

- fallback title；
- summary；
- running / success / failure 状态；
- 可折叠 input / output；
- custom kind 字符串；
- Copy Raw Payload。

未知 Block 不得显示空白，不得崩溃。

### 10.6 Renderer 动作

Renderer 不直接调用 Runtime。

```swift
public enum AgentBlockUIAction: Hashable, Sendable {
    case toggleExpanded(AgentBlockID)
    case copy(AgentBlockID)
    case openArtifact(AgentArtifactID)
    case openFile(AgentResourceReference)
    case openLink(URL)
    case retry(AgentBlockID)
    case approve(AgentApprovalResponse)
    case reject(AgentApprovalResponse)
    case custom(kind: String, payload: JSONValue)
}
```

动作先进入统一 Action Router，再决定：

- 转为 Runtime Command；
- 交给宿主 Delegate；
- 只修改本地 UI 展开状态。

---

## 11. Markdown 渲染

### 11.1 总体路线

```text
Markdown String
→ swift-markdown AST
→ AgentMarkdownRenderDocument
→ UIKit Block Views
```

不得把 `swift-markdown` 的 AST 类型直接暴露到 public API。

### 11.2 Render Document

定义平台无关、不可变、可缓存的 Render Tree：

```swift
public struct AgentMarkdownRenderDocument:
    Hashable,
    Sendable
{
    public var blocks: [AgentMarkdownRenderBlock]
}
```

Block 至少支持：

- paragraph；
- heading；
- block quote；
- ordered list；
- unordered list；
- task list；
- thematic break；
- code block；
- table；
- image；
- unsupported / fallback。

Inline 至少支持：

- text；
- emphasis；
- strong；
- strikethrough；
- inline code；
- link；
- soft break；
- hard break。

### 11.3 解析线程

- Markdown 解析不得阻塞主线程；
- 在专用 actor 或后台 Task 中解析；
- 转换为自有 `Sendable` Render Document；
- MainActor 只创建和更新 UIKit View；
- Cell 重用时取消过期 parse；
- 只应用最新 revision 的结果。

### 11.4 流式 Markdown

流式文本可能暂时不完整，例如未闭合代码围栏或列表。

必须做到：

- 不崩溃；
- 40～80ms 范围内 debounce 解析，可配置；
- 解析失败时回退为可选择的纯文本；
- 完成事件到达时立即做最终解析；
- Markdown Cache Key 包含 blockID、revision、宽度、Content Size Category 和 Theme Version；
- 不因每个 token 重建整个会话。

### 11.5 文本选择

普通 Markdown 文字使用支持选择的 TextKit / `UITextView` 方案：

- `isEditable = false`；
- `isScrollEnabled = false`；
- 支持选择、复制、链接；
- 禁止把整篇内容用 UILabel 拼接；
- 与 VoiceOver 阅读顺序一致。

### 11.6 代码块

必须包含：

- 等宽字体；
- 语言标签；
- Copy；
- 横向滚动；
- Light / Dark；
- Dynamic Type；
- 超长代码折叠；
- “展开”或“打开完整内容”动作；
- 不让代码块触发整个页面横向滚动。

v1 内置 `PlainCodeHighlighter`，保证所有语言稳定显示。另提供：

```swift
public protocol AgentCodeHighlighting: Sendable {
    func highlight(
        code: String,
        language: String?,
        theme: AgentCodeTheme
    ) async throws -> AgentHighlightedCode
}
```

语法着色 Provider 可由宿主或后续扩展包注入，不能成为主渲染稳定性的前置条件。

### 11.7 表格

- 独立横向滚动；
- header 样式；
- 单元格文本可选择；
- 不嵌套垂直滚动；
- 超宽表格不撑破页面；
- 支持 VoiceOver 按行列描述；
- 流式期间可安全重建。

### 11.8 图片

Core 只保存资源引用，不执行网络请求。

```swift
public protocol AgentImageProviding: Sendable {
    func image(
        for reference: AgentResourceReference,
        targetSize: CGSize,
        scale: CGFloat
    ) async throws -> UIImage
}
```

UIKit 层负责：

- 占位图；
- 取消；
- 缓存接入；
- 错误回退；
- 点击交给宿主；
- Cell 重用安全。

### 11.9 HTML

v1 不支持原始 HTML 执行。

- HTML 节点以纯文本或 Unsupported Block 显示；
- 不加载脚本；
- 不创建 WebView；
- 不允许 HTML 触发网络资源。

---

## 12. 内置 Block UI

### 12.1 UserText

- trailing；
- 支持纯文本和附件摘要；
- 文本可选择；
- 不使用传统夸张聊天气泡；
- 可配置背景、圆角、最大宽度；
- 长按 Copy。

### 12.2 Markdown

- 无气泡或轻量容器；
- 适合长文；
- 内联 Code、列表、表格、代码块；
- 流式光标可选；
- 完成后移除流式状态。

### 12.3 Activity

- 小型、弱化样式；
- 显示可公开的执行摘要；
- running 时可展示进度；
- 不命名为“思维链”；
- 不默认展开原始模型 reasoning。

### 12.4 Generic Tool

状态：

```text
queued
running
waitingForApproval
succeeded
failed
cancelled
```

包含：

- 图标；
- 标题；
- summary；
- 状态；
- input/output 折叠；
- retry；
- Copy Raw；
- 未知 Tool fallback。

### 12.5 Command

包含：

- command；
- working directory；
- running indicator；
- output；
- exit code；
- duration；
- success / failure；
- Copy Command；
- Copy Output；
- 折叠与展开。

输出要求：

- 支持增量追加；
- 过滤危险 ANSI 控制序列；
- 可以支持安全的 SGR 颜色；
- 必须删除 OSC、终端标题、控制字符和不可见注入；
- 内联输出达到阈值后截断；
- 默认建议上限：200KB 或 2,000 行；
- 超出部分显示摘要和“打开完整输出”动作；
- 完整内容由 Artifact 或宿主提供。

### 12.6 File Search

包含：

- query；
- root；
- running 状态；
- 匹配数量；
- 前若干项结果；
- 点击文件交给宿主；
- 不自行读取文件。

### 12.7 File Operation

包含：

- read/create/update/delete/move；
- path；
- destination；
- summary；
- success/failure；
- 点击文件交给宿主。

### 12.8 Diff

时间线内显示：

- 变更文件数量；
- additions/deletions；
- 每个文件概要；
- 部分 Unified Diff；
- 展开/收起；
- Open Full Diff。

必须实现 Unified Diff Parser，支持：

- 多文件；
- hunk；
- context/add/delete 行；
- 文件重命名；
- 二进制文件提示；
- 无换行标记；
- 解析失败时纯文本回退。

默认内联上限建议：

- 1,000 行或 150KB；
- 超过上限显示摘要；
- 完整 Diff 通过宿主页面打开。

### 12.9 Approval

包含：

- title；
- message；
- risk；
- choice；
- approve/reject；
- waiting；
- resolved；
- failed。

规则：

- 一次性响应；
- 点击后立即禁用全部按钮；
- Runtime 成功确认后显示最终状态；
- 失败时允许显式重试；
- 高风险操作使用明显但不恐吓的样式；
- VoiceOver 清楚朗读风险与选项。

### 12.10 Artifact

包含：

- title；
- media type；
- summary；
- Open；
- Share 由宿主决定；
- 不自动下载；
- 不自动打开外部 URL。

### 12.11 Error

区分：

- Block 局部错误；
- Turn 错误；
- Connection 可恢复错误；
- Runtime 终止错误。

错误 UI 应提供适用的 Retry / Reconnect，不把底层堆栈直接展示给普通用户。

---

## 13. Composer 与键盘

### 13.1 默认 Composer

```text
AgentComposerView
├── AttachmentButton
├── UITextView
├── OptionalCommandButton
└── SendOrStopButton
```

能力：

- 多行输入；
- 占位文案；
- 草稿；
- Send；
- Stop；
- 附件摘要；
- 空内容不发送；
- 运行时 Send 切换为 Stop；
- 最大高度默认 180pt；
- Dynamic Type；
- VoiceOver；
- Light / Dark。

### 13.2 Composer 可替换

```swift
@MainActor
public protocol AgentComposerProviding: AnyObject {
    var view: UIView { get }
    var actionStream: AsyncStream<AgentComposerAction> { get }
    func apply(_ state: AgentComposerState)
}
```

宿主可完全替换输入区。

### 13.3 附件

组件不直接假设附件来源。

```swift
@MainActor
public protocol AgentAttachmentPicking: AnyObject {
    func pickAttachments(
        from sourceView: UIView
    ) async throws -> [AgentAttachment]
}
```

默认 Demo 可提供 Document Picker 实现；Core 不保存安全作用域权限。

### 13.4 键盘

使用 `keyboardLayoutGuide` 与 Composer 底部布局协调。

要求：

- interactive keyboard dismissal；
- iPad 浮动键盘；
- 外接键盘；
- 旋转；
- Split View；
- Scene Resize；
- 键盘出现时保持阅读锚点；
- 不通过全局 Notification 硬编码固定键盘高度。

### 13.5 外接键盘

iPad 默认快捷键：

- `⌘ Return`：发送；
- `Escape`：停止当前运行，前提是 Runtime 支持 interrupt；
- `⌘ Shift K`：聚焦 Composer，可配置；
- 上下方向键不得破坏 UITextView 正常编辑。

所有快捷键通过 `UIKeyCommand` 提供，并可由配置关闭。

---

## 14. iPad 必须作为一等平台

v1.0 的 iPad 适配不是“iPhone 页面放大”。

必须支持：

- Portrait / Landscape；
- Split View；
- Slide Over；
- Stage Manager；
- 连续窗口 Resize；
- 外接键盘；
- Pointer；
- Context Menu；
- 文件拖入；
- 多 Scene；
- Popover 锚点；
- Regular / Compact Size Class 切换；
- 最大内容宽度；
- 大尺寸 Diff 和 Command Output。

### 14.1 多 Scene

禁止：

- 全局单例 Conversation Store；
- 全局单例 Runtime Connection；
- 通过 `UIApplication.shared.windows` 找窗口；
- 假设只有一个 Scene。

每个 Scene 可拥有独立 Session、Store 和 ViewController。

### 14.2 Pointer 与 Context Menu

以下元素提供 Pointer / Context Menu：

- Copy；
- Open File；
- Open Artifact；
- Retry；
- Expand；
- Approval 选项；
- Jump to Latest。

### 14.3 Drag & Drop

默认 Composer 支持宿主注入的拖放附件处理：

- 文件；
- 图片；
- 文本；
- URL。

组件只产生 Attachment，不自行上传。

---

## 15. Theme、无障碍与国际化

### 15.1 Theme

```swift
@MainActor
public struct AgentChatTheme {
    public var colors: AgentChatColors
    public var typography: AgentChatTypography
    public var metrics: AgentChatMetrics
    public var icons: AgentChatIcons
    public var version: Int
}
```

要求：

- 使用语义颜色；
- 默认 `.system`；
- Light / Dark；
- High Contrast；
- Theme 变化时刷新可见 Cell；
- Theme Version 纳入 Markdown / Height Cache Key；
- 不在 Core 中出现 UIColor。

### 15.2 Dynamic Type

所有文字必须使用：

- `UIFontMetrics`；
- Text Style；
- 可配置最大缩放策略；
- 不硬编码不可缩放字号。

必须测试超大辅助字号，按钮不能被截断。

### 15.3 VoiceOver

必须保证：

- Turn 与 Block 阅读顺序正确；
- Tool 状态可朗读；
- Command 成功/失败可朗读；
- Approval 风险和选项可朗读；
- Jump to Latest 有未读数量描述；
- 流式更新不逐 token 打断 VoiceOver；
- 完成时可使用节制的 Accessibility Announcement；
- 展开/收起状态可读。

### 15.4 Reduce Motion

开启 Reduce Motion 时：

- 关闭大幅插入动画；
- 状态变化使用淡入淡出或无动画；
- Jump to Latest 可立即定位；
- 不使用持续旋转之外的装饰动画。

### 15.5 国际化

v1 内置：

- English；
- 简体中文。

要求：

- 所有字符串进入 String Catalog；
- 使用 leading/trailing；
- 不硬编码 left/right；
- 基础 RTL 布局不崩溃；
- 日期与数字使用 Locale；
- Runtime 原始内容不擅自翻译。

---

## 16. 性能与内存

### 16.1 强制要求

- 不按 token `reloadData()`；
- 不按 token完整 apply Snapshot；
- Markdown 后台解析；
- 可见 Cell 才创建 UIKit 视图；
- 使用稳定 ID；
- Cell 异步任务可取消；
- 高度与 Render Document 有界缓存；
- Memory Warning 清理非必要缓存；
- Command Output 分块存储；
- 超长内容截断或按需展开；
- 不在主线程解析大型 Diff。

### 16.2 Cache

至少包含：

1. Markdown Render Document Cache；
2. Markdown Height Cache；
3. Diff Parse Cache；
4. Image Cache 接口，不强制内置网络缓存。

所有 Cache 必须：

- 有容量上限；
- 支持按 Conversation 清理；
- 支持 Theme / Dynamic Type 失效；
- 收到 Memory Warning 后释放；
- 不永久持有 Cell 或 UIView。

### 16.3 性能场景

发布前至少运行：

#### 场景 A：长会话

- 2,000 Turns；
- 6,000 Blocks；
- 混合 Markdown、Tool、Command、Diff；
- 快速滚动无崩溃；
- Cell 复用正确；
- 不出现明显位置跳动。

#### 场景 B：持续流式

- 20～30 Delta/秒；
- 连续 10 分钟；
- 只更新目标 Block；
- UI 更新频率不超过屏幕刷新频率；
- 用户向上阅读时不被拉回底部。

#### 场景 C：命令输出

- 1MB 原始输出；
- 内联截断；
- 主列表保持流畅；
- 完整输出通过 Artifact / Host Action 打开。

#### 场景 D：大型 Diff

- 5,000 行；
- 时间线只展示摘要与有限内容；
- 后台解析；
- Open Full Diff 可用；
- 不阻塞主线程。

#### 场景 E：iPad Resize

- Stage Manager 连续改变宽度；
- 保持 Block 锚点；
- Markdown、Table、Code 重新布局正确；
- Composer 不跳动。

### 16.4 Instruments 验收目标

在 Release 构建和参考设备上记录：

- 流式更新 Main Thread p95 小于 8ms；
- 连续滚动无长期主线程阻塞；
- 无明显 retain cycle；
- 长场景结束后缓存可释放；
- 6,000 Block 场景新增内存目标控制在 120MB 内。

如设备差异导致目标无法稳定自动化，必须在 `Documentation/Performance.md` 记录设备、系统、构建模式和实测结果。

---

## 17. 安全与隐私

### 17.1 默认不记录内容

默认 Logger 不得输出：

- 用户输入全文；
- Command Output；
- 文件内容；
- Diff 全文；
- Approval 敏感参数；
- Attachment 本地路径；
- Token 或密钥。

### 17.2 Logger

```swift
public protocol AgentChatLogging: Sendable {
    func log(_ event: AgentChatLogEvent)
}
```

默认 No-op Logger。调试 Logger 只记录结构化元信息和长度，不记录 payload。

### 17.3 URL

所有 URL 通过宿主 Delegate 决定是否打开。

默认允许候选：

- `https`
- `http`
- `mailto`

以下不得自动打开：

- `file`
- 自定义 scheme
- `javascript`
- `data`

### 17.4 Command Output

- 当纯文本；
- 过滤控制字符；
- 不执行链接；
- 不解析 HTML；
- ANSI 仅允许白名单 SGR；
- 删除 OSC 等控制序列。

### 17.5 Approval

- ID 唯一；
- 响应幂等；
- 防重复点击；
- UI 先进入 resolving；
- Runtime 确认后进入 resolved；
- 失败可重试；
- 不在本地假设审批一定成功。

### 17.6 Telemetry

v1 不内置分析、埋点、崩溃上报或网络请求。

---

## 18. 测试要求

### 18.1 Core Tests

覆盖：

- ID；
- Codable round-trip；
- JSONValue；
- Snapshot；
- Event 去重；
- sequence 排序；
- 乱序缓存；
- sequence gap；
- Snapshot 恢复；
- revision 冲突；
- Delta 合并；
- Block 删除幂等；
- Approval 一次性；
- Cancel；
- Retry；
- History prepend；
- 未知 Custom Block；
- Reducer 确定性。

### 18.2 Markdown Tests

覆盖：

- heading；
- emphasis；
- list；
- task list；
- quote；
- link；
- inline code；
- fenced code；
- table；
- image；
- 不完整 Markdown；
- 未闭合 code fence；
- 超长内容；
- HTML fallback；
- Unicode；
- CJK；
- Emoji；
- RTL 基础；
- Cache 失效；
- 取消旧 parse task。

使用 Golden Fixture 保存输入和 Render Document。

### 18.3 UIKit Tests

覆盖：

- Section / Item 映射；
- Cell reuse；
- Renderer fallback；
- Reconfigure；
- Insert / Delete；
- 展开收起；
- Bottom following；
- Reading history；
- Jump to latest；
- prepend anchor；
- keyboard；
- rotation；
- iPad resize；
- Dynamic Type；
- Theme；
- Reduce Motion；
- Accessibility label；
- Context Menu；
- 外接键盘命令。

### 18.4 Integration Tests

使用 `MockAgentRuntime` 真实走：

```text
Adapter
→ Connection
→ Event Stream
→ Session
→ Reducer
→ Store
→ ViewController
```

场景：

1. 正常流式回复；
2. Tool 成功；
3. Command 实时输出；
4. File Search；
5. Diff；
6. Approval 允许；
7. Approval 拒绝；
8. Runtime 断开与恢复；
9. 停止；
10. 重试；
11. 历史分页；
12. Custom Renderer。

### 18.5 Snapshot Tests

至少覆盖：

- iPhone light/dark；
- iPad light/dark；
- User；
- Markdown；
- Code；
- Table；
- Tool 各状态；
- Command；
- Diff；
- Approval；
- Error；
- Extra Large Dynamic Type；
- 中文与英文。

### 18.6 UI Tests

AgentChatDemo 使用 XCUITest 验证：

- 输入发送；
- 流式出现；
- 上滑后不自动回底；
- Jump to Latest；
- Tool 展开；
- Approval；
- Stop；
- Retry；
- Attachment；
- iPad 横竖屏；
- 外接键盘命令。

### 18.7 并发与泄漏

- 开启 Thread Sanitizer 的专用 CI Job；
- 反复创建/销毁 100 次 Session；
- ViewController dismiss 后无 Session 强引用；
- Cell 异步任务全部取消；
- Connection close 幂等。

---

## 19. AgentChatTesting

公开测试辅助模块：

```swift
public actor MockAgentRuntime:
    AgentRuntimeAdapter
```

能力：

- 脚本化事件；
- token 速度；
- 乱序；
- 重复事件；
- 中断；
- 断线；
- Approval；
- 失败；
- history；
- Custom Block。

示例：

```swift
let scenario = AgentScenario {
    Turn.user("修复项目中的失败测试")
    Turn.assistant {
        Markdown.stream("我先检查项目结构。")
        FileSearch.running(query: "Package.swift")
        FileSearch.succeeded(matches: [...])
        Command.running("swift test")
        Command.output("Building...\n")
        Command.failed(exitCode: 1)
        Approval.request(...)
        Diff.succeeded(...)
        Markdown.stream("已完成修改。")
    }
}
```

这套 DSL 必须用于 Demo 和集成测试，避免两套行为不一致。

---

## 20. Demo App

Demo 不是装饰项目，而是 v1.0 验收载体。

### 20.1 页面

```text
Scenario List
→ Agent Conversation
→ Theme / Runtime Controls
```

### 20.2 必须包含的场景

- Basic Streaming；
- Markdown Showcase；
- File Search；
- Shell Command；
- Long Command Output；
- File Changes；
- Unified Diff；
- Approval；
- Failure and Retry；
- Interrupt；
- Offline and Reconnect；
- History Pagination；
- Unknown Tool Fallback；
- Custom Renderer；
- Long Conversation；
- iPad Stage Manager；
- Accessibility；
- Chinese Content。

### 20.3 Custom Renderer 示例

提供至少一个不在 Core 的 Tool：

```text
demo.weather
```

或：

```text
demo.calendar.event
```

展示接入方如何注册自定义 Renderer，证明无需修改 AgentChatKit Core。

### 20.4 Demo 不得包含

- 真实 API Key；
- 真实模型请求；
- Shell 执行；
- 私有文件读取；
- 远程服务器依赖。

Demo 下载后离线即可完整运行。

---

## 21. 公共使用示例

### 21.1 最小接入

```swift
import AgentChatKit

let adapter = MyAgentRuntimeAdapter(...)

let store = AgentConversationStore(
    snapshot: .empty(conversationID: "demo")
)

let session = AgentChatSession(
    adapter: adapter,
    configuration: .init(),
    reducerConfiguration: .init(),
    store: store
)

let controller = AgentConversationViewController(
    store: store
)

controller.actionHandler = { action in
    switch action {
    case .runtime(let command):
        try await session.send(command)

    case .host(let hostAction):
        await appRouter.handle(hostAction)
    }
}

Task {
    try await session.start()
}
```

### 21.2 自定义 Tool Renderer

```swift
let registry = AgentBlockRendererRegistry.default

registry.register(
    CalendarEventBlockRenderer(
        supportedKinds: ["company.calendar.event"]
    )
)

let controller = AgentConversationViewController(
    store: store,
    rendererRegistry: registry
)
```

### 21.3 现有自研 Loop Adapter

```swift
final class MyLoopAdapter: AgentRuntimeAdapter {
    private let loop: MyAgentLoop

    init(loop: MyAgentLoop) {
        self.loop = loop
    }

    func connect(
        configuration: AgentRuntimeConfiguration
    ) async throws -> any AgentRuntimeConnection {
        MyLoopConnection(loop: loop)
    }
}
```

Adapter 负责：

```text
MyLoopEvent.token
→ blockDelta.appendMarkdown

MyLoopEvent.toolStarted
→ blockInserted(tool)

MyLoopEvent.shellOutput
→ blockDelta.appendCommandOutput

MyLoopEvent.approval
→ approvalRequested

MyLoopEvent.completed
→ turnUpdated(completed)
```

Agent Loop 本身无需改造成 AgentChatKit 内部实现。

---

## 22. CI 与工程质量

### 22.1 GitHub Actions

至少包含：

1. Package build；
2. Core tests；
3. Markdown tests；
4. UIKit simulator tests；
5. Integration tests；
6. Snapshot tests；
7. iPhone UI tests；
8. iPad UI tests；
9. Thread Sanitizer；
10. DocC build；
11. 格式检查；
12. Release build。

### 22.2 构建矩阵

- 最低支持系统：iOS 17 Simulator；
- 当前最新稳定 iOS Simulator；
- iPhone；
- iPad；
- Debug；
- Release。

### 22.3 格式

采用 `swift-format`，提交配置文件。

要求：

- CI strict；
- public DocC；
- 无编译 Warning；
- 无未说明 TODO；
- 无死代码；
- 无不必要 `@unchecked Sendable`。

### 22.4 API 稳定

v1.0 后遵循 Semantic Versioning：

- Patch：Bugfix；
- Minor：向后兼容能力；
- Major：破坏性 API。

Release 前保存 public API baseline，后续 CI 检测破坏性变化。

---

## 23. 分阶段研发计划

### Phase 0：仓库与基线

交付：

- Package；
- Targets；
- Demo 工程；
- CI；
- License；
- README 骨架；
- Implementation Status；
- 依赖锁定。

验收：

- 所有 Target 空骨架可编译；
- Demo 启动；
- CI 绿色。

### Phase 1：Core Models 与 Runtime SPI

交付：

- IDs；
- JSONValue；
- Snapshot；
- Turn；
- Block；
- 内置 Block；
- Adapter；
- Connection；
- Command；
- Event；
- Codable Fixtures。

验收：

- Core 无 UIKit；
- Codable round-trip；
- strict concurrency 通过；
- 单元测试通过。

### Phase 2：Reducer、Store 与 Session

交付：

- Reducer actor；
- 去重；
- 排序；
- 乱序；
- revision；
- Delta；
- Snapshot 恢复；
- Store；
- Session；
- Mock Runtime。

验收：

- 事件回放完全确定；
- 断线恢复；
- 并发测试；
- 无 data race。

### Phase 3：UICollectionView Timeline

交付：

- ViewController；
- ChatLayout；
- Diffable Data Source；
- Turn Section；
- Block Item；
- Generic Cells；
- Patch；
- Scroll Controller；
- Jump to Latest。

验收：

- 插入、更新、删除；
- 流式不 reloadData；
- 历史 prepend 不跳；
- 长列表可滚动。

### Phase 4：Markdown

交付：

- Parser；
- Render Document；
- Selectable Text；
- Lists；
- Quote；
- Code；
- Table；
- Link；
- Image Provider；
- Cache；
- 流式容错。

验收：

- Markdown Fixture 全通过；
- 后台解析；
- Cell reuse 取消；
- Light/Dark；
- Dynamic Type。

### Phase 5：Agent Blocks

交付：

- Activity；
- Generic Tool；
- Command；
- File Search；
- File Operation；
- Diff；
- Approval；
- Artifact；
- Error；
- Custom Fallback；
- Renderer Registry。

验收：

- 每种状态有 UI；
- Approval 幂等；
- 大输出截断；
- 大 Diff 摘要；
- Custom Renderer Demo。

### Phase 6：Composer 与键盘

交付：

- Default Composer；
- 可替换协议；
- Send/Stop；
- Attachments；
- Draft；
- keyboardLayoutGuide；
- interactive dismissal；
- 外接键盘命令。

验收：

- iPhone / iPad；
- 浮动键盘；
- 横竖屏；
- Resize；
- 输入不遮挡内容。

### Phase 7：iPad、Theme、无障碍、国际化

交付：

- iPad 内容宽度；
- Stage Manager；
- Pointer；
- Context Menu；
- Drag & Drop；
- Theme；
- VoiceOver；
- Reduce Motion；
- English / zh-Hans。

验收：

- iPad 完整测试矩阵；
- Extra Large Dynamic Type；
- VoiceOver 操作 Approval；
- 无硬编码 left/right。

### Phase 8：性能、文档、RC

交付：

- 性能场景；
- Instruments 报告；
- Snapshot；
- UI Test；
- DocC；
- Integration Guide；
- Custom Block Guide；
- Security；
- Migration；
- Changelog；
- 1.0 RC。

验收：

- 全部 CI 绿色；
- 无占位；
- 无高优先级缺陷；
- v1.0 验收清单全部勾选。

---

## 24. v1.0 验收清单

只有全部完成，才能发布 `1.0.0`。

### 架构

- [ ] Agent Loop 与 UI 完全解耦；
- [ ] Runtime Adapter SPI 稳定；
- [ ] Core 不依赖 UIKit；
- [ ] UIKit 不依赖具体 Runtime；
- [ ] 一 Turn 一 Section；
- [ ] 一 Block 一 Item；
- [ ] Renderer Registry 可扩展；
- [ ] 未知 Tool 安全回退。

### 流式与状态

- [ ] Markdown Delta；
- [ ] Command Output Delta；
- [ ] Tool 生命周期；
- [ ] Approval；
- [ ] Stop；
- [ ] Retry；
- [ ] History；
- [ ] Duplicate Event；
- [ ] Out-of-order Event；
- [ ] Snapshot Recovery；
- [ ] Revision 冲突保护。

### UI

- [ ] User；
- [ ] Markdown；
- [ ] Activity；
- [ ] Generic Tool；
- [ ] Command；
- [ ] File Search；
- [ ] File Operation；
- [ ] Diff；
- [ ] Approval；
- [ ] Artifact；
- [ ] Error；
- [ ] Composer；
- [ ] Jump to Latest；
- [ ] Connection Banner；
- [ ] Custom Renderer。

### Markdown

- [ ] 可选择文本；
- [ ] 标题；
- [ ] 粗体/斜体/删除线；
- [ ] 列表；
- [ ] Task List；
- [ ] Quote；
- [ ] Link；
- [ ] Inline Code；
- [ ] Code Block；
- [ ] Table；
- [ ] Image Provider；
- [ ] 流式不完整语法；
- [ ] Cache；
- [ ] 超长内容策略。

### iPad

- [ ] Portrait；
- [ ] Landscape；
- [ ] Split View；
- [ ] Stage Manager；
- [ ] Resize；
- [ ] 外接键盘；
- [ ] Pointer；
- [ ] Context Menu；
- [ ] Drag & Drop；
- [ ] Multi-scene。

### 系统质量

- [ ] Light/Dark；
- [ ] High Contrast；
- [ ] Dynamic Type；
- [ ] VoiceOver；
- [ ] Reduce Motion；
- [ ] English；
- [ ] zh-Hans；
- [ ] 基础 RTL；
- [ ] Memory Warning；
- [ ] Foreground/Background。

### 工程质量

- [ ] Core Tests；
- [ ] Markdown Tests；
- [ ] UIKit Tests；
- [ ] Integration Tests；
- [ ] Snapshot Tests；
- [ ] UI Tests；
- [ ] Performance Tests；
- [ ] Thread Sanitizer；
- [ ] DocC；
- [ ] README；
- [ ] Architecture；
- [ ] Integration；
- [ ] Runtime Adapter Guide；
- [ ] Custom Blocks Guide；
- [ ] Security；
- [ ] Performance Report；
- [ ] Changelog；
- [ ] License / Notice；
- [ ] CI 全绿；
- [ ] 无未说明 TODO；
- [ ] 无空实现；
- [ ] 无编译 Warning。

---

## 25. macOS 延后，但现在必须保留的边界

v1.0 不实现：

```text
AgentChatAppKit
NSCollectionView
macOS Window / Menu / Toolbar
本地 Codex 进程启动
stdio JSON-RPC
CodexMac Demo
```

但 iOS 研发不得破坏未来复用：

1. `AgentChatCore` 不导入 UIKit；
2. Runtime Adapter SPI 不导入 UIKit；
3. Markdown Parser 输出平台无关 Render Document；
4. Theme 的 Core Token 与 UIKit Theme 分离；
5. Runtime Event 与 UI Cell 无关；
6. 不把 `UIColor`、`UIImage`、`UIView` 放入 Core Model；
7. Resource 使用引用，不存 UIKit 对象；
8. Session 不依赖 UIViewController；
9. 行为测试尽量放在 Core / Integration；
10. 后续 AppKit 只需重新实现展示层，而不是重写 Runtime 与 Reducer。

后续 macOS 路线：

```text
AgentChatCore              复用
AgentChatMarkdown Parser   复用
Runtime Adapter SPI        复用
Reducer / Store            复用
Mock Runtime / Fixtures    复用

AgentChatAppKit            新增
CodexAppServerAdapter      新增
CodexMac Demo              新增
```

---

## 26. 首发 README 建议文案

### 标题

```text
AgentChatKit
```

### 副标题

```text
Production-ready native AI agent conversation UI for iOS and iPadOS.
```

### 能力摘要

```text
Streaming Markdown · Tool Calls · Shell Commands · File Changes
Unified Diffs · Approvals · Artifacts · Custom Runtime Adapters
```

### 核心承诺

```text
Bring your own agent runtime.
AgentChatKit does not implement or constrain your agent loop.
```

---

## 27. 最终完成定义

`AgentChatKit` 的“完成”不是页面像某个 Codex App，而是：

> 任意自研 Agent 产品可以保留自己的 Agent Loop、模型、Tool、权限和传输，只实现一个 Adapter，就能在 iPhone 与 iPad 中获得一套稳定、流畅、可扩展、可测试、可无障碍使用的生产级原生 Agent 会话页面。

当本文 v1.0 验收清单全部完成、CI 全绿、Demo 离线可运行、文档足够让第三方独立接入时，项目才可以发布 `1.0.0`。
