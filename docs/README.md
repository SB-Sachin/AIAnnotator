# AI Annotator — In-Depth Documentation

This folder explains how AI Annotator works, how it is built, and every feature it has, in as much detail as the
source code itself. The top-level [README](../README.md) is the short version; each section of it links here.

Everything in these pages was written from the code and checked against it. Constants and thresholds are quoted
exactly, and file references point to the file that implements the behavior, so you can read the docs and the source
side by side.

## Chapters

| # | Chapter | What it covers |
|---|---------|----------------|
| 1 | [Overview](01-overview.md) | What the app is, the goals behind it, design principles, and the whole pipeline at a glance |
| 2 | [Using the app](02-using-the-app.md) | Every screen, control, setting and keyboard shortcut |
| 3 | [Architecture](03-architecture.md) | Targets and modules, a tour of every source file, data flow, concurrency |
| 4 | [Ingest & OCR](04-ingest-and-ocr.md) | Opening PDFs, turning photos into searchable pages, straightening, the word-level text layer |
| 5 | [The highlighting pipeline](05-highlighting-pipeline.md) | Numbered sentences, the prompt, the planner and its budget, placing and drawing highlights |
| 6 | [Quote matching](06-quote-matching.md) | How a model's quote is found in page text: normalization, exact, ellipsis and fuzzy matching |
| 7 | [The notes pipeline](07-notes-pipeline.md) | Page digests, templates, the Markdown format, Cornell layout, the notes PDF |
| 8 | [Ollama integration](08-ollama-integration.md) | Every API call, option, timeout, retry and error |
| 9 | [Presets & templates](09-presets-and-templates.md) | All built-in styles and templates in full, the editors, the JSON format |
| 10 | [Library & storage](10-library-and-storage.md) | What is saved where, file formats, annotation keys, compatibility |
| 11 | [Redo & undo](11-redo-and-undo.md) | Redoing highlights and notes, what is kept and replaced, undo |
| 12 | [Design system](12-design-system.md) | Colors, type, components and the layout of every screen |
| 13 | [Building & testing](13-building-and-testing.md) | Building without Xcode, the scripts, every test, real-model test runs |
| 14 | [Design decisions & history](14-design-decisions.md) | Why things are built the way they are, and the problems that shaped them |
| 15 | [Limitations & troubleshooting](15-limitations-and-troubleshooting.md) | Known limits, common problems and their fixes |

## Reading paths

- **Just want to use it well:** [2 Using the app](02-using-the-app.md), then [9 Presets & templates](09-presets-and-templates.md)
  and [15 Troubleshooting](15-limitations-and-troubleshooting.md).
- **Want to understand why the highlights land where they do:** [5 Highlighting](05-highlighting-pipeline.md) →
  [6 Quote matching](06-quote-matching.md) → [4 Ingest & OCR](04-ingest-and-ocr.md).
- **Want to change the code:** [3 Architecture](03-architecture.md) → [13 Building & testing](13-building-and-testing.md) →
  [14 Design decisions](14-design-decisions.md), then the chapter for the area you're changing.

## Glossary

| Term | Meaning |
|------|---------|
| **Reading** | One document you processed: a PDF or a set of photos, with its highlights, notes and settings. Stored as a folder in the library. |
| **Run** | One pass of the model over a reading: highlights, notes, or both. A first run happens when you add a reading; later runs are redos. |
| **Highlight style** (*preset*) | A named set of highlight categories (colors), instructions for the model, a comment style and a per-page cap. `HighlightPreset` in code. |
| **Category** | One color in a style, such as "Main idea" (yellow) or "Evidence" (blue). `HighlightCategory`. |
| **Density** | How much to highlight: Light, Balanced or Thorough. Sets a budget the app enforces. `HighlightDensity`. |
| **Note template** | The shape of the notes: Cornell, Outline, Key terms + summary, Study guide, or a custom one. `NoteTemplate`. |
| **Digest** | A short structured summary of one page (summary, key points, terms) that notes are written from. `PageDigest`. |
| **Planner** | The code that decides which of the model's suggested highlights are kept. `HighlightPlanner`. |
| **Quote matching** | Finding the model's quoted words in the page's text. `QuoteMatcher`. |
| **Text layer** | The text a PDF page carries (selectable, searchable). Photos get an invisible one made by OCR. |
| **Margin note** | A short comment shown beside a highlight, in the page margin or as a sticky-note icon. |
| **Generated vs. your own highlights** | Highlights the AI made vs. ones you made by selecting text. A redo replaces only generated ones. |
