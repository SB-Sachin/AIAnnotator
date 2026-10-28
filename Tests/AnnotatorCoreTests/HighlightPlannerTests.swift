import Foundation
import Testing
@testable import AnnotatorCore

struct HighlightPlannerTests {
    // About 160 words, so the length-based budget allows only a few highlights.
    let text = """
    Photosynthesis converts light energy into chemical energy stored in glucose. It takes place in the chloroplasts of plant cells. \
    The light-dependent reactions happen in the thylakoid membranes and produce ATP and NADPH. \
    The Calvin cycle uses that ATP and NADPH to fix carbon dioxide into sugar. \
    Chlorophyll absorbs mostly red and blue light and reflects green, which is why leaves look green. \
    Factors such as light intensity, temperature and carbon dioxide concentration limit the rate of photosynthesis. \
    In 1779 Jan Ingenhousz showed that plants need light to produce oxygen. \
    Today scientists study photosynthesis to design better solar cells and to improve crop yields. \
    Some plants, called C4 plants, concentrate carbon dioxide to reduce photorespiration in hot climates. \
    CAM plants open their stomata at night to save water in deserts. \
    Overall, photosynthesis supplies nearly all of the energy that flows through ecosystems on Earth.
    """

    func h(_ quote: String, _ sentence: Int? = nil, importance: Int = 2) -> RawHighlight {
        RawHighlight(quote: quote, category: "main", note: "", sentence: sentence, importance: importance)
    }

    @Test func dropsOverlapsKeepingMoreImportant() {
        let s = PageSentences(text)
        let plan = HighlightPlanner.plan([
            h("converts light energy into chemical energy", 1, importance: 2),
            h("Photosynthesis converts light energy", 1, importance: 3),
        ], sentences: s, density: .thorough, maxPerPage: 10)
        #expect(plan.highlights.count == 1)
        #expect((text as NSString).substring(with: plan.highlights[0].range) == "Photosynthesis converts light energy")
        #expect(plan.dropped == 1)
    }

    @Test func onePerSentence() {
        let plan = HighlightPlanner.plan([
            h("light-dependent reactions", 3), h("produce ATP and NADPH", 3),
        ], sentences: PageSentences(text), density: .thorough, maxPerPage: 10)
        #expect(plan.highlights.count == 1)
    }

    @Test func enforcesDensityBudget() {
        let s = PageSentences(text)
        let many = s.sentences.enumerated().map { i, sentence in
            h(sentence.text.split(separator: " ").prefix(6).joined(separator: " "), i + 1)
        }
        let light = HighlightPlanner.plan(many, sentences: s, density: .light, maxPerPage: 10)
        let thorough = HighlightPlanner.plan(many, sentences: s, density: .thorough, maxPerPage: 10)
        // Budget scales with page length: about one highlight per `wordsPerHighlight` words, at least 2.
        #expect(light.highlights.count == max(2, s.wordCount / HighlightDensity.light.wordsPerHighlight))
        #expect(thorough.highlights.count == max(2, s.wordCount / HighlightDensity.thorough.wordsPerHighlight))
        #expect(light.highlights.count < many.count / 3)
        #expect(light.highlights.count + light.dropped == many.count)
        // Kept highlights come back in reading order.
        #expect(light.highlights.map(\.range.location) == light.highlights.map(\.range.location).sorted())
    }

    @Test func prefersNamedSentence() throws {
        // "ATP and NADPH" appears in sentences 3 and 4; the sentence number decides which one.
        let s = PageSentences(text)
        let plan = HighlightPlanner.plan([h("ATP and NADPH", 4)], sentences: s, density: .balanced, maxPerPage: 10)
        let r = try #require(plan.highlights.first?.range)
        #expect(NSLocationInRange(r.location, s.sentences[3].range))
        #expect(!NSLocationInRange(r.location, s.sentences[2].range))
    }

    @Test func dropsOverlongQuotes() {
        let long = "Factors such as light intensity, temperature and carbon dioxide concentration limit the rate of photosynthesis. In 1779 Jan Ingenhousz showed that plants need light to produce oxygen."
        let plan = HighlightPlanner.plan([h(long)], sentences: PageSentences(text), density: .thorough, maxPerPage: 10)
        #expect(plan.highlights.isEmpty)
        #expect(plan.dropped == 1)
    }

    @Test func numbersSentencesForPrompt() {
        let s = PageSentences("First idea here.\nSecond idea is hyphen-\nated across lines.")
        #expect(s.sentences.count == 2)
        #expect(s.numbered(limit: 1000) == "[1] First idea here.\n[2] Second idea is hyphenated across lines.")
    }

    @Test func fuzzyMatchRejectsSpansOfWrongLength() {
        let page = "The cell membrane controls what enters the cell. Much later, after many unrelated words about other topics entirely, the cell wall gives structure."
        // Head and tail exist but are far apart: not a match.
        #expect(QuoteMatcher.find("The cell membrane controls what gives structure.", in: page) == nil)
    }

    @MainActor @Test func separatesStackedLineBoxes() {
        let top = CGRect(x: 0, y: 100, width: 200, height: 14)
        let below = CGRect(x: 0, y: 88, width: 200, height: 14)   // overlaps top by 2pt
        let out = PDFHighlighter.separated([top, below], from: [])
        #expect(out.count == 2)
        #expect(!out[0].intersects(out[1]) || out[0].intersection(out[1]).height < 0.01)
        // Boxes on the same line are left alone.
        let a = CGRect(x: 0, y: 100, width: 50, height: 14), b = CGRect(x: 60, y: 100, width: 50, height: 14)
        #expect(PDFHighlighter.separated([a, b], from: []) == [a, b])
    }
}
