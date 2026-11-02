import Foundation
import Testing
@testable import AssistantCore

func speech(_ seconds: Double) -> [Float] {
    (0..<Int(seconds * 16_000)).map { Float(0.1 * sin(2 * Double.pi * 220 * Double($0) / 16_000)) }
}

func silence(_ seconds: Double) -> [Float] {
    [Float](repeating: 0, count: Int(seconds * 16_000))
}

extension Array {
    func chunked(by size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}

@Test func speechThenSilenceEmitsOneUtterance() {
    let s = UtteranceSegmenter()
    let out = s.append(speech(1.0) + silence(0.8), at: .now)
    #expect(out.count == 1)
    #expect(out[0].samples.count >= 16_000)
}

@Test func shortPauseDoesNotSplit() {
    let out = UtteranceSegmenter().append(speech(1) + silence(0.4) + speech(1) + silence(0.8), at: .now)
    #expect(out.count == 1)
}

@Test func tooShortSpeechIsIgnored() {
    #expect(UtteranceSegmenter().append(speech(0.1) + silence(1), at: .now).isEmpty)
}

@Test func longSpeechIsCutAtMax() {
    let out = UtteranceSegmenter().append(speech(16), at: .now)
    #expect(out.count == 1)
    #expect(out[0].samples.count == 15 * 16_000)
}

@Test func chunkingDoesNotChangeResult() {
    let audio = speech(1) + silence(0.8) + speech(2) + silence(0.8)
    let whole = UtteranceSegmenter().append(audio, at: .now).map(\.samples.count)
    let s = UtteranceSegmenter()
    var chunked: [Int] = []
    for chunk in audio.chunked(by: 333) { chunked += s.append(Array(chunk), at: .now).map(\.samples.count) }
    #expect(whole == chunked)
    #expect(whole.count == 2)
}

@Test func endedAtIsTimeOfCompletingChunk() {
    let s = UtteranceSegmenter()
    let t0 = Date(timeIntervalSince1970: 100)
    #expect(s.append(speech(1), at: t0).isEmpty)
    let out = s.append(silence(0.8), at: t0 + 1)
    #expect(out.first?.endedAt == t0 + 1)
}

@Test func discardDropsUnfinishedSpeech() {
    let s = UtteranceSegmenter()
    #expect(s.append(speech(1), at: .now).isEmpty)
    s.discard()
    let out = s.append(silence(0.2) + speech(0.5) + silence(0.8), at: .now)
    #expect(out.count == 1)
    #expect(out[0].samples.count < 16_000) // only the speech after the discard
}
