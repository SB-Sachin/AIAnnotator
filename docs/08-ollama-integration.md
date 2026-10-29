# 8. Ollama integration

[← 7 The notes pipeline](07-notes-pipeline.md) · [Docs index](README.md) · Next: [9 Presets & templates →](09-presets-and-templates.md)

Code: [`Sources/AnnotatorCore/OllamaClient.swift`](../Sources/AnnotatorCore/OllamaClient.swift)

AI Annotator uses [Ollama](https://ollama.com) as its only model provider. Ollama runs models locally and serves a small
HTTP API on `http://127.0.0.1:11434`. The client is a plain `URLSession` wrapper with no SDK.

## Endpoints used

| Call | Endpoint | When | Timeout |
|------|----------|------|---------|
| `listModels()` | `GET /api/tags` | at launch, before a run or redo sheet opens, when you change the default model, on Retry/Refresh | 5 s |
| `supportsVision(model:)` | `POST /api/show` `{"model": …}` | once at the start of each run that reads pages | 10 s |
| `chat(…)` | `POST /api/chat` | once per page, plus once for notes | 600 s per request, 1,800 s total |

## The chat request

```json
{
  "model": "gemma3:12b",
  "messages": [
    { "role": "system", "content": "<task instructions>" },
    { "role": "user", "content": "<page text or digests>", "images": ["<base64 JPEG>"] }
  ],
  "stream": false,
  "format": { "<JSON Schema>": "…" },
  "keep_alive": "15m",
  "options": { "temperature": 0.2, "num_ctx": 8192 }
}
```

| Field | Value | Why |
|-------|-------|-----|
| `stream` | `false` | The reply is a single JSON object, only useful once complete. |
| `format` | a JSON Schema | Structured outputs, see below. |
| `keep_alive` | `"15m"` | Keeps the model loaded between pages and between runs, avoiding a reload (several seconds for a 12B model) on every page. |
| `temperature` | `0.2` | Low, so quotes are copied faithfully and results are consistent; a little variety helps the model avoid repeating itself. |
| `num_ctx` | `8192` per page, `16384` for notes | A page with its numbered sentences, instructions and image fits in 8K; all the digests for a 20-page reading fit in 16K. Ollama's default context is smaller and would silently cut the prompt. |
| `images` | one base64 JPEG, only for vision models | See [Vision](#vision). |

## Structured outputs

Ollama's `format` field accepts a JSON Schema and constrains generation so the reply always matches it. The app uses
this for every call: page results, digests, Cornell notes and section notes (schemas in
[5](05-highlighting-pipeline.md#step-3-the-schema-and-the-reply) and [7](07-notes-pipeline.md#layout-guides-and-schemas)).
Benefits:

- replies always parse, with no "extract the JSON from the prose" step;
- enums restrict values, so `category` can only be one of the style's ids and `importance` only 1, 2 or 3;
- `required` fields are always present.

Schemas constrain shape, not truth: the app still checks every quote against the page ([6](06-quote-matching.md)) and
enforces the budget ([5](05-highlighting-pipeline.md#the-planner)).

## Retries and errors

- `chat` decodes the reply into the expected Swift type. If decoding fails (rare with structured outputs, but possible
  if the model stops early), it **retries once**, then fails with the first 200 characters of the bad reply.
- HTTP **404** from `/api/chat` → `OllamaError.modelMissing`: "The model "…" isn't installed. Run `ollama pull …` in
  Terminal."
- Any other non-200 status → `OllamaError.badResponse` with the start of the body.
- Connection refused, host not found or connection lost → `OllamaError.notRunning`: "Can't reach Ollama. Open the
  Ollama app (or run `ollama serve`) and try again."
- Errors stop the run, appear in the status pill (selectable, with a Dismiss button), and the pages finished so far are
  kept and saved.

## Status checks and the banner

`AppModel.refreshOllama()` calls `listModels()`:

| Result | Status | Shown |
|--------|--------|-------|
| List returned, default model in it | `.ok` | nothing |
| List returned, default model missing | `.modelMissing(name)` | orange banner with `ollama pull <name>` |
| Request failed | `.notRunning` | orange banner: "Ollama isn't running" |

A model counts as installed if its name matches exactly or with `:latest` added, since Ollama lists `llama3` as
`llama3:latest`. The Start and Redo buttons stay disabled until the chosen model is installed.

## Vision

`supportsVision(model:)` asks `/api/show` for the model's details and checks whether its `capabilities` include
`"vision"`. If yes, every page request includes the page image (JPEG, longest side 1,200 px, see
[4](04-ingest-and-ocr.md#the-page-image-for-vision-models-pageimage)). If the call fails or the model has no vision,
requests are text-only.

What the image is for:

- **Digests** get information from diagrams, charts, tables and captions.
- **Highlights** get context about layout and emphasis (headings, bold terms, sidebars). The *position* of a highlight
  always comes from the text: the model quotes, the app locates. The image never decides where a highlight goes.

## Choosing a model

Any model Ollama has installed appears in the pickers. The default, `gemma3:12b`, was chosen in planning because it's
multimodal, follows structured-output instructions well, and runs comfortably on Apple-silicon Macs with 16 GB or more.

| If you want… | Try |
|--------------|-----|
| The default balance | `gemma3:12b` |
| Faster, lower quality | `gemma3:4b` (still has vision) |
| Better reasoning, slower, more memory | `gemma3:27b` |
| Text-only models | work, but don't see figures |

Change it per run in the run or redo sheet, or as the default in **Settings → General**.

## Performance notes

- Pages are processed **one at a time**, in order, so highlights appear as each page finishes and memory use stays flat.
  Ollama generally serves one request at a time per model anyway.
- With **Both**, highlights and the digest come from **one** call per page.
- Redoing notes **reuses saved digests**: one call, no page reading ([11](11-redo-and-undo.md#redoing-notes)).
- Measured with gemma3:12b on an Apple-silicon Mac: about 20–60 s per page; 5 photo pages of highlights in about
  1.5 minutes; one Cornell notes call from 5 saved digests in about 45 s.
