import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation

guard CommandLine.arguments.count >= 4 else {
    fputs("Usage: render_video <scene-directory> <audio.wav> <output.mp4>\n", stderr)
    exit(2)
}

let sceneDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let audioURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
let silentURL = outputURL.deletingLastPathComponent().appendingPathComponent("Tappy-Promo-Vertical-silent.mp4")

let width = 1080
let height = 1920
let frameRate: Int32 = 30
let duration = 31.43333333333333
let frameCount = Int(ceil(duration * Double(frameRate)))
let transitionDuration = 0.34
let outputRect = CGRect(x: 0, y: 0, width: width, height: height)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let ciContext = CIContext(options: [
    .cacheIntermediates: false,
    .useSoftwareRenderer: false,
])

struct Scene {
    let filename: String
    let start: Double
    let end: Double
    let driftX: CGFloat
    let driftY: CGFloat
    let zoom: CGFloat
}

let scenes = [
    Scene(filename: "01-hero.png", start: 0.0, end: 2.6, driftX: 0, driftY: 14, zoom: 1.035),
    Scene(filename: "02-question.png", start: 2.6, end: 4.25, driftX: -10, driftY: 0, zoom: 1.020),
    Scene(filename: "03-question-complete.png", start: 4.25, end: 6.2, driftX: 10, driftY: -8, zoom: 1.022),
    Scene(filename: "04-menu-plastic.png", start: 6.2, end: 9.5, driftX: 0, driftY: -18, zoom: 1.026),
    Scene(filename: "05-menu-squishy.png", start: 9.5, end: 12.2, driftX: 0, driftY: 18, zoom: 1.024),
    Scene(filename: "06-everywhere.png", start: 12.2, end: 16.35, driftX: -14, driftY: -8, zoom: 1.030),
    Scene(filename: "07-sound-graphics.png", start: 16.35, end: 21.85, driftX: 12, driftY: -16, zoom: 1.034),
    Scene(filename: "08-all-sounds.png", start: 21.85, end: 25.0, driftX: -10, driftY: 12, zoom: 1.024),
    Scene(filename: "09-privacy.png", start: 25.0, end: 27.7, driftX: 10, driftY: 0, zoom: 1.022),
    Scene(filename: "10-cta.png", start: 27.7, end: duration, driftX: 0, driftY: -10, zoom: 1.030),
]

func loadScene(_ scene: Scene) -> CIImage {
    let url = sceneDirectory.appendingPathComponent(scene.filename)
    guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        fputs("Could not load scene: \(url.path)\n", stderr)
        exit(1)
    }
    let scaleX = CGFloat(width) / image.extent.width
    let scaleY = CGFloat(height) / image.extent.height
    return image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY)).cropped(to: outputRect)
}

let loadedScenes = scenes.map(loadScene)

func easeInOut(_ value: Double) -> CGFloat {
    let t = CGFloat(max(0.0, min(1.0, value)))
    return t * t * (3.0 - 2.0 * t)
}

func animatedImage(_ image: CIImage, scene: Scene, at time: Double) -> CIImage {
    let progress = easeInOut((time - scene.start) / max(0.001, scene.end - scene.start))
    let scale = 1.0 + (scene.zoom - 1.0) * progress
    let x = scene.driftX * (progress - 0.5)
    let y = scene.driftY * (progress - 0.5)
    var transform = CGAffineTransform(translationX: CGFloat(width) / 2 + x, y: CGFloat(height) / 2 + y)
    transform = transform.scaledBy(x: scale, y: scale)
    transform = transform.translatedBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
    return image.transformed(by: transform).cropped(to: outputRect)
}

func imageWithAlpha(_ image: CIImage, alpha: CGFloat) -> CIImage {
    image.applyingFilter("CIColorMatrix", parameters: [
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha),
    ])
}

func frameImage(at time: Double) -> CIImage {
    let currentIndex = scenes.lastIndex(where: { time >= $0.start }) ?? 0
    let currentScene = scenes[currentIndex]
    let current = animatedImage(loadedScenes[currentIndex], scene: currentScene, at: time)
    guard currentIndex > 0, time < currentScene.start + transitionDuration else {
        return current
    }
    let previousScene = scenes[currentIndex - 1]
    let previous = animatedImage(loadedScenes[currentIndex - 1], scene: previousScene, at: previousScene.end)
    let progress = easeInOut((time - currentScene.start) / transitionDuration)
    return imageWithAlpha(current, alpha: progress).composited(over: previous)
}

try? FileManager.default.removeItem(at: silentURL)
try? FileManager.default.removeItem(at: outputURL)

let writer = try AVAssetWriter(outputURL: silentURL, fileType: .mp4)
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 6_000_000,
        AVVideoExpectedSourceFrameRateKey: frameRate,
        AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    ],
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
input.expectsMediaDataInRealTime = false
let attributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
]
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
guard writer.canAdd(input) else {
    fputs("Could not add video input.\n", stderr)
    exit(1)
}
writer.add(input)
guard writer.startWriting() else {
    throw writer.error ?? NSError(domain: "TappyMarketing", code: 1)
}
writer.startSession(atSourceTime: .zero)

for frameIndex in 0..<frameCount {
    while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.002)
    }
    autoreleasepool {
        guard let pool = adaptor.pixelBufferPool else {
            fputs("Pixel buffer pool was unavailable.\n", stderr)
            exit(1)
        }
        var maybeBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
        guard status == kCVReturnSuccess, let buffer = maybeBuffer else {
            fputs("Could not create pixel buffer: \(status)\n", stderr)
            exit(1)
        }
        let seconds = Double(frameIndex) / Double(frameRate)
        ciContext.render(frameImage(at: seconds), to: buffer, bounds: outputRect, colorSpace: colorSpace)
        let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
        guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
            fputs("Could not append frame \(frameIndex): \(writer.error?.localizedDescription ?? "unknown")\n", stderr)
            exit(1)
        }
    }
    if frameIndex % 94 == 0 {
        print("render \(Int(Double(frameIndex) / Double(frameCount) * 100.0))%")
    }
}

input.markAsFinished()
let writerSemaphore = DispatchSemaphore(value: 0)
writer.finishWriting {
    writerSemaphore.signal()
}
writerSemaphore.wait()
guard writer.status == .completed else {
    throw writer.error ?? NSError(domain: "TappyMarketing", code: 2)
}

let videoAsset = AVURLAsset(url: silentURL)
let audioAsset = AVURLAsset(url: audioURL)
let composition = AVMutableComposition()
guard
    let sourceVideoTrack = videoAsset.tracks(withMediaType: .video).first,
    let sourceAudioTrack = audioAsset.tracks(withMediaType: .audio).first,
    let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
    let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
else {
    fputs("Could not prepare video and audio tracks.\n", stderr)
    exit(1)
}

let finalDuration = CMTime(seconds: duration, preferredTimescale: 600)
try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: finalDuration), of: sourceVideoTrack, at: .zero)
let audioDuration = min(audioAsset.duration, finalDuration)
try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration), of: sourceAudioTrack, at: .zero)

guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
    fputs("Could not create export session.\n", stderr)
    exit(1)
}
exporter.outputURL = outputURL
exporter.outputFileType = .mp4
exporter.shouldOptimizeForNetworkUse = true
let exportSemaphore = DispatchSemaphore(value: 0)
exporter.exportAsynchronously {
    exportSemaphore.signal()
}
exportSemaphore.wait()
guard exporter.status == .completed else {
    throw exporter.error ?? NSError(domain: "TappyMarketing", code: 3)
}

print(outputURL.path)
