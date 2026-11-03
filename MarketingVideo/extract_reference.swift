import AppKit
import AVFoundation
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: extract_reference <video> <output-directory> [interval-seconds]\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let interval = CommandLine.arguments.count > 3 ? (Double(CommandLine.arguments[3]) ?? 1.5) : 1.5

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let asset = AVURLAsset(url: inputURL)
let duration = CMTimeGetSeconds(asset.duration)
guard duration.isFinite, duration > 0 else {
    fputs("Could not read video duration.\n", stderr)
    exit(1)
}

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

var timestamps: [Double] = [0]
var time = interval
while time < duration - 0.05 {
    timestamps.append(time)
    time += interval
}
timestamps.append(max(0, duration - 0.05))

for (index, seconds) in timestamps.enumerated() {
    let requestedTime = CMTime(seconds: seconds, preferredTimescale: 600)
    var actualTime = CMTime.zero
    let image = try generator.copyCGImage(at: requestedTime, actualTime: &actualTime)
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "TappyMarketing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode frame"])
    }

    let actualSeconds = CMTimeGetSeconds(actualTime)
    let filename = String(format: "%03d-%06.2fs.png", index, actualSeconds)
    try png.write(to: outputURL.appendingPathComponent(filename))
    print(String(format: "%@\t%.3f", filename, actualSeconds))
}

print(String(format: "duration=%.3f frames=%d interval=%.2f", duration, timestamps.count, interval))
