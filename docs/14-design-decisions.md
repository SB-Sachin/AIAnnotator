# 14. Design decisions & history

[← 13 Building & testing](13-building-and-testing.md) · [Docs index](README.md) · Next: [15 Limitations & troubleshooting →](15-limitations-and-troubleshooting.md)

Why AI Annotator is built the way it is, and the problems that shaped it. Each entry gives the decision, the reasons,
and the alternatives that were considered.

## Decisions

### Native SwiftUI + PDFKit, not a web or Electron app
Chosen in the planning interview. PDFKit gives exact text positions, standard annotations that open in Preview,
and smooth scrolling of large PDFs; Vision gives on-device OCR; the app stays small and feels like a Mac app.
*Alternative:* a web stack with PDF.js. It would need its own text-position and annotation code, and wouldn't
integrate with Apple's OCR.

### A Swift Package plus a bundle script, not an Xcode project
The Mac it was built on only has the Command Line Tools. A package builds with `swift build`; a 40-line script makes the
`.app`. *Cost:* two macro workarounds ([13](13-building-and-testing.md#building-without-xcode)).

### All logic in `AnnotatorCore`
Prompts, matching, planning, drawing, notes and storage are UI-free and unit-tested; the app target is presentation and
orchestration. This made it possible to tune highlighting against real pages from tests rather than by clicking.

### Quotes, not coordinates
The model returns **text**, never positions. Language models are poor at pixel coordinates, while PDFKit knows exactly
where every character is. Asking for an exact quote and finding it ([6](06-quote-matching.md)) gives
character-precise highlights, and a quote that can't be found is simply skipped instead of drawn in the wrong place.

### Structured outputs everywhere
Every call carries a JSON Schema ([8](08-ollama-integration.md#structured-outputs)). No parsing of prose, enums that
restrict categories, and one retry for the rare reply that doesn't decode.

### One call per page, combining highlights and digest
With "Both", a page's highlights and its notes digest come from the same request. That halves the number of model
calls for the most common choice.

### Notes in two passes, from saved digests
Per-page digests, then one notes call ([7](07-notes-pipeline.md)). This scales to 20 pages within the context
window, and since the digests are saved ([10](10-library-and-storage.md#digestsjson)), switching templates later costs
one call.

### Markdown as the source of truth for notes
The notes you see, edit and export are one Markdown string. The preview and the PDF renderer both parse it, so
your edits are always reflected everywhere. Cornell notes use a fixed Markdown shape (`### cue` rows, `## Summary`)
that's still readable as plain text.

### Plain files, not a database
A reading is a folder with a PDF, Markdown and JSON ([10](10-library-and-storage.md)). Easy to inspect, back up and
move, and the annotated PDF is usable without the app.

### The app enforces restraint, not the prompt
The density budget, the length limits and one-per-sentence are applied in code by the planner
([5](05-highlighting-pipeline.md#the-planner)). Prompts help, but models over-highlight anyway; see the history below.

### Light is the default density
Fewer, better highlights are more useful for review, and redoing with more is one click. The first feedback was
"way too much highlighting".

### Undo as an in-memory snapshot
A redo can rewrite every page, so undo restores a full snapshot of the PDF and settings
([11](11-redo-and-undo.md#undo-last-redo)). One level, in memory: simple and reliable. *Alternative:* per-annotation
undo history. More complex, and not what people reach for after a redo they don't like.

## History: problems found and how they were fixed

The project's commits, in order:

| Commit | What changed |
|--------|--------------|
| `84bc383` Initial app | The full first version: ingest, OCR, prompts, matching, highlights, notes, exports, library, presets editor. |
| `3eeb2cc` App icon | The icon, drawn in code. |
| `f7c1849` Sharper, lighter highlights; annotation list; refreshed design | Numbered sentences, the planner and density, overlap fixes, the Highlights list, the new design. |
| `be9ca7b` Fix highlighting on photographed pages | Straightening, the word-by-word text layer, quotation-mark matching, saved quotes, margin-note sizing. |
| `e0beac1` Redo and undo | Redo highlights or notes, your-highlights protection, saved digests, re-reading photos, undo. |

### Over-highlighting (first version)
**Symptom:** the first real run highlighted almost every sentence. **Cause:** the prompt allowed long quotes, and the
only limit was a per-page count (10). **First fix:** the prompt asked for 4–25-word key phrases covering "well under a
third" of the page. Better, but still too much in practice. **Real fix** (`f7c1849`): the planner with a density budget
based on page length and character share, importance ranking, 3–24 words, one per sentence, with Light as the default.
On a dense textbook page, Light now marks about 6 % of the words.

### Cornell cues repeated in the notes column
**Symptom:** each row's first note restated the cue question. **Fix:** the prompt says notes contain only answers, and the
formatter removes a first note that ends in `?` when there are others ([7](07-notes-pipeline.md#cornell-markdown)).

<a id="loose-fuzzy-matching"></a>
### Loose fuzzy matching
**Symptom:** some highlights landed on the wrong passage. **Cause:** the fuzzy step took the *first* place the quote's
first 8+ characters appeared and accepted any end within 1.3× the length, so common openings like "the cell " matched
the wrong sentence. **Fix:** longer anchors (12–30 characters), a strict length window (85–120 %), the closest-length
candidate, and, more importantly, searching inside the sentence the model named
([6](06-quote-matching.md#4-fuzzy-match)).

### Overlapping highlights and dark bands
**Symptom:** highlights overlapped, and multi-line highlights showed darker stripes. **Causes:** two suggestions could
cover the same words, and PDFKit's line boxes are taller than the line spacing, so translucent color stacked.
**Fix:** the planner forbids overlaps and same-sentence pairs; line boxes are trimmed 6 % top and bottom and separated
at midpoints; a new manual highlight replaces one it covers ([5](05-highlighting-pipeline.md#drawing-highlights)).

<a id="numbered-sentences"></a>
### Sentences split at every PDF line break
**Symptom** (found while testing): the sentence tokenizer turned each printed line into a "sentence", so sentence
numbers were meaningless. **Cause:** PDF text breaks at every printed line, and the tokenizer treats a newline as a
boundary. **Fix:** tokenize a same-length copy with single newlines turned into spaces
([5](05-highlighting-pipeline.md#step-1-numbered-sentences-pagesentences)).

### Garbled text in the highlights list
**Symptom:** the list showed `New Englanamuch`, `labo-ers`. **Cause:** the text was read back line box by line box, which
clipped letters at the edges and dropped the spaces between lines. **Fix:** read back as one continuous selection, and
store the exact quote in the annotation (`/AIQuote`) when it's created.

<a id="photos-made-paragraph-sized-blobs"></a>
### Photos made paragraph-sized blobs (the big one)
**Symptom:** on a reading made from five phone photos, each highlight was a huge rounded blob covering a whole
paragraph, and the text read `townsmade`, `theyrequired`. The highlight *counts* were fine (1–3 per page); the
*shapes* were the problem. **Cause:** the photo-to-PDF step drew each OCR line as one invisible text run inside its
axis-aligned bounding box, with no space between lines. On a tilted photo those boxes are much taller than the text and
overlap the neighboring lines, and the missing spaces glued words together. PDFKit couldn't tell lines apart, so a
selection's "line" covered most of a paragraph. Earlier tests had only used digital PDFs and a flat synthetic image, so
none caught it. **Fix** (`be9ca7b`, [4](04-ingest-and-ocr.md)):

1. straighten photos first: crop and flatten the page, then rotate the text level;
2. lay out the invisible text **word by word** at each word's own box, with spaces;
3. a regression test that photographs tilted text and checks spacing and box heights. It fails on the old code and
   passes on the new.

Result on the same five photos: 2–4 highlights per page, each one line-sized, about 5–7 % of the text.

### Quotes missed because of quotation marks
**Symptom:** after the photo fix, some quotes still weren't found. **Cause:** the page had `''gentleman,'' "yeoman,"`
(OCR is inconsistent with quote marks) and the model wrote `gentleman, yeoman, or laborer`. **Fix:** the matcher drops all
quotation marks and apostrophes on both sides ([6](06-quote-matching.md#1-normalize-both-texts-the-same-way)).

### Margin notes cut off
**Symptom:** the last line of margin notes was clipped. **Cause:** the box was measured at the text's exact height, but
PDFKit pads free-text annotations. **Fix:** measure 14 pt narrower and add 12 pt of height.

### Sticky-note popups left behind on redo
**Symptom** (found by a test): clearing AI annotations left an empty `/Popup`. **Cause:** PDFKit creates a separate popup
annotation for a sticky note. **Fix:** remove the popup with its parent.

### Build issues (Command Line Tools only)
- `LibraryItem` clashed with SwiftUI's own `LibraryItem` type; renamed to `ReadingItem`.
- The `@State` and Swift Testing macro plugins: see [13](13-building-and-testing.md#building-without-xcode).
