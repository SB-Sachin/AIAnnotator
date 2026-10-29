# 11. Redo & undo

[← 10 Library & storage](10-library-and-storage.md) · [Docs index](README.md) · Next: [12 Design system →](12-design-system.md)

Code: [`RedoSheet.swift`](../Sources/AIAnnotator/RedoSheet.swift), `Session.redo`, `Session.perform` and
`Session.undoRedo` in [`Session.swift`](../Sources/AIAnnotator/Session.swift), `PDFHighlighter.removeGenerated` in
[`PDFHighlighter.swift`](../Sources/AnnotatorCore/PDFHighlighter.swift)

A reading isn't fixed once it's made. **Redo** re-runs its highlights or its notes, optionally with a different
style, density, template or model, and **Undo Last Redo** brings the previous version back.

## Where to find it

- The **Redo ▾** button in the reading's header: *Redo Highlights…*, *Redo Notes…* (shown as *Add Highlights…* /
  *Add Notes…* when the reading has none), and *Undo Last Redo* after a redo.
- The **Reading** menu: Redo Highlights… (⇧⌘R), Redo Notes… (⌥⌘R), Undo Last Redo.
- An **Undo** button in the "Done" status pill right after a redo.

Redo is disabled while a run is in progress.

## The redo sheet

A switch at the top chooses **highlights** or **notes**.

| For highlights | For notes |
|----------------|-----------|
| Highlight style (preselected: the reading's current style) | Note template (preselected: the current template) |
| How much to highlight (preselected: the reading's density) | |
| *Re-read photographed pages* (only for older readings, see below) | |
| Model (preselected: the reading's model if installed, else the default) | Model |

A note under the options says exactly what will happen, for example "Replaces the current AI highlights on every page.
Highlights you added yourself are kept." or "Uses the pages already read, so it takes under a minute."

## Redoing highlights

For each page, in order:

1. **Clear generated annotations** (`removeGenerated`): every annotation whose author is `AIAnnotator` **and** that
   isn't marked as yours (`/AIManual`) is removed. That covers AI highlights, margin notes, sticky-note icons and the
   popups PDFKit attaches to sticky notes.
2. **Keep yours.** Highlights you made by selecting text stay, with their colors and notes.
3. **Highlight again** with the new style and density. The normal pipeline runs ([5](05-highlighting-pipeline.md)),
   and new highlights are never drawn over existing ones, so yours are never covered.

The reading's style and density are updated, and the highlights list refreshes page by page as it goes.

If the reading also has notes, a highlights redo **doesn't touch them**, or the saved digests.

## Redoing notes

Notes are written from per-page digests ([7](07-notes-pipeline.md)). The redo checks whether the reading has
**saved digests for every page**:

- **Yes:** no page is read. One notes call with the chosen template, typically **under a minute**. Switching Cornell →
  Outline → Study guide is fast.
- **No** (the reading was highlights-only, or was made before digests were saved): each page is read once to make a
  digest, then the notes call. Those digests are saved, so the next notes redo is fast.

The reading's template is updated, its mode becomes *Both* if it had only highlights, and the side panel switches to
**Notes**.

Highlights are **not touched** by a notes redo.

## Re-reading photographed pages

Readings made from photos before the photo fix ([14](14-design-decisions.md#photos-made-paragraph-sized-blobs)) have a
poor text layer: words glued across lines and oversized boxes. Redoing their highlights with that text would give
the same bad shapes. So for **older readings** (those without a recorded list of photo pages), the highlights redo
sheet offers **Re-read photographed pages**:

- For each page, the page is rendered without annotations, run through the current OCR process (straighten, recognize,
  word-by-word text layer), and **replaces** the old page ([4](04-ingest-and-ocr.md#re-reading-a-photo-page-rereadphotopage)).
- Because the page is replaced, **all** annotations on it are replaced, including any you made yourself.
- An older reading doesn't record which pages were photos, so with the switch on, **every** page is re-read. That's
  right for a photo reading. For a digital PDF it would replace crisp vector pages with rendered images, so leave the
  switch off for those; it's off by default.

New readings record their photo pages (`photoPages`), already have a good text layer, and don't show the switch.

## Undo Last Redo

Right before a redo starts, the session takes a **snapshot**:

| Saved in the snapshot |
|-----------------------|
| the whole PDF (`dataRepresentation()`), including all annotations |
| the notes Markdown |
| mode, model, highlight style, density, template name and layout |
| the saved digests |

**Undo Last Redo** restores all of it, saves the reading, and shows "Restored the previous version".

- There's **one level** of undo: the most recent redo. A second redo replaces the snapshot.
- The snapshot is kept **in memory**: it's gone after you close the reading or quit the app.
- Undo isn't available while a run is in progress. Stop the run first, then undo to go back to the version before it.

## Stopping a redo

**Stop** works as for a first run: the current request is cancelled, and the reading is saved as it is. A page's
generated highlights are cleared only when the redo **reaches** that page, so after a stop:

- pages already processed have their **new** highlights;
- the page that was in progress has had its old AI highlights cleared and no new ones yet;
- pages not reached still have their **old** highlights.

**Undo Last Redo** restores the old version of every page.

## Tests

`RedoTests` covers the core of this feature:

| Test | Checks |
|------|--------|
| `redoClearsGeneratedButKeepsReadersHighlights` | clearing removes AI highlights, margin notes and popups but keeps yours; a new AI pass won't draw over yours |
| `manualFlagSurvivesSaving` | the "made by you" flag survives saving and reopening |
| `digestsRoundTripAndOldReadingsStillLoad` | digests save and load; old `item.json` files without the new fields still load |
| `rereadsAPhotoPage` | re-reading a photo page produces correct text |

The full flow (redo highlights with re-read, redo notes without and then with saved digests, undo) was also run in the
app against gemma3:12b ([13](13-building-and-testing.md#checking-the-ui)).
