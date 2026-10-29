# AI Annotator

A small native Mac app that reads a PDF or photos of textbook pages with a **local Ollama model**
and produces study notes in a template, a highlighted and annotated copy of the pages, or both.
Nothing leaves your Mac. ([Overview →](docs/01-overview.md))

## Documentation

This README is the short version. **[`docs/`](docs/README.md) explains everything in depth**: how each part works, how
it's built, every feature and setting, and why it's designed that way.

| | |
|---|---|
| [1 Overview](docs/01-overview.md) | Goals, principles, the pipeline at a glance |
| [2 Using the app](docs/02-using-the-app.md) | Every screen, control and shortcut |
| [3 Architecture](docs/03-architecture.md) | Modules, every source file, data flow, concurrency |
| [4 Ingest & OCR](docs/04-ingest-and-ocr.md) | PDFs and photos, straightening, the word-level text layer |
| [5 Highlighting](docs/05-highlighting-pipeline.md) | Numbered sentences, prompts, the planner and its budget, drawing |
| [6 Quote matching](docs/06-quote-matching.md) | How quotes are found in page text |
| [7 Notes](docs/07-notes-pipeline.md) | Digests, templates, Markdown, the notes PDF |
| [8 Ollama](docs/08-ollama-integration.md) | API calls, options, errors, choosing a model |
| [9 Presets & templates](docs/09-presets-and-templates.md) | The built-ins in full, making your own |
| [10 Library & storage](docs/10-library-and-storage.md) | What's saved where |
| [11 Redo & undo](docs/11-redo-and-undo.md) | Redoing highlights and notes |
| [12 Design system](docs/12-design-system.md) | Colors, type, components, the icon |
| [13 Building & testing](docs/13-building-and-testing.md) | Building without Xcode, every test |
| [14 Design decisions & history](docs/14-design-decisions.md) | Why it's built this way, problems fixed |
| [15 Limitations & troubleshooting](docs/15-limitations-and-troubleshooting.md) | Known limits, fixes |

## Run it

```bash
./scripts/build-app.sh      # builds build/AIAnnotator.app (no Xcode needed)
open build/AIAnnotator.app
```

You need [Ollama](https://ollama.com) running with a model installed. The default is `gemma3:12b`, which can also look
at page images; switch models in Settings. While developing, `swift run AIAnnotator` also works.
More: [Building](docs/13-building-and-testing.md#building) · [Choosing a model](docs/08-ollama-integration.md#choosing-a-model)

## Using it

1. Drop a PDF, or several photos of pages. Photos are combined in filename order, straightened and OCR'd on-device.
   ([Ingest & OCR](docs/04-ingest-and-ocr.md))
2. Choose **Notes**, **Highlights** or **Both**, a highlight style, how much to highlight
   (**Light** ≈ 2–4 per page, **Balanced** ≈ 3–6, **Thorough** ≈ 5–9), a note template, and a model.
   ([The run sheet](docs/02-using-the-app.md#starting-a-reading-the-run-sheet))
3. Pages are processed one at a time (about 20–60 seconds each with gemma3:12b). Highlights appear as they're placed.
4. Review the result. The **Highlights** panel lists every highlight by page with its quote and note;
   filter by category, and click one to jump to it on the page.
   ([The reading screen](docs/02-using-the-app.md#the-reading-screen))
   - Select text on the page and pick a color to add your own highlight (it replaces any highlight under it).
   - Click a highlight, on the page or in the list, to recolor it, edit its note, or delete it.
   - Notes can be edited as Markdown.
5. Not happy with the result? **Redo** (in the reading's header, or the Reading menu) re-runs the highlights (⇧⌘R) or
   the notes (⌥⌘R), optionally with a different style, amount, template or model. Highlights you added yourself are
   kept, redoing notes reuses the pages already read, and **Undo Last Redo** brings back the previous version.
   ([Redo & undo](docs/11-redo-and-undo.md))
6. **Save** (⌘S) to the library, or **Export** an annotated PDF, Markdown notes, or a formatted notes PDF.
   ([Exporting](docs/02-using-the-app.md#exporting))

Built-in note templates: Cornell, Outline, Key terms + summary, Study guide / Q&A.
Built-in highlight styles: Color-coded study, Margin commentary, Literary analysis.
To make your own, go to Settings → *Highlight Styles* / *Note Templates* and choose **Duplicate**.
([Presets & templates](docs/09-presets-and-templates.md))

Data lives in `~/Library/Application Support/AIAnnotator/`: each reading keeps its annotated PDF, its notes, and the
per-page digests its notes were written from. ([Library & storage](docs/10-library-and-storage.md))

## How it works

- `AnnotatorCore` holds all the logic (unit-tested); `AIAnnotator` is the SwiftUI app.
  ([Architecture](docs/03-architecture.md))
- For each page the model gets the page image plus the page text split into **numbered sentences**, and returns JSON
  constrained by a schema. Each highlight names a sentence and an **exact quote** inside it, with an importance from
  1 to 3. The model never guesses coordinates. ([Highlighting](docs/05-highlighting-pipeline.md))
- `QuoteMatcher` finds the quote within that sentence, tolerating whitespace, quotation marks, ligatures and
  hyphenation, and PDFKit provides the precise word positions. ([Quote matching](docs/06-quote-matching.md))
- `HighlightPlanner` decides what is kept: most important first, at most one per sentence, no overlaps, 3–24 words
  each, and within the density budget. Models over-highlight, so the app enforces these limits itself.
  ([The planner](docs/05-highlighting-pipeline.md#the-planner))
- Photos are cropped and flattened like a scan, rotated level, and given an invisible OCR text layer laid out word by
  word, so highlights follow the printed lines. ([Photos](docs/04-ingest-and-ocr.md#photos-from-camera-image-to-searchable-page))
- Highlights are standard PDF annotations, so they show up and can be edited in Preview and other PDF apps.
  ([Inside the PDF](docs/10-library-and-storage.md#inside-the-pdf))
- Notes are built in two passes: a per-page digest, then one call that fills the chosen template. The result is
  Markdown, which is what you edit and what the exporters read. ([Notes](docs/07-notes-pipeline.md))

Why it's built this way, and the problems that shaped it: [Design decisions & history](docs/14-design-decisions.md).

## Tests

```bash
./scripts/test.sh                   # unit tests
OLLAMA_E2E=1 ./scripts/test.sh      # plus a real run against Ollama (OLLAMA_MODEL to override)

# Highlight chosen pages of any PDF (or a folder of photos) and print what was kept, dropped and missed:
OLLAMA_E2E=1 OLLAMA_E2E_PDF=~/Downloads/book.pdf OLLAMA_E2E_PAGES=100,101 OLLAMA_E2E_DENSITY=balanced \
  ./scripts/test.sh --filter highlightsRealPages
```

Building with only the Command Line Tools needs two workarounds, both handled here: `ViewState` aliases SwiftUI's
`State` wrapper because the `@State` macro plugin ships only with Xcode, and `test.sh` points the compiler at the
Swift Testing macro plugin. More: [Building & testing](docs/13-building-and-testing.md).

Trouble? See [Limitations & troubleshooting](docs/15-limitations-and-troubleshooting.md).
