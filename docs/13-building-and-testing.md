# 13. Building & testing

[← 12 Design system](12-design-system.md) · [Docs index](README.md) · Next: [14 Design decisions & history →](14-design-decisions.md)

## Requirements

- macOS 14 or later, ideally on Apple silicon (for model speed).
- Swift 6 toolchain. **Full Xcode is not required**: Apple's Command Line Tools are enough (`xcode-select --install`).
- [Ollama](https://ollama.com) with a model, for running the app and the opt-in real-model tests.

## Building

```bash
./scripts/build-app.sh          # release build → build/AIAnnotator.app
open build/AIAnnotator.app
```

[`scripts/build-app.sh`](../scripts/build-app.sh):

1. `swift build -c release`.
2. Creates `build/AIAnnotator.app/Contents/{MacOS,Resources}` and copies in the binary and `Resources/AppIcon.icns`.
3. Writes `Info.plist`:

   | Key | Value |
   |-----|-------|
   | `CFBundleName`, `CFBundleDisplayName` | AI Annotator |
   | `CFBundleIdentifier` | `com.sbsachin.aiannotator` |
   | `CFBundleExecutable` | `AIAnnotator` |
   | `CFBundleIconFile` | `AppIcon` |
   | `CFBundleShortVersionString` / `CFBundleVersion` | `0.1.0` / `1` |
   | `LSMinimumSystemVersion` | `14.0` |
   | `LSApplicationCategoryType` | `public.app-category.education` |
   | `NSHighResolutionCapable` | yes |
   | `NSAppTransportSecurity → NSAllowsLocalNetworking` | yes, which allows plain `http://` to Ollama on localhost |

4. Signs the bundle ad hoc (`codesign --force --sign -`), enough to run on your own Mac.

During development you can also run the executable directly with `swift run AIAnnotator`. An app delegate switches it
to a regular foreground app, which a bare executable otherwise isn't.

You may see linker warnings like `search path '/Library/Developer/CommandLineTools/Developer/Library/Frameworks' not
found`. They're harmless: those paths only exist with full Xcode.

### Building without Xcode

Two Swift features are implemented as compiler plugins (macros) that only ship with full Xcode in this SDK:

| Problem | Workaround |
|---------|------------|
| SwiftUI's `@State` is a macro in the macOS 27 SDK; its plugin isn't in the Command Line Tools, so `@State` fails to compile. | [`ViewState.swift`](../Sources/AIAnnotator/ViewState.swift) defines `typealias ViewState<Value> = SwiftUI.State<Value>`, and views use `@ViewState`. That uses `State` as an ordinary property wrapper, with identical behavior. |
| Swift Testing's `@Test` / `#expect` macros: the plugin exists in the Command Line Tools but isn't on the default search path. | [`scripts/test.sh`](../scripts/test.sh) runs `swift test` with `-Xswiftc -plugin-path` pointing at `…/usr/lib/swift/host/plugins/testing`. |

One more limitation: nested `#require` macros (`try #require(X(try #require(y)))`) fail to expand. The tests split
them into two statements.

### Regenerating the icon

```bash
swift scripts/make-icon.swift
```

Writes `Resources/AppIcon.icns` and `Resources/AppIcon.png`. See [12](12-design-system.md#the-app-icon).

## Testing

```bash
./scripts/test.sh                          # all unit tests (no Ollama needed)
./scripts/test.sh --filter QuoteMatcher    # one suite (any swift test arguments work)
```

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) and cover `AnnotatorCore` only: the UI is checked
by running the app (below).

### The test suites (38 tests)

| Suite | Tests | What it covers |
|-------|-------|----------------|
| [`QuoteMatcherTests`](../Tests/AnnotatorCoreTests/QuoteMatcherTests.swift) | 10 | Every normalization rule, the ellipsis and fuzzy steps, UTF-16 ranges, quotation marks. See [6](06-quote-matching.md#tests). |
| [`HighlightPlannerTests`](../Tests/AnnotatorCoreTests/HighlightPlannerTests.swift) | 8 | Overlaps keep the more important; one per sentence; density budgets scale with page length; the named sentence wins; over-long quotes dropped; sentence numbering across PDF line breaks; fuzzy length check; separating stacked line boxes. |
| [`HighlightPlacementTests`](../Tests/AnnotatorCoreTests/HighlightPlacementTests.swift) | 3 | Highlights and margin notes on a real PDF, surviving save/reload with exact read-back text; OCR of a synthetic photo; a **tilted photo** gets properly spaced text and line-sized highlight boxes. |
| [`NotesTests`](../Tests/AnnotatorCoreTests/NotesTests.swift) | 6 | Cornell Markdown round-trips through `CornellLayout`; section nesting; the parser; bold runs; the notes PDF contains the text; long notes paginate. |
| [`PromptTests`](../Tests/AnnotatorCoreTests/PromptTests.swift) | 5 | The schema matches the mode; categories are restricted to the style; template sections appear in the notes prompt; replies decode; custom presets save and delete. |
| [`RedoTests`](../Tests/AnnotatorCoreTests/RedoTests.swift) | 4 | Clearing generated annotations keeps yours; the "made by you" flag persists; digests and old readings load; re-reading a photo page. See [11](11-redo-and-undo.md#tests). |
| [`OllamaEndToEndTests`](../Tests/AnnotatorCoreTests/OllamaEndToEndTests.swift) | 2 | Opt-in runs against a real model, below. Skipped unless enabled. |

The tilted-photo test was written to fail on the old OCR code (glued words, giant boxes) and pass on the new; it was
checked both ways. See [14](14-design-decisions.md#photos-made-paragraph-sized-blobs).

### Real-model tests

These need Ollama running and talk to a real model, so they are **off by default**.

```bash
OLLAMA_E2E=1 ./scripts/test.sh
```

`highlightsAndNotesFromAPage` renders a small textbook page about cells, asks the model for highlights and a digest
(with the page image), places the highlights (expects at least 2), writes Cornell notes from the digest, and saves
`annotated.pdf` and `notes.pdf` to `$TMPDIR/aiannotator-e2e/`. It prints what the model suggested, placed, dropped and
missed.

#### Real-reading tests

`highlightsRealPages` runs the full highlight pipeline on **your own** files and prints a per-page report:

```bash
# Pages of a PDF
OLLAMA_E2E=1 OLLAMA_E2E_PDF=~/Downloads/book.pdf OLLAMA_E2E_PAGES=100,101 OLLAMA_E2E_DENSITY=balanced \
  ./scripts/test.sh --filter highlightsRealPages

# A folder of page photos (goes through the same OCR as the app)
OLLAMA_E2E=1 OLLAMA_E2E_PDF=~/Desktop/photos/ OLLAMA_E2E_PRESET=1 \
  ./scripts/test.sh --filter highlightsRealPages
```

| Variable | Meaning | Default |
|----------|---------|---------|
| `OLLAMA_E2E` | must be `1` to enable the suite | — |
| `OLLAMA_MODEL` | model to use | `gemma3:12b` |
| `OLLAMA_E2E_PDF` | a PDF, or a folder of page photos | — |
| `OLLAMA_E2E_PAGES` | 1-based pages of the PDF, comma-separated | `1` |
| `OLLAMA_E2E_DENSITY` | `light`, `balanced` or `thorough` | `light` |
| `OLLAMA_E2E_PRESET` | index of the built-in style: 0 Color-coded, 1 Margin commentary, 2 Literary | `0` |

The output looks like this (values vary from run to run):

```
Page 100: 481 words, 26 sentences. Model suggested 6; placed 5, dropped 1, missed 0. Highlighted 59 words (12%).
   text: Rhode Island One well-respected Puritan minister who moved from England to Boston was Roger Williams…
   • [2 boxes, tallest 13pt] the individual's conscience was beyond the control of any civil or church authority
   • [1 box, tallest 13pt] founded the community of Providence in 1636
   ✗ missed: …
```

The annotated pages are written to `$TMPDIR/aiannotator-e2e/real.pdf`. The per-highlight box count and height make
oversized highlights obvious at a glance. This is the tool used to tune the prompt and budget against real textbooks
and photos.

## Checking the UI

The UI isn't covered by automated tests. Changes were checked by building the app, running it, and looking at
screenshots of each screen (home, run sheet, reading screen, redo sheet), including a full run and redo against
gemma3:12b. When the display was asleep, the app was briefly given a temporary launch hook that saved snapshots of its
own windows (`NSView.cacheDisplay`). Those hooks were removed before committing and aren't part of the codebase.
