// swift-tools-version: 5.9
// F1 Race Control — Rennsimulation & Rennleitung
//
// Bewusst auf Tools-Version 5.9 und Swift-5-Sprachmodus: die Engine soll sowohl
// unter Linux (swift build / swift test) als auch in Xcode auf dem Mac bauen.
import PackageDescription

let package = Package(
    name: "F1RaceControl",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        // Die Rennlogik. Kennt keine UI und hängt nur an Foundation.
        .library(name: "RaceEngine", targets: ["RaceEngine"]),
        .library(name: "RaceServerCore", targets: ["RaceServerCore"]),
        // Rennen im Terminal ansehen — läuft auch dort, wo es kein SwiftUI gibt.
        .executable(name: "f1ctl", targets: ["f1ctl"]),
        // Rennleitungs-Server: ein Rennen, viele Zuschauer, ein Race Director.
        .executable(name: "f1server", targets: ["RaceServer"]),
    ],
    targets: [
        .target(
            name: "RaceEngine",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "f1ctl",
            dependencies: ["RaceEngine"]
        ),
        // Der Server ist eine Bibliothek plus eine dünne Hülle — nur so lässt sich
        // sein Innenleben (WebSocket, SHA-1, Protokoll) überhaupt testen.
        .target(
            name: "RaceServerCore",
            dependencies: ["RaceEngine"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "RaceServer",
            dependencies: ["RaceServerCore", "RaceEngine"]
        ),
        .testTarget(
            name: "RaceEngineTests",
            dependencies: ["RaceEngine"]
        ),
        .testTarget(
            name: "RaceServerTests",
            dependencies: ["RaceServerCore", "RaceEngine"]
        ),
    ]
)
