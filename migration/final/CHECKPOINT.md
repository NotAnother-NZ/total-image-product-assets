# Final Webflow migration checkpoint — 2026-10-07

## Live Webflow reset complete

- Products cleared: 437 -> 0
- Images cleared: 3,715 -> 0
- Product Hero Image references cleared before deletion
- Product Related Products references cleared before deletion
- 36 Article -> Product reference sets backed up and cleared/published
- Article reference backup: `migration/final/article-product-reference-backup.json`

## Locked final sources

- Final Products: 422
- Final Colours: 202
- Colour Families: 17
- Approved GitHub asset folders: 422
- Approved WebP files: 4,464
  - Model: 2,048
  - Product: 2,416

GitHub asset folder/file names are client-approved and authoritative. Do not rename them during migration.

## Generated image migration outputs

`migration/final/output/05-images-001.csv` through `05-images-006.csv`

Supporting manifests:
- `image-manifest.json`
- `hero-image-map.json`
- `image-validation-report.json`

All 422 final products have a selected Hero Image candidate. Images whose approved filename does not safely encode one of that product's final Website colours are intentionally left without an Image -> Colour reference rather than guessed.

## Next import order

1. Colour Families
2. Colours
3. Colour Family reciprocal links
4. Products
5. Images CSV chunks 001-006
6. Apply Product Hero Image references
7. Restore Article -> Product references by final SKU where the product still exists
8. Final referential/count QA

Do not publish until the final QA passes.


## 2026-10-07 pre-import hardening

- Corrected the Colour CSVs to include Webflow Item IDs for all retained existing items.
  - 17 Colour Families update in place.
  - 189 existing Colours update in place.
  - 13 genuinely new Colours have blank Item IDs and will be created.
- Product CSV content fields were normalised so the merged source description is split into the intended CMS fields:
  - Key Highlights → Rich Text list
  - Description → Plain Text
  - Fabric & Features → existing Fabric paragraph + Rich Text feature list
- 393/422 Products have supplied structured content; 29 have no reliable optional content in the supplied product-data sources and remain blank rather than fabricated.
- The original 06 Product Hero file must not be imported directly because new Product Item IDs do not exist yet.
- Added `scripts/build-product-hero-update.mjs` to generate a safe Item-ID-based Hero update CSV from a fresh Webflow Product export after Product import.
- Added `IMPORT_RUNBOOK.md` with the exact staged import order and expected counts.

Next action requiring Webflow UI:
1. Import 01 Colour Families.
2. Import 02 Colours.
3. Import 03 reciprocal Colour Family links.
4. Import final 04 Products.
5. Import 05 Image chunks.
6. Export Products and generate/import the safe 06 Hero update.
7. Restore Article references and run final QA.
