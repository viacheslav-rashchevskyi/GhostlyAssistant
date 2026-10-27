import AssistantCore
import CoreMedia
import Foundation
import os
import ScreenCaptureKit

enum CaptureError: Error {
    case noDisplay
}

/// Captures all system audio except this app's own and turns it into utterances.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onUtterance: (@Sendable (Utterance) -> Void)?
    /// true while audio is present.
    var onLevel: (@Sendable (Bool) -> Void)?

    private static let log = Logger(subsystem: "local.zoomassistant.app", category: "audio")
    private let queue = DispatchQueue(label: "local.zoomassistant.audio")
    private let segmenter = UtteranceSegmenter()
    private var stream: SCStream?
    private var lastLevel: Bool?
    private var quietSamples = 0

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16_000
        config.channelCount = 1
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        Self.log.info("audio capture started")
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return }
        var samples: [Float] = []
        try? sampleBuffer.withAudioBufferList { list, _ in
            let buffers = Array(list)
            let channels = Int(asbd.mChannelsPerFrame)
            let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            let channelData: [[Float]] = buffers.map { b in
                guard let data = b.mData else { return [] }
                let count = Int(b.mDataByteSize) / MemoryLayout<Float>.size
                return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
            }
            if nonInterleaved && channelData.count > 1 {
                let frames = channelData.map(\.count).min() ?? 0
                let mono = (0..<frames).map { i in channelData.reduce(Float(0)) { $0 + $1[i] } / Float(channelData.count) }
                samples = Resampler.toMono16k(mono, sampleRate: asbd.mSampleRate, channels: 1)
            } else {
                samples = Resampler.toMono16k(channelData.first ?? [], sampleRate: asbd.mSampleRate, channels: nonInterleaved ? 1 : channels)
            }
        }
        guard !samples.isEmpty else { return }
        updateLevel(samples)
        for u in segmenter.append(samples, at: Date()) {
            Self.log.info("utterance \(Double(u.samples.count) / 16_000, format: .fixed(precision: 1))s")
            onUtterance?(u)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Self.log.error("stream stopped: \(error.localizedDescription, privacy: .public)")
    }

    /// Reports "audio present" immediately and "silence" after one quiet second, to avoid flicker.
    private func updateLevel(_ samples: [Float]) {
        let rms = (samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        if rms > 0.01 {
            quietSamples = 0
        } else {
            quietSamples += samples.count
        }
        let present = quietSamples < 16_000
        if present != lastLevel {
            lastLevel = present
            onLevel?(present)
        }
    }
}
