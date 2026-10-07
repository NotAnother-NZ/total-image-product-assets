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
