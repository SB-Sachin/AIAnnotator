# AI Annotator

A small native Mac app that reads a PDF or photos of textbook pages with a **local Ollama model**
and produces study notes in a template, a highlighted and annotated copy of the pages, or both.
Nothing leaves your Mac.

## Run it

```bash
./scripts/build-app.sh      # builds build/AIAnnotator.app (no Xcode needed)
open build/AIAnnotator.app
```

You need Ollama running with a model installed. The default is `gemma3:12b`, which can also look at
page images; switch models in Settings. While developing, `swift run AIAnnotator` also works.

## Using it

1. Drop a PDF, or several photos of pages (they're combined in filename order and OCR'd on-device).
2. Choose **Notes**, **Highlights** or **Both**, a highlight style, how much to highlight
   (**Light** ≈ 2–4 per page, **Balanced** ≈ 3–6, **Thorough** ≈ 5–9), a note template, and a model.
3. Pages are processed one at a time (about 20–60 seconds each with gemma3:12b). Highlights appear as they're placed.
4. Review the result. The **Highlights** panel lists every highlight by page with its quote and note;
   filter by category, and click one to jump to it on the page.
   - Select text on the page and pick a color to add your own highlight (it replaces any highlight under it).
   - Click a highlight, on the page or in the list, to recolor it, edit its note, or delete it.
   - Notes can be edited as Markdown.
5. **Save** (⌘S) to the library, or **Export** an annotated PDF, Markdown notes, or a formatted notes PDF.

Built-in note templates: Cornell, Outline, Key terms + summary, Study guide / Q&A.
Built-in highlight styles: Color-coded study, Margin commentary, Literary analysis.
To make your own, go to Settings → *Highlight Styles* / *Note Templates* and choose **Duplicate**.

Data lives in `~/Library/Application Support/AIAnnotator/` (`Library/` for readings, `Presets/` for custom styles).

## How it works

- `AnnotatorCore` holds all the logic (unit-tested); `AIAnnotator` is the SwiftUI app.
- For each page the model gets the page image plus the page text split into **numbered sentences**, and returns JSON
  constrained by a schema (Ollama's `format`). Each highlight names a sentence and an **exact quote** inside it, with an
  importance from 1 to 3. `QuoteMatcher` finds the quote within that sentence (tolerating whitespace, ligatures, curly
  quotes and hyphenation), and PDFKit provides the precise word positions. The model never guesses coordinates.
- `HighlightPlanner` then decides what is kept: most important first, at most one highlight per sentence, no overlaps,
  3–24 words each, and within the density budget (a share of the page's words and a per-page cap). Models
  over-highlight, so the app enforces these limits itself rather than trusting the prompt.
- Highlight line boxes are trimmed so stacked lines never overlap and darken.
- Highlights are standard PDF annotations, so they show up and can be edited in Preview and other PDF apps.
- Notes are built in two passes: a per-page digest, then one call that fills the chosen template. The result is
  Markdown, which is what you edit and what the exporters read.

## Tests

```bash
./scripts/test.sh                   # unit tests
OLLAMA_E2E=1 ./scripts/test.sh      # plus a real run against Ollama (OLLAMA_MODEL to override)

# Highlight chosen pages of any PDF and print what was kept, dropped and missed:
OLLAMA_E2E=1 OLLAMA_E2E_PDF=~/Downloads/book.pdf OLLAMA_E2E_PAGES=100,101 OLLAMA_E2E_DENSITY=balanced \
  ./scripts/test.sh --filter highlightsRealPages
```

Building with only the Command Line Tools needs two workarounds, both handled here: `ViewState` aliases SwiftUI's
`State` wrapper because the `@State` macro plugin ships only with Xcode, and `test.sh` points the compiler at the
Swift Testing macro plugin.
