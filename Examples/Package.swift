// swift-tools-version: 5.7

import PackageDescription

let package = Package(
  name: "CloudKitBodega",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
  ],
  products: [
    .library(
      name: "CloudKitBodega",
      targets: ["CloudKitBodega"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/mergesort/Bodega", from: "2.0.2"),
  ],
  targets: [
    .target(
      name: "CloudKitBodega",
      dependencies: [
        "Bodega",
      ]
    ),
    .testTarget(
      name: "CloudKitBodegaTests",
      dependencies: ["CloudKitBodega"]
    ),
  ]
)
