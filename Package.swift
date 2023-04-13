// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "macosrec",
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.0")
  ],
  targets: [
    .executableTarget(
      name: "macosrec",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources")
  ]
)
