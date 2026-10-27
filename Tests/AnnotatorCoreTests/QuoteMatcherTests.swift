import Foundation
import Testing
@testable import AnnotatorCore

struct QuoteMatcherTests {
    private func matched(_ quote: String, in text: String) -> String? {
        guard let r = QuoteMatcher.find(quote, in: text) else { return nil }
        return (text as NSString).substring(with: r)
    }

    @Test func exactMatch() {
        let text = "Cells are the basic unit of life. The mitochondria is the powerhouse of the cell."
        #expect(matched("the mitochondria is the powerhouse", in: text) == "The mitochondria is the powerhouse")
    }

    @Test func ignoresLineBreaksAndSpacing() {
        let text = "Photosynthesis converts light\nenergy into   chemical energy."
        #expect(matched("converts light energy into chemical energy", in: text) == "converts light\nenergy into   chemical energy")
    }

    @Test func normalizesCurlyQuotesAndDashes() {
        let text = "He said \u{201C}it\u{2019}s over\u{201D} \u{2014} and left."
        #expect(matched("said \"it's over\" - and left", in: text) != nil)
    }

    @Test func joinsHyphenatedLineBreaks() {
        let text = "The process of photo-\nsynthesis occurs in chloroplasts."
        #expect(matched("process of photosynthesis occurs", in: text) == "process of photo-\nsynthesis occurs")
    }

    @Test func handlesLigatures() {
        let text = "The \u{FB01}rst \u{FB02}ow of energy"
        #expect(matched("first flow of energy", in: text) == "\u{FB01}rst \u{FB02}ow of energy")
    }

    @Test func ellipsisSpansFirstToLastFragment() {
        let text = "The French Revolution began in 1789 and transformed politics across Europe for decades."
        #expect(matched("The French Revolution began ... across Europe", in: text)
                == "The French Revolution began in 1789 and transformed politics across Europe")
    }

    @Test func fuzzyToleratesSmallMiddleDifferences() {
        let text = "Natural selection is the process by which organisms better adapted to their environment tend to survive."
        let quote = "Natural selection is the process where organisms better adapted to their environment tend to survive"
        #expect(matched(quote, in: text)?.hasPrefix("Natural selection") == true)
    }

    @Test func returnsNilWhenAbsent() {
        #expect(QuoteMatcher.find("quantum chromodynamics explains everything", in: "Cells are the basic unit of life.") == nil)
    }

    @Test func rangesAreUTF16ForEmojiAndAccents() {
        let text = "Café 🌍 culture: the café was central to Parisian intellectual life."
        #expect(matched("central to Parisian intellectual life", in: text) == "central to Parisian intellectual life")
    }
}
