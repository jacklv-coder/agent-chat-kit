// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentChatKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "AgentChatCore", targets: ["AgentChatCore"]),
        .library(name: "AgentChatMarkdown", targets: ["AgentChatMarkdown"]),
        .library(name: "AgentChatUIKit", targets: ["AgentChatUIKit"]),
        .library(name: "AgentChatTesting", targets: ["AgentChatTesting"]),
        .library(name: "AgentChatKit", targets: ["AgentChatKit"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git",
            exact: "0.8.0"
        ),
    ],
    targets: [
        .target(name: "AgentChatCore"),
        .target(
            name: "AgentChatMarkdown",
            dependencies: [
                "AgentChatCore",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(
            name: "AgentChatUIKit",
            dependencies: [
                "AgentChatCore",
                "AgentChatMarkdown",
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "AgentChatTesting",
            dependencies: ["AgentChatCore"]
        ),
        .target(
            name: "AgentChatKit",
            dependencies: ["AgentChatCore", "AgentChatMarkdown", "AgentChatUIKit"]
        ),
        .testTarget(
            name: "AgentChatCoreTests",
            dependencies: ["AgentChatCore"]
        ),
        .testTarget(
            name: "AgentChatMarkdownTests",
            dependencies: ["AgentChatMarkdown"]
        ),
        .testTarget(
            name: "AgentChatUIKitTests",
            dependencies: ["AgentChatUIKit"]
        ),
        .testTarget(
            name: "AgentChatIntegrationTests",
            dependencies: ["AgentChatCore", "AgentChatTesting"]
        ),
        .testTarget(
            name: "AgentChatPerformanceTests",
            dependencies: ["AgentChatCore", "AgentChatMarkdown"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
