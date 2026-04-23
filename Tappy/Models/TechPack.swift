import Foundation

struct TechPack: Identifiable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let blurb: String
    let symbolName: String
    let isAvailable: Bool
    let isPremium: Bool

    static let plasticTapping = TechPack(
        id: "plastic-tapping",
        name: "Plastic Tapping",
        tagline: "ASMR tech pack",
        blurb: "Light, glossy taps with short low-latency hits.",
        symbolName: "circle.hexagongrid.fill",
        isAvailable: true,
        isPremium: false
    )

    static let farming = TechPack(
        id: "farming",
        name: "Farming",
        tagline: "New tech pack",
        blurb: "Wood, stone, sand, villager, and munchy farm-game taps remixed for typing.",
        symbolName: "leaf.fill",
        isAvailable: true,
        isPremium: false
    )

    static let bubble = TechPack(
        id: "bubble",
        name: "Bubble",
        tagline: "New tech pack",
        blurb: "Glossy pops, airy blips, and soft bubble hits shaped for fast typing.",
        symbolName: "circle.grid.2x2.fill",
        isAvailable: true,
        isPremium: true
    )

    static let stars = TechPack(
        id: "stars",
        name: "Stars",
        tagline: "New tech pack",
        blurb: "Bright collectible pops, combo chimes, and sparkly game-style UI hits trimmed for typing.",
        symbolName: "sparkles",
        isAvailable: true,
        isPremium: true
    )

    static let swordBattle = TechPack(
        id: "sword-battle",
        name: "Sword Battle",
        tagline: "New tech pack",
        blurb: "Sword slashes, impact swipes, and fuller battle effects shaped into fast keyboard hits.",
        symbolName: "flame.fill",
        isAvailable: true,
        isPremium: true
    )

    static let woodBrush = TechPack(
        id: "wood-brush",
        name: "Wood Brush",
        tagline: "New tech pack",
        blurb: "Dry woody swipes and brushy desk passes shaped into soft tactile key sounds.",
        symbolName: "paintbrush.fill",
        isAvailable: true,
        isPremium: true
    )

    static let fart = TechPack(
        id: "fart",
        name: "Fart",
        tagline: "New tech pack",
        blurb: "Short comic toot and blurp cuts trimmed into low-latency keyboard hits.",
        symbolName: "wind",
        isAvailable: true,
        isPremium: true
    )

    static let analogStopwatch = TechPack(
        id: "analog-stopwatch",
        name: "Analog Stopwatch",
        tagline: "New tech pack",
        blurb: "Winding ratchets and mechanical metallic clicks trimmed into tight keyboard hits.",
        symbolName: "stopwatch.fill",
        isAvailable: true,
        isPremium: true
    )

    static let all: [TechPack] = [
        .plasticTapping,
        .farming,
        .swordBattle,
        .bubble,
        .analogStopwatch,
        .stars,
        .woodBrush,
        .fart
    ]
}
