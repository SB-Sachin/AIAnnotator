# 6. Quote matching

[← 5 The highlighting pipeline](05-highlighting-pipeline.md) · [Docs index](README.md) · Next: [7 The notes pipeline →](07-notes-pipeline.md)

Code: [`Sources/AnnotatorCore/QuoteMatcher.swift`](../Sources/AnnotatorCore/QuoteMatcher.swift) ·
Tests: [`QuoteMatcherTests.swift`](../Tests/AnnotatorCoreTests/QuoteMatcherTests.swift)

The model returns a quote like `"the first written constitution in American history"`. To draw it, the app needs the
exact place in the page's text where those words are, as an `NSRange` that PDFKit's `page.selection(for:)` accepts.
`QuoteMatcher.find(_ quote:, in text:) -> NSRange?` does that.

It's harder than a plain substring search, because the quote and the page text rarely match character for character:

| Page text has… | Model writes… |
|----------------|---------------|
| a line break mid-sentence | a space |
| `con-`⏎`stitution` (hyphenated across lines) | `constitution` |
| `“Goodwife,”` (curly quotes) or OCR's `''Goodwife,''` | `Goodwife,` or `"Goodwife,"` |
| `—` or `–` (em/en dash) | `-` |
| the `ﬁ` ligature (one character) | `fi` |
| `…` (one character) | `...` |
| `Massachusetts` | `massachusetts` |

## How it works

### 1. Normalize both texts the same way

`normalize` walks the text one `Character` at a time and builds a simplified copy. For every character it keeps, it
also records where that character **started and ended in the original, in UTF-16 units**, so a match in the simplified
copy can be mapped back to the exact original range.

| Rule | Effect |
|------|--------|
| Hyphen or soft hyphen followed directly by a line break | dropped together with the break and any spaces after it (`con-`⏎`stitution` → `constitution`) |
| Other soft hyphens (U+00AD) | dropped |
| Any run of whitespace (spaces, tabs, line breaks) | one space; leading and trailing whitespace removed |
| Quotation marks and apostrophes: `' " ‘ ’ ‛ ` ′ “ ” ‟ ″ « »` | **dropped entirely** |
| Dashes: `‐ ‑ ‒ – — −` | `-` |
| Ligatures `ﬁ ﬂ ﬀ ﬃ ﬄ` | expanded to their letters |
| Ellipsis `…` | `...` |
| Everything else | lowercased |

Quotation marks are dropped rather than normalized because they are the most common source of mismatches: models
leave them out of quotes, and OCR reads them as `"`, `''`, `“` or even `ạ`. Dropping them on both sides makes
`gentleman, yeoman, or laborer` match `“gentleman,'' "yeoman," or “laborer`. Apostrophes go too (`individual’s` →
`individuals`), which is harmless because both sides lose them.

The normalized quote must be at least **3 characters**, or there's nothing to look for.

### 2. Exact match

The first occurrence of the normalized quote in the normalized page. This handles the large majority of quotes. The
result is the range from the original start of the first matched character to the original end of the last.

### 3. Ellipsis match

If the model shortened the quote with `...` (it's told not to, but sometimes does):

- split the quote at `...`, trim the pieces, keep pieces of at least 3 characters;
- with at least two pieces, find the **first piece**, then the **last piece** after it;
- return the range from the start of the first piece to the end of the last.

### 4. Fuzzy match

For quotes that differ slightly in the middle (an OCR typo, a changed word), and only for quotes of at least
**24 characters**:

1. Take a **head** and a **tail** anchor from the quote, each `min(30, max(12, length / 3))` characters long.
2. Find every place the head occurs; for each, look for the tail after it.
3. Accept a span only if its length is between **85 %** and **120 % + 4 characters** of the quote's length. A span
   that runs much longer is a different passage that happens to share the same words at its start and end.
4. Of all acceptable spans, return the one **closest in length** to the quote.

This length check was added after the first version, which accepted the first head with any tail within 1.3× the
length, and sometimes picked a wrong passage. See [14](14-design-decisions.md#loose-fuzzy-matching).

### 5. No match

Return `nil`. The planner records the quote as *missed* and draws nothing. See
[5](05-highlighting-pipeline.md#1-locate-each-quote).

## Where it is called from

The planner first calls `find` with **one sentence's text** (the sentence the model named), then, only if that fails,
with the **whole page**. Searching one sentence makes even the loose steps safe, and it removes ambiguity: a phrase
that appears five times on the page appears once in its sentence. A match inside the sentence is shifted by the
sentence's start to give a page range.

## Worked examples

**Hyphenation, line breaks and case**

```
page:   "Cell theory states that all living things are made of cells, that the cell is the basic unit of life, and that
         new cells arise only from exist-\ning cells."
quote:  "New cells arise only from existing cells"
normalized page:  "…and that new cells arise only from existing cells."
normalized quote: "new cells arise only from existing cells"     → exact match
```

**OCR quotation marks**

```
page:   "…identified by social order, as ''gentleman,'' \"yeoman,\" or “laborer,” or else…"
quote:  "gentleman, yeoman, or laborer"
normalized page:  "…as gentleman, yeoman, or laborer, or else…"   → exact match
returned range:   gentleman,'' "yeoman," or “laborer
```

**Rejected fuzzy match**

```
page:   "The cell membrane controls what enters the cell. Much later, after many unrelated words about other
         topics entirely, the cell wall gives structure."
quote:  "The cell membrane controls what gives structure."   (49 characters normalized)
anchors are min(30, max(12, 49 / 3)) = 16 characters:
  head "the cell membran" is found at the start of the page,
  tail "gives structure." is found only near the end, about 140 characters later;
  the span is far longer than 1.2 × 49 + 4 = 62 characters → rejected → nil
```

## Why ranges are in UTF-16

`NSString`, `NSRange` and PDFKit count in UTF-16 code units, while Swift `String` counts grapheme clusters. An emoji
or an accented letter written as two code points can make these differ. The normalizer records each original
character's UTF-16 offsets as it goes (`c.utf16.count`), so the returned range is correct for PDFKit even when the text
has such characters. The test `rangesAreUTF16ForEmojiAndAccents` covers this.

## Tests

| Test | Checks |
|------|--------|
| `exactMatch` | plain substring |
| `ignoresLineBreaksAndSpacing` | newlines and repeated spaces |
| `normalizesCurlyQuotesAndDashes` | curly quotes and em dashes vs. straight ones |
| `joinsHyphenatedLineBreaks` | `exist-⏎ing` = `existing` |
| `handlesLigatures` | `ﬁ` = `fi` |
| `ellipsisSpansFirstToLastFragment` | `a ... b` spans from a to b |
| `fuzzyToleratesSmallMiddleDifferences` | a changed word in the middle still matches |
| `fuzzyMatchRejectsSpansOfWrongLength` (planner tests) | far-apart head and tail are rejected |
| `returnsNilWhenAbsent` | text that isn't there gives nil |
| `rangesAreUTF16ForEmojiAndAccents` | correct ranges around emoji and accents |
| `ignoresQuotationMarksTheModelLeftOut` | OCR `''…''` and mixed quotes vs. a quote without them |
