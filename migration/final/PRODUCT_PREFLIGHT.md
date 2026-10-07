# Product preflight — final 422-item import

## Validation result

- Rows: 422
- Unique Product SKUs: 422
- Unique Product slugs: 422
- Category reference errors: 0
- Subcategory reference errors: 0
- Industry reference errors: 0
- Gender values: only Men / Women / Unisex / blank
- Structured Product content present: 393
- Optional content unavailable in supplied product-data sources: 29

## Important correction applied

The previous Product CSV used `workwear-and-hi-vis` as the Category slug for 50 Workwear / Hi-Vis products.

The live Webflow **Product Categories** collection uses the slug:

`hi-vis-and-workwear`

The final Product CSV has been corrected to use that live slug. Industries continue to use `workwear-and-hi-vis`, which is the correct live Industry slug.

## Product content field split

The source product detail copy was stored as one combined value containing:

- Key Highlights
- Description
- Fabric & Features

Before import, that content was split into the actual Product CMS fields:

- **Key Highlights** → Rich Text `<ul><li>…</li></ul>`
- **Description** → Plain Text
- **Fabric & Features** → existing Fabric paragraph plus the Rich Text feature list

393 products contain this structured content.

## 29 products with no reliable optional product-detail content

These products remain valid migration rows, but Key Highlights / Description / Fabric & Features are intentionally blank because the supplied product-data sources do not contain reliable detail copy for them. No copy has been fabricated.

- 1529 — Selwyn Men's Vest
- 1796WL — Freya Shirred Cuff Soft Top
- 2512 — Selwyn Lady Jacket
- 40310 — Womens Hudson L/S Shirt
- 40320 — Mens Hudson L/S Shirt
- 43411 — Springfield Womens 3/4 Sleeve Shirt
- 70716R — Mens Siena Slim Fit Flat Front Pant (Regular)
- BBS2605L — Womens Grace T-Shirt Midi Dress
- JH130W — Arches Women's Padded Jacket
- JH135 — Arches Men's Padded Vest
- MJ365 — Standard Jeans MENS R Jean
- P515LS — Womens Lotus Short Sleeve Polo
- P515MS — Mens Lotus Short Sleeve Polo
- PS60 — Ladies Bamboo Charcoal Short Sleeve Polo
- R900M — Printable Recycled 3-Layer Softshell Jacket
- RGS2670L — Womens Sammy Skirt
- S627LN — Ladies Madison Sleeveless Top
- S628LS — Ladies Madison Short Sleeve Shirt
- T14 — Men's Stevie
- TW1639 — Mens Signature Trouser
- TW1643 — Mens Signature Shorts
- TW1838 — Ladies Signature Trouser
- W49 — Mens Blue Denim Shirt Men’s Dylan Short Sleeve Shirt
- W71 — Men's Floyd Long Sleeve
- W73 — Ladies Floyd Long Sleeve
- W90 — Men's Blake Long Sleeve Shirt
- W91 — Men's Blake Short Sleeve Shirt
- W92 — Ladies Blake Long Sleeve Shirt
- W93 — Ladies Blake Short Sleeve Shirt

These fields are optional in the current Webflow Product schema, so this does not block the migration.
