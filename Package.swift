// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SwiftUIIntelligence",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "SwiftUIIntelligence", targets: ["SwiftUIIntelligence"]),
    .library(name: "SwiftUIIntelligenceWeatherDemo", targets: ["SwiftUIIntelligenceWeatherDemo"]),
    .library(name: "SwiftUIIntelligenceFoundationModels", targets: ["SwiftUIIntelligenceFoundationModels"]),
    .executable(name: "SwiftUIIntelligenceModelProbe", targets: ["SwiftUIIntelligenceModelProbe"]),
  ],
  targets: [
    .target(name: "SwiftUIIntelligence"),
    .target(name: "SwiftUIIntelligenceFoundationModels", dependencies: ["SwiftUIIntelligence"]),
    .executableTarget(name: "SwiftUIIntelligenceModelProbe", dependencies: ["SwiftUIIntelligence", "SwiftUIIntelligenceFoundationModels"]),
    .target(name: "SwiftUIIntelligenceWeatherDemo", dependencies: ["SwiftUIIntelligence"]),
    .testTarget(name: "SwiftUIIntelligenceTests", dependencies: ["SwiftUIIntelligence", "SwiftUIIntelligenceWeatherDemo", "SwiftUIIntelligenceFoundationModels"], path: "tests/SwiftUIIntelligenceTests"),
  ]
)
