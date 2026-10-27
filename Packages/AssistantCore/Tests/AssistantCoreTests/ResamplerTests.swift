import Testing
@testable import AssistantCore

@Test func resamplesStereo48kToMono16k() {
    let stereo = (0..<9600).map { $0 % 2 == 0 ? Float(0.2) : Float(0.4) } // 4800 frames
    let mono = Resampler.toMono16k(stereo, sampleRate: 48_000, channels: 2)
    #expect(mono.count == 1600)
    #expect(abs(mono[100] - 0.3) < 0.001)
}

@Test func mono16kPassesThrough() {
    let input: [Float] = [0.1, 0.2, 0.3]
    #expect(Resampler.toMono16k(input, sampleRate: 16_000, channels: 1) == input)
}
