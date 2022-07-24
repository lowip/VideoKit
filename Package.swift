// swift-tools-version: 5.6

import PackageDescription

let package = Package(
  name: "VideoKit",
  platforms: [.iOS(.v10)],
  products: [
    .library(
      name: "VideoKit",
      targets: ["VideoKit"]
    ),
  ],
  dependencies: [],
  targets: [
    .target(
      name: "VideoKit",
      dependencies: []
    ),
    .testTarget(
      name: "VideoKitTests",
      dependencies: ["VideoKit"]
    ),
  ]
)
