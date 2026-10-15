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

**Do not apply until you review the preview image.** The lossless intermediate preserves all original photo pixels; the compressed WebP is lossy and may introduce small encoding differences.

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
