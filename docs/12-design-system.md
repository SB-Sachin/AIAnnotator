# 12. Design system

[← 11 Redo & undo](11-redo-and-undo.md) · [Docs index](README.md) · Next: [13 Building & testing →](13-building-and-testing.md)

Code: [`Theme.swift`](../Sources/AIAnnotator/Theme.swift) and the views in [`Sources/AIAnnotator`](../Sources/AIAnnotator),
the icon in [`scripts/make-icon.swift`](../scripts/make-icon.swift)

## Direction

The look is meant to be calm and focused, in the spirit of apps like Wispr Flow: warm off-white surfaces instead of
stark white, soft cards with hairline borders, rounded type, pill-shaped controls, generous spacing, and one confident
accent color. The palette comes from the app icon: **indigo** with a **gold** sparkle. Highlight colors are the only
other strong colors, so the reading itself stays the focus.

Everything adapts to Light and Dark mode through dynamic colors.

## Color tokens (`Theme`)

| Token | Light | Dark | Used for |
|-------|-------|------|----------|
| `brand` | `#5B4BD6` | same | accent: selection, tint, links, the selected-highlight outline |
| `brandDeep` | `#3A2E9C` | same | deep indigo (icon background) |
| `gold` | `#FFB547` | same | secondary accent (the photo icon on Home) |
| `brandGradient` | `#7B6CF0` → `#4F3FCC`, top-left to bottom-right | same | primary buttons, Export, the Redo sheet badge |
| `canvas` | `#F8F7F4` | `#1B1A1F` | window and panel backgrounds |
| `card` | `#FFFFFF` | `#26252C` | raised surfaces: cards, tiles, selected pills |
| `well` | `#EFEDE8` | `#141317` | inset fields (the note editor) |
| `hairline` | primary at 8 % opacity | same | card borders |
| `pdfBackground` | `#EDEBE6` | `#141317` | behind the PDF pages |

The whole app is tinted with `brand`, so system controls (toggles, progress bars, focus rings) match.

## Type

- **Display type** (`Theme.display(size, weight)`): SF Pro **Rounded**, semibold by default. Used for titles and
  headings: Home headline 30 pt, sheet titles 20 pt, the reading title 17 pt, the sidebar wordmark 15 pt, panel
  headings 15 pt.
- **Labels and controls:** SF Pro Rounded, 11.5–13 pt, medium or semibold.
- **Body text** (quotes, notes, descriptions): SF Pro, 11–14 pt.
- **Section labels** (`SectionLabel`): 10.5 pt semibold rounded, UPPERCASE, letter-spacing 0.8, secondary color.
- **Monospaced:** the Markdown editor and Ollama commands.

## Components

| Component | Look and behavior |
|-----------|-------------------|
| `card(radius, shadow:)` | `card` fill, continuous rounded corners (16 pt by default), a hairline border and a soft shadow (black 6 %, radius 12, 4 pt down). Used for tiles, list cards and the notes preview. |
| `PrimaryButtonStyle` | Capsule with the brand gradient, white semibold rounded label, a faint white inner border and an indigo glow. On hover the glow grows and it brightens slightly; when pressed it scales to 97 %; disabled is 45 % opacity. A `large` variant is used on Home. |
| `SoftButtonStyle` | Quiet capsule: primary color at 5 % (8 % hover, 12 % pressed). Cancel, Save, Retry, Dismiss, Stop. |
| `ChoiceCard` | Selectable tile with 12 pt corners. Selected: indigo 1.5 pt border and a light indigo fill. Hover: a stronger hairline. Used for every choice in the run and redo sheets. |
| `PillPicker` | Segmented control as a capsule: the selected option is a raised `card` capsule with a small shadow, animated with a quick spring. Used for density, Highlights/Notes, Preview/Edit, the redo kind. |
| `FlowLayout` | A SwiftUI `Layout` that places children left to right and wraps to new lines. Used for the category filter chips. |
| `Legend` | Category chips: color dot plus name on a tinted capsule. As buttons, they form the "Highlight as" bar. |
| `CategoryDot` | A small color circle with a faint outline. |
| `BrandMark` | The app icon at any size. |
| `SidebarItem` | Icon tile plus title and subtitle; the selected row gets an indigo tint and indigo icon; hover gets a faint fill. |

## Screens

### Window
Hidden title bar (`.windowStyle(.hiddenTitleBar)`), with no sidebar toggle. The split view's sidebar is 220–320 pt wide
(250 ideal). Minimum window size 1040 × 680.

### Home
A centered column, at most 620 pt wide: the icon at 72 pt with an indigo glow, the headline, a subtitle, the **drop
card** (22 pt corners; while dragging it shows a dashed indigo border, an indigo glow behind it and grows 1.5 % with a
spring), three **feature tiles** of equal height, and a **Recent** grid of up to six cards that lift slightly on hover.

### Run sheet and Redo sheet
640 pt wide. A header (icon, title, file names), a scrollable body of labeled sections with `ChoiceCard` grids
(styles adapt to 170 pt minimum columns; templates in two columns), and a footer with the model picker, a hint,
**Cancel** and the primary action. Return starts, Escape cancels.

### Reading screen
- **Header:** title and subtitle on the left; *Unsaved*, **Redo ▾** (soft capsule), **Save** (soft) and **Export ▾**
  (gradient capsule) on the right.
- **Page area:** PDFKit view on the `pdfBackground` color; continuous scrolling; pages auto-scaled to fit.
- **Status pill:** floats 14 pt below the top edge, on a regular-material capsule with a shadow; slides in from the top.
  The sparkle pulses while working.
- **Selection bar:** floats 18 pt above the bottom while text is selected; slides up with a spring.
- **Inspector:** 330–560 pt (390 ideal) on the canvas color. A `PillPicker` switches Highlights/Notes. Highlight cards
  have a 4 pt category-color bar, the category in small secondary text, the quote in curly quotes, and the note with a
  speech-bubble icon. The selected card has an indigo border and shows the editor. Page headers stay pinned while
  scrolling.
- **Jump-to:** clicking a card scrolls the page to the highlight and draws a 2 pt indigo outline around it for 1.1 s.

### Settings
A standard macOS settings window with three tabs, tinted indigo. The editors use grouped forms.

## Motion

Short and functional: 0.12–0.15 s ease-out for hover states, a 0.2 s spring for pickers, 0.3–0.35 s springs for the
status pill, the selection bar and the drop card. Nothing loops except the progress sparkle's pulse while a run is
active.

## The app icon

Drawn entirely in code by `scripts/make-icon.swift` (run it with `swift scripts/make-icon.swift`); it writes
`Resources/AppIcon.icns` (all sizes from 16 to 1024 px) and `Resources/AppIcon.png`.

- An 824 pt rounded square (185 pt corner radius) on the standard 1024 macOS icon grid, with a soft drop shadow.
- An indigo gradient from `#7B6CF0` (top) to `#3A2E9C` (bottom), extended to the corners.
- A white page tilted 6° with seven text lines; three of them are highlighted in the Color-coded study yellow
  (`#FFE066`), green (`#8CE99A`) and blue (`#74C0FC`), with darker text bars on top.
- A gold four-point sparkle (gradient `#FFE066` → `#FF9F43`) with a white outline over the page corner, plus a small
  white sparkle: the "AI" in the name.

It was checked at 64 px, Dock size, to make sure it still reads clearly there.
