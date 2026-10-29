# 10. Library & storage

[← 9 Presets & templates](09-presets-and-templates.md) · [Docs index](README.md) · Next: [11 Redo & undo →](11-redo-and-undo.md)

Code: [`Stores.swift`](../Sources/AnnotatorCore/Stores.swift), `ReadingItem` in
[`Models.swift`](../Sources/AnnotatorCore/Models.swift), `Session.save()` in
[`Session.swift`](../Sources/AIAnnotator/Session.swift)

## Where everything lives

```
~/Library/Application Support/AIAnnotator/
├── Library/
│   └── <reading id (UUID)>/
│       ├── item.json        what the reading is and how it was made
│       ├── document.pdf     the PDF, with every highlight and margin note as annotations
│       ├── notes.md         the notes (only if there are any)
│       └── digests.json     per-page digests the notes were written from (only if there are any)
└── Presets/
    ├── highlights/<id>.json your highlight styles
    └── templates/<id>.json  your note templates
```

Open this folder from **Settings → General → Library: Show in Finder**. Right-click a reading in the sidebar and choose
**Show in Finder** to reveal its `document.pdf`.

Plain files were chosen over a database on purpose: a reading is just a folder you can open, back up, copy to another
Mac, or inspect. The annotated PDF opens directly in Preview.

## `item.json`

```json
{
  "createdAt" : "2026-10-28T21:46:59Z",
  "density" : "light",
  "hasNotes" : true,
  "id" : "D846E22A-D334-4004-B1A2-ADE5239410EA",
  "mode" : "both",
  "model" : "gemma3:12b",
  "photoPages" : [ 0, 1, 2, 3, 4 ],
  "presetName" : "Margin commentary",
  "templateLayout" : "cornell",
  "templateName" : "Cornell notes",
  "title" : "colonial-social-ranks-historical-text (+4 pages)"
}
```

| Field | Meaning |
|-------|---------|
| `id` | the reading's UUID; also the folder name |
| `title` | the first file's name without its extension; for several photos, `"<first> (+N pages)"` |
| `createdAt` | when the reading was first made (ISO 8601); the library is sorted by it, newest first |
| `mode` | `notes`, `annotations` or `both`: what the reading currently contains. A redo can widen it, e.g. adding notes to a highlights-only reading makes it `both`. |
| `model` | the model used for the latest run |
| `presetName` | the highlight style's **name**; used to find the style's colors when the reading is reopened (falls back to the first built-in if it no longer exists) |
| `templateName`, `templateLayout` | the note template's name and layout; the layout decides how notes are previewed and exported |
| `hasNotes` | whether `notes.md` has content |
| `photoPages` | 0-based pages that came from photos. **Absent** for readings saved before this was recorded; see [11](11-redo-and-undo.md#re-reading-photographed-pages) |
| `density` | the last highlight density; preselected when redoing. Absent in older readings (treated as Balanced) |

Dates use ISO 8601; JSON is pretty-printed with sorted keys so files diff cleanly.

**Compatibility:** `photoPages` and `density` are optional. Older `item.json` files without them load fine; this is
tested by `digestsRoundTripAndOldReadingsStillLoad`.

## `document.pdf`

The reading's pages with all annotations, written with `PDFDocument.dataRepresentation()`. For a single-PDF reading
the pages are the original PDF's; for photos they're the generated pages ([4](04-ingest-and-ocr.md)).

### Inside the PDF

Highlights are standard PDF `/Highlight` annotations, so every PDF app shows them. The app also uses a few fields for
its own features:

| Field | On | Value | Purpose |
|-------|----|-------|---------|
| `/Contents` | highlights | `"Category"` or `"Category: note"` | category and note; shown by PDF apps as the comment |
| `/T` (author, `userName`) | everything the app draws | `"AIAnnotator"` | tells the app's own annotations apart from others |
| `/C` (color) | highlights | category color; PDFKit stores the 45 % opacity separately | |
| `/QuadPoints` | highlights | four points per line box | the exact highlighted shape |
| `/AIQuote` | highlights | the highlighted text | exact text for the highlights list, even on curved photo pages |
| `/AIManual` | your highlights | `"yes"` | marks highlights **you** made; a redo keeps them |
| — | margin notes | `/FreeText` annotations (or `/Text` sticky notes plus their `/Popup`) by `AIAnnotator` | |

`/AIQuote` and `/AIManual` are custom keys. PDF viewers ignore keys they don't know, so the file stays valid
everywhere, and PDFKit preserves them when saving (tested by `manualFlagSurvivesSaving` and the save/reload checks in
`placesHighlightsOnDigitalPDF`).

## `notes.md`

The notes Markdown exactly as shown in the editor ([7](07-notes-pipeline.md#from-json-to-markdown-notesformatter)).
Written only when notes exist.

## `digests.json`

```json
[
  { "digest" : { "key_points" : [ "Roger Williams founded Providence in 1636." ],
                 "summary" : "Founding of Rhode Island and Connecticut.",
                 "terms" : [ { "definition" : "Salvation through faith alone", "term" : "Antinomianism" } ] },
    "page" : 1 },
  …
]
```

One entry per page (1-based), saved after every run that reads pages for notes. It makes **Redo Notes** a single model
call ([11](11-redo-and-undo.md#redoing-notes)). The file is deleted when there are no digests.

## When things are saved

| Event | What's saved |
|-------|--------------|
| A run (first run or redo) ends: finished, stopped or failed | everything: `item.json`, `document.pdf`, `notes.md`, `digests.json` |
| **Save** (⌘S) | everything |
| Undo Last Redo | everything (the restored version) |
| Opening another reading, going Home, or starting a new reading with unsaved edits | the current reading is saved first, unless it's still running |

Edits (adding, recoloring, re-noting or deleting highlights; editing notes) mark the reading **Unsaved** until one of
these happens.

## Deleting

Right-click a reading → **Delete** removes its whole folder. If it's open, its run is cancelled and the app returns
Home. This can't be undone from the app.

## Preferences (UserDefaults)

| Key | Value |
|-----|-------|
| `defaultModel` | default model name (initially `gemma3:12b`) |
| `lastMode` | last run mode |
| `lastPreset` | last highlight style id |
| `lastTemplate` | last note template id |
| `lastDensity` | last density |

Stored in the app's defaults domain (`com.sbsachin.aiannotator` when run from the bundle).
