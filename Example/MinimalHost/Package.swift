// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MinimalHost", platforms: [.macOS(.v26), .iOS(.v26)], products: [.library(name: "MinimalHost", targets: ["MinimalHost"])], dependencies: [.package(name: "SwiftUIIntelligence", path: "../..")], targets: [.target(name: "MinimalHost", dependencies: [.product(name: "SwiftUIIntelligence", package: "SwiftUIIntelligence"), .product(name: "SwiftUIIntelligenceFoundationModels", package: "SwiftUIIntelligence")])])
