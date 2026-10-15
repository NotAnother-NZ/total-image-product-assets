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
