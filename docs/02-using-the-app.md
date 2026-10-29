# 2. Using the app

[← 1 Overview](01-overview.md) · [Docs index](README.md) · Next: [3 Architecture →](03-architecture.md)

This chapter walks through every screen and control. For how each feature works underneath, follow the links.

## Before you start

1. Install [Ollama](https://ollama.com) and open it, so it's running in the menu bar.
2. Have at least one model installed. The default is `gemma3:12b`:
   ```bash
   ollama pull gemma3:12b
   ```
   Any installed model works. Models with *vision* (gemma3 is one) also see each page as an image, which helps with
   diagrams, tables and figures. See [8 Ollama integration](08-ollama-integration.md#vision).
3. Build and open the app (details in [13 Building & testing](13-building-and-testing.md)):
   ```bash
   ./scripts/build-app.sh && open build/AIAnnotator.app
   ```

If Ollama isn't running, or the chosen model isn't installed, an orange banner appears at the top of the window with
the fix (for a missing model it shows the exact `ollama pull …` command, which you can select and copy) and a
**Retry** button.

## The window

The window has a sidebar on the left and the main area on the right. The title bar is hidden for a cleaner look; the
traffic-light buttons sit over the sidebar. The minimum window size is 1040 × 680 points.

### Sidebar

- **AI Annotator** wordmark with the app icon.
- **New reading** (indigo button): opens a file chooser.
- **Home**: goes back to the home screen.
- **Library**: every reading you've processed, newest first. Each row shows an icon for what it contains (note page =
  notes, highlighter = highlights, sparkles = both), the title, and how long ago it was made. Click to open.
  Right-click for **Show in Finder** (reveals the reading's PDF) and **Delete** (removes the reading from the library
  for good).

### Home screen

- A headline, then a large **drop card**: drag files anywhere onto the main area, or click **Choose files**. The card
  glows and shows a dashed indigo border while you drag over it.
- Three tiles summarizing what the app does.
- **Recent**: up to six recent readings as cards; click to open.

Accepted files: PDFs and images (JPG, JPEG, PNG, HEIC, HEIF, TIFF, WebP, GIF, BMP). You can drop several at once.
Photos are combined **in filename order** (natural order, so `page2` comes before `page10`), and you can mix PDFs and
photos. See [4 Ingest & OCR](04-ingest-and-ocr.md).

## Starting a reading: the run sheet

After you choose files, a sheet asks what to make:

| Section | Choices | Notes |
|---------|---------|-------|
| **What should it make?** | Notes · Highlights · Both | Notes only skips highlighting; Highlights only skips notes. |
| **Highlight style** | Color-coded study · Margin commentary · Literary analysis · your own | Each card shows its colors as dots. See [9](09-presets-and-templates.md). |
| **How much to highlight** | Light · Balanced · Thorough | Light ≈ 2–4 per page, Balanced ≈ 3–6, Thorough ≈ 5–9. Enforced by the app, see [5](05-highlighting-pipeline.md#the-density-budget). |
| **Note template** | Cornell notes · Outline · Key terms + summary · Study guide / Q&A · your own | See [7](07-notes-pipeline.md) and [9](09-presets-and-templates.md). |
| **Model** (bottom left, chip icon) | Any installed Ollama model | Defaults to the model chosen in Settings. |

Click **Start** (or press Return). The app remembers your last choice of mode, style, density and template for next
time.

## While it runs

The reading opens right away. A floating **status pill** at the top of the page shows a pulsing sparkle, "Reading page
3 of 8…", a progress bar and a **Stop** button.

- Pages are read one at a time. **Highlights appear on each page as soon as it's done**, and the Highlights list fills
  in as you watch.
- Notes are written at the end, after every page has been read ("Writing Cornell notes…").
- **Stop** cancels. Pages already finished are kept and saved; the status says "Stopped. Pages finished so far are kept."
- When it finishes, the pill says "Done · 12 highlights on 5 pages" (or "Notes ready"), then disappears after 8 seconds.
- The reading is **saved to the library automatically** when a run ends.

## The reading screen

```
┌───────────────────────────────────────────────────────────────────────────┐
│ Title                                         [Redo ▾] [Save] [Export ▾]  │
│ Both · Color-coded study · Cornell notes · Oct 28, 2026                    │
├──────────────────────────────────────────────┬────────────────────────────┤
│            ( status pill )                   │ [ Highlights · 12 | Notes ]│
│                                              │ 12 highlights on 5 of 5 pp │
│                PDF pages                     │ (Main idea 4) (Definition 3)│
│                                              │ Page 1                      │
│                                              │ ┃ Main idea                 │
│                                              │ ┃ "quoted words…"           │
│         ( Highlight as: ● ● ● ● )            │ ┃ 💬 margin note            │
└──────────────────────────────────────────────┴────────────────────────────┘
```

### Header

- **Title** and a subtitle: what the reading contains · highlight style · note template · date.
- **Unsaved** appears when you've made changes that aren't saved yet.
- **Redo ▾**: Redo Highlights… / Redo Notes… (or *Add…* if the reading doesn't have them yet), and Undo Last Redo after
  a redo. See [11 Redo & undo](11-redo-and-undo.md).
- **Save**: saves edits to the library (⌘S). Disabled when there's nothing to save.
- **Export ▾**: Annotated PDF… · Notes as Markdown… · Notes as PDF…

### The page

The PDF with its highlights. Margin-commentary and literary styles also show **margin notes** next to highlights, in
whichever side margin has room. Where there's no room, a small sticky-note icon appears at the page edge instead.

- **Click a highlight** (or its margin note) to select it. The side panel jumps to it.
- **Select text** with the mouse and a floating **Highlight as** bar appears at the bottom with one button per color.
  Click one to highlight the selection. If your selection covers an existing highlight, the new one replaces it.
  Highlights you make this way are *yours*: a redo never removes them. See [11](11-redo-and-undo.md).

### The side panel: Highlights

Every highlight at a glance, in reading order:

- A count ("12 highlights on 5 of 5 pages").
- **Category chips** with counts, e.g. *Main idea 4*. Click a chip to hide or show that category; the chips wrap onto
  several lines when there are many.
- Highlights **grouped by page**, with a pinned "Page N" header as you scroll. Each card shows a color bar, the category,
  the exact highlighted words in quotes, and the margin note if there is one.
- **Click a card** to scroll the page to that highlight; it's briefly outlined in indigo so you can spot it.
- The selected card expands into an editor:
  - **Add a note** / edit the note (saved as you type; a visible margin note updates too).
  - **Color dots** to move it to another category.
  - **Trash** (also shown on hover) to delete it, together with its margin note.

### The side panel: Notes

Shown when the reading has notes. A **Preview / Edit** switch:

- **Preview** renders the Markdown. Cornell notes appear as a two-column table (cues left, notes right) with the
  summary below.
- **Edit** shows the raw Markdown in a monospaced editor. Changes mark the reading as unsaved.

When a reading has both highlights and notes, a switch at the top of the panel moves between them. The panel switches
to Highlights when you select a highlight, and to Notes when notes are rewritten.

## Exporting

| Export | What you get |
|--------|--------------|
| **Annotated PDF…** (⇧⌘E) | The PDF with every highlight and margin note as standard annotations. Opens in Preview, Acrobat, etc. |
| **Notes as Markdown…** | The notes exactly as shown in Edit mode (`.md`). |
| **Notes as PDF…** | A formatted US Letter PDF of the notes; Cornell notes get a real two-column layout. See [7](07-notes-pipeline.md#the-notes-pdf). |

## Settings (⌘,)

| Tab | What's there |
|-----|--------------|
| **General** | Default model (from Ollama's installed list), Ollama status with Refresh, a note on vision models, and **Show in Finder** for the app's data folder. |
| **Highlight Styles** | The style list (built-ins have a lock). Duplicate any style, then edit its name, description, comment style, per-page cap (1–25), model instructions, and colors (color, name, what to highlight). Save / Delete for your own styles. |
| **Note Templates** | The template list. Duplicate, then edit name, description, layout (Cornell or Sections), model instructions, and for Sections an ordered list of headings with guidance. |

Details in [9 Presets & templates](09-presets-and-templates.md).

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | New reading (back to Home) |
| ⌘O | Open files… |
| ⌘S | Save the current reading |
| ⇧⌘E | Export annotated PDF |
| ⇧⌘R | Redo highlights… |
| ⌥⌘R | Redo notes… |
| ⌘, | Settings |
| Return / Esc | Start / Cancel in sheets |

The **Reading** menu in the menu bar has Redo Highlights…, Redo Notes… and Undo Last Redo.

## Tips

- **Start with Light.** It's the default for a reason: a few precise highlights are easier to study from. Redo with
  Balanced or Thorough if you want more.
- **Margin commentary** is best when you want the *why*, not just the *what*: every highlight gets a short comment.
- **Photos:** lay the page flat, fill the frame, avoid strong shadows. The app straightens and crops, but blur and
  glare still hurt OCR. See [4](04-ingest-and-ocr.md) and [15](15-limitations-and-troubleshooting.md).
- **Switching note templates is cheap.** After the first notes run, Redo Notes with another template takes one model
  call. See [11](11-redo-and-undo.md#redoing-notes).
