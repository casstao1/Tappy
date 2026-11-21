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
        name: "Tapping Nails on Plastic",
        tagline: "Light feedback cues",
        blurb: "Light, glossy cues for clear low-latency typing feedback.",
        symbolName: "circle.hexagongrid.fill",
        isAvailable: true,
        isPremium: false
    )

    static let farming = TechPack(
        id: "farming",
        name: "Wood and Sand Blocks",
        tagline: "Natural feedback cues",
        blurb: "Wood, stone, and soft organic taps shaped for typing awareness.",
        symbolName: "leaf.fill",
        isAvailable: true,
        isPremium: false
    )

    static let swordBattle = TechPack(
        id: "sword-battle",
        name: "Sword Battle",
        tagline: "Battle sound effects",
        blurb: "Sword slashes, impact swipes, and battle effects shaped into keyboard sounds.",
        symbolName: "flame.fill",
        isAvailable: true,
        isPremium: true
    )

    static let bubble = TechPack(
        id: "bubble",
        name: "Bubbles",
        tagline: "Gentle feedback cues",
        blurb: "Glossy pops and airy blips for softer auditory typing feedback.",
        symbolName: "circle.grid.2x2.fill",
        isAvailable: true,
        isPremium: true
    )

    static let stars = TechPack(
        id: "stars",
        name: "Star Level Up",
        tagline: "High-clarity feedback cues",
        blurb: "Bright, lightweight cues for users who prefer more audible typing feedback.",
        symbolName: "sparkles",
        isAvailable: true,
        isPremium: true
    )

    static let woodBrush = TechPack(
        id: "wood-brush",
        name: "Wood Brush",
        tagline: "Dry tactile feedback cues",
        blurb: "Dry woody swipes and brushy desk passes shaped into soft tactile cues.",
        symbolName: "paintbrush.fill",
        isAvailable: true,
        isPremium: true
    )

    static let analogStopwatch = TechPack(
        id: "analog-stopwatch",
        name: "Mechanical Ticks",
        tagline: "Precise feedback cues",
        blurb: "Winding ratchets and compact metallic ticks for precise typing feedback.",
        symbolName: "stopwatch.fill",
        isAvailable: true,
        isPremium: true
    )

    static let squishyPop = TechPack(
        id: "studio-mix",
        name: "Wet Squishy Pop",
        tagline: "Wet tactile pops",
        blurb: "Seventeen wet, crackly pops with a tactile squish across every key.",
        symbolName: "drop.fill",
        isAvailable: true,
        isPremium: false
    )

    static let waxCracking = TechPack(
        id: "wax-cracking",
        name: "Wax Cracking",
        tagline: "Crisp layered cracks",
        blurb: "Eleven crisp wax cracks with brittle, layered texture across every key.",
        symbolName: "seal.fill",
        isAvailable: true,
        isPremium: true
    )

    static let fart = TechPack(
        id: "fart",
        name: "Fart",
        tagline: "Playful comic sounds",
        blurb: "A collection of silly toots and pops for your keyboard.",
        symbolName: "wind",
        isAvailable: true,
        isPremium: true
    )

    static let paperCrinkle = TechPack(
        id: "paper-crinkle",
        name: "Paper Crinkle",
        tagline: "Crisp paper sounds",
        blurb: "A selection of crisp paper crinkles for every key.",
        symbolName: "doc.text.fill",
        isAvailable: true,
        isPremium: true
    )

    static let plasticCrinkle = TechPack(
        id: "plastic-crinkle",
        name: "Plastic Crinkle",
        tagline: "Crisp plastic sounds",
        blurb: "A selection of crinkly plastic sounds for every key.",
        symbolName: "waveform",
        isAvailable: true,
        isPremium: true
    )

    static let wetMouth = TechPack(
        id: "wet-mouth",
        name: "Wet Mouth Sounds",
        tagline: "Soft ASMR sounds",
        blurb: "A selection of wet mouth sounds for every key.",
        symbolName: "mouth.fill",
        isAvailable: true,
        isPremium: true
    )

    static let suckingWaterThroughATube = TechPack(
        id: "sucking-water-through-a-tube",
        name: "Water Tube Sucking",
        tagline: "Tingly water sounds",
        blurb: "A selection of soft, watery sounds for every key.",
        symbolName: "drop.fill",
        isAvailable: true,
        isPremium: true
    )

    static let hairBrushing = TechPack(
        id: "hair-brushing",
        name: "Hair Brushing",
        tagline: "Soft brushing sounds",
        blurb: "Gentle brushing sounds for every key.",
        symbolName: "paintbrush.fill",
        isAvailable: true,
        isPremium: true
    )

    static let splashingWater = TechPack(
        id: "splashing-water",
        name: "Taking care of business",
        tagline: "Playful water sounds",
        blurb: "A selection of gentle water splashes for every key.",
        symbolName: "toilet.fill",
        isAvailable: true,
        isPremium: true
    )

    static let gentleWaterSwishing = TechPack(
        id: "gentle-water-swishing",
        name: "Gentle Water Swishing",
        tagline: "Soft flowing water",
        blurb: "Gentle water sounds for every key.",
        symbolName: "water.waves",
        isAvailable: true,
        isPremium: true
    )

    static let scissorsCutting = TechPack(
        id: "scissors-cutting",
        name: "Scissors Cutting",
        tagline: "Crisp cutting sounds",
        blurb: "A selection of scissors sounds for every key.",
        symbolName: "scissors",
        isAvailable: true,
        isPremium: true
    )

    static let catMeows = TechPack(
        id: "cat-meows",
        name: "Cat Meows",
        tagline: "Playful cat sounds",
        blurb: "A selection of cat meows for every key.",
        symbolName: "cat.fill",
        isAvailable: true,
        isPremium: true
    )

    static let dogBarks = TechPack(
        id: "dog-barks",
        name: "Dog Barks",
        tagline: "Playful dog sounds",
        blurb: "A selection of dog barks for every key.",
        symbolName: "dog.fill",
        isAvailable: true,
        isPremium: true
    )

    static let running = TechPack(
        id: "running",
        name: "Running",
        tagline: "Quick footsteps",
        blurb: "A selection of running footsteps for every key.",
        symbolName: "figure.run",
        isAvailable: true,
        isPremium: true
    )

    static let thud = TechPack(
        id: "thud",
        name: "Thud",
        tagline: "A full impact sound",
        blurb: "The full thud sound plays on each key.",
        symbolName: "burst.fill",
        isAvailable: true,
        isPremium: true
    )

    static let all: [TechPack] = [
        .plasticTapping,
        .farming,
        .squishyPop,
        .swordBattle,
        .waxCracking,
        .bubble,
        .analogStopwatch,
        .stars,
        .woodBrush,
        .fart,
        .splashingWater,
        .paperCrinkle,
        .plasticCrinkle,
        .wetMouth,
        .suckingWaterThroughATube,
        .hairBrushing,
        .gentleWaterSwishing,
        .scissorsCutting,
        .catMeows,
        .dogBarks,
        .running,
        .thud
    ]
}
