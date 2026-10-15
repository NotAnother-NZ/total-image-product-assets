# Single-image padding restoration test

Isolated proof of concept for the Total Image Webflow hero image **Men’s Derby**. It does not change any existing migration scripts or bulk-process other products.

## Target
- Product slug: `mens-derby`
- Images CMS item: `6ac69399d70193b11f7af706`
- Source asset ID: `6ac69399d70193b11f7af702`
- Source: https://cdn.prod.website-files.com/6a5cf9aea7826c08d8c44b43/6ac69399d70193b11f7af702_ROLLIE-DERBY_MENS_DERBY_BLACK.webp

## Setup

```bash
git fetch origin
git switch feat/image-padding-restoration-test
cd tools/image-padding
npm install
cp .env.example .env
```

Edit your untracked `.env`:

```dotenv
OPENAI_API_KEY=your_key
WEBFLOW_API_TOKEN=your_webflow_site_token
OPENAI_IMAGE_MODEL=gpt-image-2.5-sunburst
```

Webflow token requires CMS read/write and assets write scopes. Node.js 20+ is required. Only place real keys in the ignored `.env`; never commit them.

## Preview — no Webflow changes

AI version using Sunburst:

```bash
npm run preview
```

Alternative AI model:

```bash
npm run preview -- --model gpt-image-2.5-flare --out output/flare
```

Deterministic solid-colour version (recommended for this particular grey background because it never regenerates product pixels and does not use the OpenAI API):

```bash
npm run preview:solid -- --out output/solid
```

Each preview downloads the currently linked Webflow image, detects the white rectangular padding, and protects the central source photo. The AI route sends a mask and background-only prompt to OpenAI, then composites the **original unmodified photo rectangle** over the generated backdrop. The solid route fills the margin with the sampled authentic background colour.

Examine the files in the output directory:
- `before-after.jpg`: side-by-side comparison.
- `preview.webp`: resulting 1200 × 1600 WebP image.
- `original.webp`: untouched source for rollback.
- `normalized.png`, `mask.png`, `restored.png`, optional `ai-output.png`: intermediate files.
- `manifest.json`: original Webflow records, hashes, and apply state.
- `usage.json`: per-request OpenAI tokens, pricing rates, and estimated USD cost.

**Do not apply until you review the preview image.** The lossless intermediate preserves all original photo pixels; the compressed WebP is lossy and may introduce small encoding differences.

## Token usage and cost reporting

After each successful OpenAI Images API request (`npm run preview` or the Flare alternative), the terminal shows the actual API-reported token usage, split into:
- Input text tokens
- Input image tokens
- Output image tokens
- **Total tokens**
- Estimated USD cost for each token category and the **estimated total cost**

Example (illustrative token usage, not a recorded charge):

```text
--- OpenAI image-edit token usage and cost ---
Model: gpt-image-2.5-sunburst
Input tokens: 1,100
  Text input: 100
  Image input: 1,000
Output image tokens: 2,300
TOTAL TOKENS: 3,400
Text input cost:  $0.00050000
Image input cost: $0.00800000
Image output cost:$0.06900000
ESTIMATED TOTAL COST: $0.07750000 USD
```

Rates for both Sunburst and Flare, **Standard (non-Batch)** direct Images API calls, as verified 2026-10-15:
- Text input: **$5.00 / 1M tokens**
- Image input: **$8.00 / 1M tokens**
- Image output: **$30.00 / 1M tokens**

The token numbers come from the response's `usage` object. The result is an *estimated API cost*, not an OpenAI invoice; it excludes any taxes, account-specific adjustments or future pricing changes. If usage or the text/image breakdown is missing, the tool explicitly prints **unavailable** rather than reporting a made-up total. If the edit request succeeds but subsequent image processing fails, token usage and cost are still printed immediately.

The preview directory also contains `usage.json`, and the same report is saved in `manifest.json` for a later audit. These are **per preview request**, not your OpenAI account-wide usage totals.

`npm run preview:solid` does not call OpenAI, so it prints 0 tokens and $0 OpenAI API cost.

Official documentation: [Image generation cost and token usage](https://developers.openai.com/api/docs/guides/image-generation) and [API pricing](https://developers.openai.com/api/docs/pricing).


## Apply — explicit staged change only

```bash
npm run apply -- --confirm 6ac69399d70193b11f7af706
```

For the Flare or solid preview, include `--out output/flare` or `--out output/solid`.

Apply verifies the preview hash and confirms the source CMS item, hero relation, and unrelated fields are unchanged. It then uploads a **new** Webflow asset and patches only the `image` field on the existing Images CMS item. Product, colour, sort order, and hero reference remain intact.

This is a **staged CMS update**. The tool does not publish or delete assets. The original asset remains available. Validate in Webflow before publishing manually.

## Roll back staged change

```bash
node src/cli.mjs rollback --confirm 6ac69399d70193b11f7af706
```

For a custom preview directory, supply `--out` with the original directory. Rollback refuses to overwrite newer unrelated CMS changes. It restores the original image in staging; it does not unpublish or reverse publishing that you performed separately.

## Tests

```bash
npm test
```

This is a deliberately **single-image, manual-QA prototype**. A passing test does not substitute for testing the OpenAI request with actual credentials, Webflow upload permissions, API behaviour, or visual review. Stop if the border detector rejects the photo. No automatic batch updates or live-site publishing are implemented.

See [OpenAI Images API](https://platform.openai.com/docs/api-reference/images) and [Webflow CMS API](https://developers.webflow.com/data/reference/cms).

---

## Batch restoration — all 108 linked Images CMS items

This batch tool covers **all 108 image records across the 47 products** in the client's white-padding issue list, including **47 hero images and 61 other gallery images**. It does not touch the six products in the separate gender-mismatch list.

The original single-image commands remain available and unchanged.

### 1. Refresh the branch and test

```bash
git fetch origin
git switch feat/image-padding-restoration-test
git pull --ff-only origin feat/image-padding-restoration-test

cd tools/image-padding
npm install
npm test
```

Your `.env` must contain `WEBFLOW_API_TOKEN` and `OPENAI_API_KEY`; tokens remain local and are ignored by Git.

### 2. Verify the 108-image plan

```bash
npm run batch:plan
```

This is **read-only in Webflow**. It discovers the live Products and Images CMS records, matches all 47 product slugs, verifies each hero reference, and requires **exactly 108 unique linked image items**. If the CMS count or relationships changed since the audit, the script stops instead of guessing.

A local checkpoint is written to `output/batch-padding/plan.json`.

### 3. Create previews

Run a small trial first:

```bash
npm run batch:preview -- --limit 3
```

Then process the remainder:

```bash
npm run batch:preview
```

The default model is `gpt-image-2.5-sunburst`, with **AI editing for images where a safe rectangular padding area can be detected**. To select Flare:

```bash
npm run batch:preview -- --model gpt-image-2.5-flare
```

For uniform-colour backgrounds, you can avoid paid model calls and any possibility of AI altering the background by using `--engine auto`. This chooses **exact solid-colour fill** for uniform backgrounds and AI for more complex ones:

```bash
npm run batch:preview -- --engine auto
```

The `--engine solid` option uses only solid fill and skips images with nonuniform backgrounds.

Every source is individually validated. The image is normalized to **1200 × 1600 (3:4)**, the photograph is protected, the padding alone is filled or outpainted, the original photograph is composited back, and the final image is compressed to WebP. Images without a reliably identifiable rectangular padding region are **skipped for manual review**, never forced through an unsafe modification.

**Important:** preview is read-only in Webflow. It does **not** upload, update, publish or delete CMS data.

### Terminal progress and final OpenAI cost

Progress updates show current image, completed/total count, percentage and ETA:

```text
[############------------] 54/108 50% ETA 8m 12s  ready product-slug
```

Each successful OpenAI request also prints its token counts and cost. The **final** report aggregates all recorded image-edit requests in the saved batch, including outputs produced in earlier runs:

```text
========== OPENAI BATCH USAGE ==========
API requests with recorded usage: ...
Text input tokens:              ...
Image input tokens:             ...
Image output tokens:            ...
TOTAL TOKENS (reported):        ...
TOTAL ESTIMATED API COST:       $... USD
========================================
```

Estimates use the rates documented in `src/usage.mjs`. Missing usage receipts are explicitly identified, and an incomplete total is not presented as a guaranteed final charge.

### 4. Review every generated preview

Each image receives its own folder:

```text
output/batch-padding/
  plan.json
  summary.json
  <product-slug>/
    <images-cms-item-id>/
      manifest.json
      original-source.bin
      normalized.png
      mask.png                  # AI requests
      ai-output.png             # AI requests
      usage.json                # AI requests
      restored.png
      preview.webp
      before-after.jpg
```

Check the `before-after.jpg` files before applying. `summary.json` identifies **ready, skipped, failed, review-required and applied** items. The original CMS data and source asset remain saved in each manifest for rollback.

You can review progress and totals without contacting Webflow:

```bash
npm run batch:summary
```

### Visual QA contact sheets (local only)

Generate review sheets for **all 101 completed previews** and a separate sheet containing the **seven unresolved source images**:

```bash
npm run batch:review
```

The tool creates `output/batch-padding/review-sheets/` with numbered `ready-01.webp`, `ready-02.webp`, etc. for side-by-side **original vs. generated** comparisons, plus `needs-attention-01.webp` showing the skipped/failed original images and their reasons. It also writes `review-sheets/index.json` mapping each CMS image ID to its sheet.

**Please inspect all previews before applying.** A `ready` status means the output was generated and passed processing checks, not that the resulting padding, edges, products, and shadows have been visually approved.

This contact-sheet generator is **entirely local**: no OpenAI API request, no Webflow changes, no new charges. Upload `needs-attention-01.webp` to a follow-up chat if you want visual diagnosis of the six skipped images and the one failed image.

**Accounting clarification:** when any API request may have been billed without a usage receipt, `usage.completeCost` is now **false**, and the terminal calls the displayed amount a **partial estimate**, rather than implying that it represents every possible charge. Run `npm run batch:summary` to regenerate this corrected summary without reprocessing images.

### 5. Apply approved previews to Webflow CMS (optional)

**Only after inspecting and approving the previews**, run:

```bash
npm run batch:apply -- --reviewed yes --confirm APPLY_REVIEWED_108_IMAGES
```

This command does **not** call OpenAI again. It uploads the saved WebP for each eligible image, then updates **only the `image` field on the existing Images CMS item**, preserving the original item ID, product and colour links, sort order, and hero references. It validates that no one has edited the source CMS record since the preview, and verifies the updated field.

For a limited rollout, append `--limit 3` to apply the next three eligible items; rerunning resumes from checkpoints.

**Apply changes staging only. It deliberately does not publish the site or CMS items**, or delete the original assets. Review in Webflow and publish separately when satisfied.

### 6. Roll back staging (optional)

```bash
npm run batch:rollback -- --reviewed yes --confirm ROLLBACK_108_IMAGES
```

Rollback only changes an image if the CMS still points to the exact asset this batch uploaded. It restores the original `image` field, leaves other fields alone, and does not republish or undo any earlier manual publishing.

### Resume and failure behaviour

- Re-run `npm run batch:preview` after a restart or interruption. Completed previews are verified by SHA-256 and skipped without additional OpenAI calls.
- An AI response's token usage and output are saved immediately. If postprocessing fails, the result is reused on the next run rather than generated again.
- If an interrupted API request may have been billed without a saved response, it is flagged for **manual review** and not automatically repurchased.
- Failed records do not block safe records; `summary.json` keeps the full list and the last-run outcomes.
- `--retry-failed yes` retries safe failed records after you investigate them. It **does not** automatically repeat an uncertain OpenAI call that may already have been billed; that record stays marked for manual review.
- The batch is strictly scoped to the audited list; it never automatically adds new products.

### Verification scope

Offline unit tests exercise target selection (47 products, 108 Images CMS records), safe refusal on missing/duplicate images, cost aggregation, and lossless preservation of the protected photograph before WebP compression. Live paid OpenAI requests and Webflow write permissions can only be validated with your local `.env` credentials.

