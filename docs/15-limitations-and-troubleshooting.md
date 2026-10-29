# 15. Limitations & troubleshooting

[← 14 Design decisions & history](14-design-decisions.md) · [Docs index](README.md)

## Known limitations

| Limitation | Why | What to do |
|------------|-----|------------|
| **Speed:** about 20–60 s per page with gemma3:12b | A 12B model running locally, one page at a time | Use Light (shorter replies), a smaller model (`gemma3:4b`), or start a long reading and let it run. Redoing notes reuses saved digests. |
| **Best for 1–20 pages** | Notes from 20 digests fit the 16K context; much longer readings may overflow it | Split long chapters into parts. |
| **Scanned PDFs with no text layer get no highlights** | A single PDF is used as is, with no OCR ([4](04-ingest-and-ocr.md#what-isnt-ocrd)) | Export the scan's pages as images and drop those in. |
| **Some suggested highlights are skipped** | A quote that can't be found in the page text is skipped, not guessed | Usually OCR errors on photos. Retake a clearer photo, or redo. |
| **Strongly curved pages** | Straightening is global; it can't uncurl a bent page | Press the page flat. Words still land where printed, but a highlight on a curve is a series of flat boxes. |
| **Handwriting** | Not a goal; Vision's results vary | — |
| **Multi-column layouts** | Text order follows the PDF's own order or Vision's line order, which can interleave columns | Highlights still land correctly (each quote is found where it is); notes may mix columns slightly. |
| **One level of undo, in memory** | Simple and reliable ([11](11-redo-and-undo.md#undo-last-redo)) | Export a copy first if you want to keep a version long-term. |
| **Re-reading photos on an older reading re-reads every page** | Older readings don't record which pages were photos | Leave the switch off for digital PDFs. |
| **Category matching after renaming a style's colors** | Highlights store the category name | The list falls back to the nearest color. Redo highlights to refresh. |
| **No automated UI tests** | The UI is checked by running the app | The logic in `AnnotatorCore` is covered by 38 tests. |

## Troubleshooting

### The orange banner says "Ollama isn't running"
Open the Ollama app (it lives in the menu bar), or run `ollama serve` in Terminal, then click **Retry**. The app expects
Ollama at `http://127.0.0.1:11434`.

### "… isn't installed"
The chosen model isn't in Ollama's list. Run the command shown in the banner, e.g.:

```bash
ollama pull gemma3:12b
```

Or pick an installed model in **Settings → General** or in the run sheet.

### Start or Redo is greyed out
The selected model isn't installed, Ollama isn't reachable, or (for Redo) a run is in progress.

### It's very slow, or the first page takes much longer
The first request loads the model into memory, which takes several seconds for a 12B model. After that it stays loaded
for 15 minutes (`keep_alive`). Close other memory-heavy apps; on 8 GB Macs, use a smaller model.

### "Ollama returned an unexpected response"
The model's reply didn't match the expected JSON even after one retry, or Ollama returned an error. Try again, or try
another model. The message includes the start of the reply, which helps diagnose it.

### Too many, or too few, highlights
Redo highlights (⇧⌘R) with another density: **Light** (≈ 2–4 per page), **Balanced** (≈ 3–6), **Thorough** (≈ 5–9).
A style's own "at most N per page" also caps it. See [5](05-highlighting-pipeline.md#the-density-budget).

### Highlights on photos look like big blocks
The reading was made before the photo fix. Redo highlights with **Re-read photographed pages** on
([11](11-redo-and-undo.md#re-reading-photographed-pages)), or drop the photos in again.

### A page has fewer highlights than expected
Some suggestions are skipped on purpose: quotes that can't be found in the page's text (usually OCR misreads on
photos), quotes under 3 or over 24 words, overlaps, and anything over the density budget. A skipped highlight is never
placed somewhere wrong. To see exactly what happened on a page, run the real-reading test on it
([13](13-building-and-testing.md#real-reading-tests)), which prints what was suggested, placed, dropped and missed.

### Margin notes overlap the page edge or show as an icon
There wasn't enough margin (at least 64 pt is needed for a visible note), so a sticky-note icon is used instead. Click
it, or read the note in the Highlights list.

### My own highlight disappeared after a redo
It shouldn't: highlights you make by selecting text are marked and kept. Two exceptions: **Re-read photographed pages**
replaces whole pages, and highlights made before the "made by you" marker existed (`e0beac1`) look like AI ones.
Use **Undo Last Redo**.

### Notes repeat the cue question, or the notes are off
Redo notes (⌥⌘R), possibly with another template or model. It's fast when the page digests are saved. You can also
edit the notes directly in **Edit** mode.

### Where are my files?
`~/Library/Application Support/AIAnnotator/`, or **Settings → General → Show in Finder**. See
[10](10-library-and-storage.md).

<a id="a-scanned-pdf-gets-no-highlights"></a>
### A scanned PDF gets no highlights
See the first table: export the pages as images and drop those in, so they go through OCR.

### Build errors about `@State` or `#expect` macros
You're building with the Command Line Tools only; use `@ViewState` and `scripts/test.sh`. See
[13](13-building-and-testing.md#building-without-xcode).
