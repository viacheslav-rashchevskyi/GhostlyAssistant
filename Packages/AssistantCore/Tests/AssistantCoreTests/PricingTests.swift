import Foundation
import Testing
@testable import AssistantCore

private let page = """
# Pricing

| Model | Base input tokens | 5m cache writes | 1h cache writes | Cache hits and refreshes | Output tokens |
|-------|-------------------|-----------------|-----------------|--------------------------|---------------|
| Claude Mythos 5.1 ([limited availability](https://support.claude.com/x)) | $10 / MTok | $12.50 / MTok | $20 / MTok | $0.25 / MTok<sup>1</sup> | $50 / MTok |
| Claude Opus 5.5 | $4 / MTok | $5 / MTok | $8 / MTok | $0.20 / MTok<sup>2</sup> | $20 / MTok |
| Claude Sonnet 5 | $2 / MTok<sup>3</sup> | $2.50 / MTok | $4 / MTok | $0.20 / MTok | $10 / MTok<sup>3</sup> |
| Claude Haiku 5.5 (for prompts up to 100,000 tokens) | $0.10 / MTok | $0.125 / MTok | $0.20 / MTok | $0.01 / MTok | $0.50 / MTok |
| Claude Haiku 5.5 (for prompts over 100,000 tokens) | $0.50 / MTok | $0.625 / MTok | $1 / MTok | $0.05 / MTok | $2.50 / MTok |

## Batch

| Model | Batch input | Batch output |
|-------|-------------|--------------|
| Claude Opus 5.5 | $2 / MTok | $10 / MTok |
"""

@Test func parsesStandardPricesByDisplayName() {
    let prices = PricingPage.parse(page)
    #expect(prices["Claude Opus 5.5"] == ClaudePrice(input: 4, output: 20))
    #expect(prices["Claude Sonnet 5"] == ClaudePrice(input: 2, output: 10))
    #expect(prices["Claude Mythos 5.1"] == ClaudePrice(input: 10, output: 50))
}

@Test func firstRowWinsForTieredModels() {
    #expect(PricingPage.parse(page)["Claude Haiku 5.5"] == ClaudePrice(input: 0.10, output: 0.50))
}

@Test func batchTableDoesNotOverrideStandardPrices() {
    #expect(PricingPage.parse(page)["Claude Opus 5.5"]?.input == 4)
}

@Test func garbageGivesNoPrices() {
    #expect(PricingPage.parse("<html>not found</html>").isEmpty)
}

@Test func fetchReadsThePublicPage() async throws {
    let t = MockTransport(status: 200, body: page)
    let prices = try await PricingPage.fetch(transport: t)
    #expect(prices["Claude Opus 5.5"] == ClaudePrice(input: 4, output: 20))
    #expect(t.last?.url?.absoluteString == "https://platform.claude.com/docs/en/about-claude/pricing.md")
}
