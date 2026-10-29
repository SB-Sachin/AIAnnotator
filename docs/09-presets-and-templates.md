# 9. Presets & templates

[← 8 Ollama integration](08-ollama-integration.md) · [Docs index](README.md) · Next: [10 Library & storage →](10-library-and-storage.md)

Code: [`BuiltIns.swift`](../Sources/AnnotatorCore/BuiltIns.swift), [`Models.swift`](../Sources/AnnotatorCore/Models.swift),
[`Stores.swift`](../Sources/AnnotatorCore/Stores.swift) (`PresetStore`),
[`SettingsView.swift`](../Sources/AIAnnotator/SettingsView.swift) (the editors)

There are two kinds of preset:

- **Highlight styles** (`HighlightPreset`): what to highlight, in which colors, and whether to comment.
- **Note templates** (`NoteTemplate`): the shape of the notes.

Built-ins are defined in code, can't be edited, and always come first in lists. Your own are JSON files you create by
duplicating a built-in in Settings.

## Anatomy of a highlight style

| Field | Meaning | Where it's used |
|-------|---------|-----------------|
| `id` | stable identifier (`color-coded-study`, or `custom-<uuid>` for yours) | remembered "last style"; files |
| `name` | shown in pickers, saved with each reading | run/redo sheet, reading subtitle |
| `summary` | one-line description | style cards |
| `instructions` | free text added to the prompt | [the prompt](05-highlighting-pipeline.md#step-2-the-prompt) |
| `categories` | the colors: `id`, `name`, `colorHex`, `description` | prompt category list, schema enum, colors, list chips |
| `marginStyle` | `none` (No comments), `popup` (Comment on hover), `margin` (Visible margin notes) | the note rule in the prompt; [how notes are drawn](05-highlighting-pipeline.md#margin-notes-addmarginnote) |
| `maxPerPage` | upper limit per page (1–25 in the editor) | combined with the density budget; can only lower it |
| `isBuiltIn` | locks editing | Settings |

## Built-in highlight styles

### Color-coded study (`color-coded-study`)

*Main ideas, definitions, examples and names/dates in four colors.* · Comments: **on hover** · Max per page: **10**

> Highlight the passages a strong student would mark while studying this for a test. Focus on the central ideas of the
> page, the definitions of terms, the examples or evidence that support them, and important names, dates and numbers.

| Id | Name | Color | What it marks |
|----|------|-------|---------------|
| `main` | Main idea | `#FFE066` yellow | Thesis statements, central claims, topic sentences, conclusions. |
| `definition` | Definition | `#8CE99A` green | A term being defined or explained. |
| `example` | Example / evidence | `#74C0FC` blue | Examples, data, experiments, quotations or evidence supporting an idea. |
| `fact` | Name / date / number | `#F783AC` pink | Key people, places, dates, statistics and formulas worth memorizing. |

### Margin commentary (`margin-commentary`)

*Light highlights with short notes in the margin, like an annotated copy.* · Comments: **visible margin notes** ·
Max per page: **6**

> Annotate like a thoughtful reader writing in the margins. Mark the claims that carry the argument, the evidence
> behind them, and places that raise a question or connect to something earlier. Every highlight must have a useful
> margin note: name what the passage is doing (e.g. "thesis", "counterargument", "key evidence"), or ask the question
> it raises.

| Id | Name | Color | What it marks |
|----|------|-------|---------------|
| `claim` | Claim | `#FFD43B` yellow | The argument or main point being made. |
| `evidence` | Evidence | `#74C0FC` blue | Support for a claim: data, examples, sources. |
| `question` | Question / connection | `#B197FC` violet | Something confusing, debatable, or linked to another part of the reading. |

### Literary analysis (`literary-analysis`)

*Themes, symbols, literary devices and tone for English and history readings.* · Comments: **visible margin notes** ·
Max per page: **7**

> Read this like an English or history student preparing for an analytical essay. Mark passages that develop themes,
> use symbolism or imagery, employ literary or rhetorical devices, or reveal tone, character or the author's purpose.
> Margin notes should name the theme/device and briefly say why it matters.

| Id | Name | Color | What it marks |
|----|------|-------|---------------|
| `theme` | Theme | `#B197FC` violet | Develops a central theme, message or idea of the work. |
| `symbol` | Symbol / imagery | `#63E6BE` teal | Symbolism, motifs, vivid imagery. |
| `device` | Literary device | `#F783AC` pink | Metaphor, irony, foreshadowing, allusion, rhetorical appeals, etc. |
| `tone` | Tone / character | `#FFA94D` orange | Reveals tone, mood, voice, characterization or the author's purpose. |

All colors are drawn at 45 % opacity on the page, so text stays readable.

## Anatomy of a note template

| Field | Meaning |
|-------|---------|
| `id`, `name`, `summary`, `isBuiltIn` | as for styles |
| `instructions` | free text added to the notes prompt |
| `layout` | `cornell` (cues + notes + summary) or `sections` |
| `sections` | for `sections` layout: an ordered list of `{title, guidance}`; empty means "the model picks headings that mirror the reading" |

## Built-in note templates

| Template | Layout | Sections | Instructions |
|----------|--------|----------|--------------|
| **Cornell notes** (`cornell`) | Cornell | — | Write Cornell notes. Each cue should be a question or keyword a student can cover the notes with and quiz themselves on. Notes answer the cue in short bullet points. |
| **Outline** (`outline`) | Sections | chosen by the model | Write a hierarchical outline of the reading. Top-level bullets are major ideas; nested bullets (level 1, 2) hold supporting details, examples and evidence. Keep bullets short. |
| **Key terms + summary** (`key-terms`) | Sections | Key Terms · Summary · Main Takeaways | Focus on vocabulary and the big picture. |
| **Study guide / Q&A** (`study-guide`) | Sections | Practice Questions · Flashcards · Summary | Write a study guide a student could use the night before a test. |

Section guidance for the two fixed-section templates:

| Template | Section | Guidance given to the model |
|----------|---------|-----------------------------|
| Key terms + summary | Key Terms | Each item is "**Term** — definition in plain words". Include every important term. |
| | Summary | One item: a 4–6 sentence paragraph summarizing the whole reading. |
| | Main Takeaways | 3–6 items, the most important things to remember. |
| Study guide / Q&A | Practice Questions | 6–12 items formatted "**Q:** question **A:** answer". Mix recall and understanding questions. |
| | Flashcards | Items formatted "**Front** — back" for terms, people, dates and concepts. |
| | Summary | One item: a short paragraph tying the reading together. |

The Cornell layout's own rules (5–12 rows, 1–5 bullets, no repeated cues, a 3–5 sentence summary) come from the layout
guide in [7](07-notes-pipeline.md#layout-guides-and-schemas), so a custom Cornell template gets them too.

## Making your own

In **Settings → Highlight Styles** or **Note Templates**:

1. Select any style or template. Built-ins show a lock and their fields are read-only.
2. Click **Duplicate**. A copy named "… (Copy)" with a new `custom-<uuid>` id is created, saved and selected.
3. Edit it:
   - **Styles:** name, description, comments (No comments / Comment on hover / Visible margin notes), "At most N
     highlights per page" (1–25), instructions for the model, and colors. For each color: a color well, a name, and
     "what to highlight in this color". **Add Color** adds one; the minus button removes one (at least one must remain).
   - **Templates:** name, description, layout, instructions, and for Sections an ordered list of headings, each with
     "what goes in this section". Add and remove sections as needed.
4. Click **Save**. **Delete** removes your own style or template.

Your styles and templates then appear in the run and redo sheets alongside the built-ins, sorted by name.

### Category ids

When a style is saved, each category's id is rebuilt from its name: lowercase, letters and digits kept, everything else
becomes `-`, repeated dashes collapsed (`Name / date` → `name-date`). Duplicates get `-2`, `-3`, and an empty result
becomes `category`. Ids are what the model writes in `"category"` and what the schema's enum allows, so they must be
unique and stable.

Highlights store the category **name** in their `contents`, not the id. Renaming a category in a style doesn't break
existing highlights' colors; the list falls back to matching by nearest color
([5](05-highlighting-pipeline.md#the-highlights-list-annotationindex)).

## The JSON format

Custom presets are stored in `~/Library/Application Support/AIAnnotator/Presets/`:

- `highlights/<id>.json`
- `templates/<id>.json`

Pretty-printed with sorted keys. An example style:

```json
{
  "categories" : [
    { "colorHex" : "#FFE066", "description" : "The single most important claim on the page.",
      "id" : "big-idea", "name" : "Big idea" },
    { "colorHex" : "#74C0FC", "description" : "Numbers, dates and statistics.",
      "id" : "data", "name" : "Data" }
  ],
  "id" : "custom-6f1c…",
  "instructions" : "Highlight like an AP Biology student reviewing for a unit test.",
  "isBuiltIn" : false,
  "marginStyle" : "popup",
  "maxPerPage" : 5,
  "name" : "AP Bio review",
  "summary" : "Big ideas and data only."
}
```

You can write these files by hand (for example, to share a style). Files that fail to decode are skipped silently.
`marginStyle` is `none`, `popup` or `margin`; a template's `layout` is `cornell` or `sections`.

## Writing good instructions

The instructions are pasted into the prompt as-is ([5](05-highlighting-pipeline.md#step-2-the-prompt)). What works:

- Say **who** is reading and **why** ("a student reviewing for a unit test on cell biology").
- Describe **what deserves a highlight**, not how many: the density setting handles amount.
- Make category descriptions **distinct**. If two could describe the same passage, the model splits them arbitrarily.
- Keep category names short; they appear on chips and in the list.
- For margin notes, say what a useful note does ("name the rhetorical move", "ask the question it raises").
