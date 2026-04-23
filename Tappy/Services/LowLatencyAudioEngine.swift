import AVFoundation
import Foundation

struct LoadedSound {
    let category: SoundCategory
    let url: URL
    let buffer: AVAudioPCMBuffer
}

enum AudioEngineError: LocalizedError {
    case unreadableFile(URL)
    case unsupportedFormat(URL)
    case conversionFailed(URL)

    var errorDescription: String? {
        switch self {
        case let .unreadableFile(url):
            return "The app could not read \(url.lastPathComponent)."
        case let .unsupportedFormat(url):
            return "\(url.lastPathComponent) uses an unsupported format."
        case let .conversionFailed(url):
            return "The app could not convert \(url.lastPathComponent) into the low-latency playback format."
        }
    }
}

final class LowLatencyAudioEngine {
    private let queue = DispatchQueue(label: "Tappy.LowLatencyAudioEngine", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let outputFormat: AVAudioFormat
    private let concurrentVoices: Int

    private var players: [AVAudioPlayerNode] = []
    private var loadedSounds: [SoundCategory: [LoadedSound]] = [:]
    private var loadedKeySounds: [UInt16: [LoadedSound]] = [:]
    private var lastPlayedIndex: [SoundCategory: Int] = [:]
    private var lastPlayedKeyIndex: [UInt16: Int] = [:]
    private var nextPlayerIndex = 0
    private var isEnabled = true

    init(concurrentVoices: Int = 12) {
        self.concurrentVoices = concurrentVoices

        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 48_000
        let channelCount = max(hardwareFormat.channelCount, 2)
        outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!

        configureEngine()
    }

    func makeBuffer(from url: URL) throws -> AVAudioPCMBuffer {
        let sourceFile = try AVAudioFile(forReading: url)
        let sourceFormat = sourceFile.processingFormat
        let frameCount = AVAudioFrameCount(sourceFile.length)

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw AudioEngineError.unreadableFile(url)
        }

        try sourceFile.read(into: sourceBuffer)

        if sourceFormat == outputFormat {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
            throw AudioEngineError.unsupportedFormat(url)
        }

        let conversionRatio = outputFormat.sampleRate / sourceFormat.sampleRate
        let estimatedFrameCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * conversionRatio) + 1

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: estimatedFrameCapacity
        ) else {
            throw AudioEngineError.conversionFailed(url)
        }

        var didSupplyInput = false
        var conversionError: NSError?

        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if didSupplyInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didSupplyInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if status == .error || conversionError != nil {
            throw AudioEngineError.conversionFailed(url)
        }

        return convertedBuffer
    }

    func setLoadedSounds(_ sounds: [SoundCategory: [LoadedSound]], keySounds: [UInt16: [LoadedSound]]) throws {
        try queue.sync {
            loadedSounds = sounds
            loadedKeySounds = keySounds
            lastPlayedIndex.removeAll()
            lastPlayedKeyIndex.removeAll()
            if isEnabled {
                try startEngineIfNeeded()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.isEnabled = enabled

            if enabled {
                do {
                    try self.startEngineIfNeeded()
                } catch {
                    NSLog("Tappy audio engine enable failed: \(error.localizedDescription)")
                }
            } else {
                self.stopPlayback()
            }
        }
    }

    func play(category: SoundCategory, keyCode: UInt16? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isEnabled else { return }
            guard let sound = self.pickSound(for: category, keyCode: keyCode) else { return }

            do {
                try self.startEngineIfNeeded()
                self.playBuffer(sound.buffer)
            } catch {
                NSLog("Tappy audio engine start failed: \(error.localizedDescription)")
            }
        }
    }

    func play(buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isEnabled else { return }

            do {
                try self.startEngineIfNeeded()
                self.playBuffer(buffer)
            } catch {
                NSLog("Tappy audio engine preview failed: \(error.localizedDescription)")
            }
        }
    }

    private func configureEngine() {
        players = (0..<concurrentVoices).map { _ in
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
            player.volume = 1.0
            return player
        }

        engine.mainMixerNode.outputVolume = 1.0
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func stopPlayback() {
        for player in players {
            player.stop()
        }

        if engine.isRunning {
            engine.pause()
        }
    }

    private func pickSound(for category: SoundCategory, keyCode: UInt16?) -> LoadedSound? {
        let keyOptions = keyCode.flatMap { loadedKeySounds[$0] }
        let options = candidateSounds(for: category, keyCode: keyCode)
        guard !options.isEmpty else { return nil }

        if let keyCode, let keyOptions, !keyOptions.isEmpty {
            if options.count == 1 {
                lastPlayedKeyIndex[keyCode] = 0
                return options[0]
            }

            var nextIndex = Int.random(in: 0..<options.count)
            if let lastIndex = lastPlayedKeyIndex[keyCode], nextIndex == lastIndex {
                nextIndex = (nextIndex + 1) % options.count
            }

            lastPlayedKeyIndex[keyCode] = nextIndex
            return options[nextIndex]
        }

        if options.count == 1 {
            lastPlayedIndex[category] = 0
            return options[0]
        }

        var nextIndex = Int.random(in: 0..<options.count)
        if let lastIndex = lastPlayedIndex[category], nextIndex == lastIndex {
            nextIndex = (nextIndex + 1) % options.count
        }

        lastPlayedIndex[category] = nextIndex
        return options[nextIndex]
    }

    private func candidateSounds(for category: SoundCategory, keyCode: UInt16?) -> [LoadedSound] {
        if let keyCode, let keySounds = loadedKeySounds[keyCode], !keySounds.isEmpty {
            return keySounds
        }

        if let categorySounds = loadedSounds[category], !categorySounds.isEmpty {
            return categorySounds
        }

        return loadedSounds[.standard] ?? []
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        let player = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }
}
