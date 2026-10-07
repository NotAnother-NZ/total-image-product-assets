# Total Image — final Webflow CSV import runbook

## Current live state

- Products: 0
- Images: 0
- Colours: 189 retained final items; 13 final items still need to be created
- Colour Families: 17 retained items
- Colour ↔ Colour Family references: cleared
- Article → Product references: cleared and backed up

## Important CSV safety rule

Webflow only matches existing CMS items for update when the CSV carries the existing **Item ID**. The final Colour CSVs therefore contain Item IDs for retained items; the 13 genuinely new Colours have blank Item IDs and must be created as new items.

Do not import the old `06-product-hero-images.csv` directly. Product IDs do not exist until after the Product import. Generate the ready version from a fresh Webflow Product export using `scripts/build-product-hero-update.mjs`.

## Import order

### 1. Colour Families

Import `output/01-colour-families.csv` into **Color Families**.

Choose **Link and update matching items**.

Map:
- Item ID → Item ID
- Color Family Name → Color Family Name
- Slug → Slug
- Swatch Color → Swatch Color

### 2. Colours

Import `output/02-colours.csv` into **Colors**.

Choose **Link and update matching items and import remaining as new**.

Expected on a clean run:
- 189 linked/updated
- 13 created
- 202 total after import

If resuming the 2026-10-07 in-progress migration where only Black Charcoal and Black/Black failed, do not re-import all 202 rows. Import `output/02b-colours-retry.csv` as new items, then continue to Step 3.

Map:
- Item ID → Item ID
- Color Name → Color Name
- Slug → Slug
- Color Families → Color Families
- Swatch Type → Swatch Type
- Swatch Color 1 → Swatch Color 1
- Swatch Color 2 → Swatch Color 2
- Swatch Color 3 → Swatch Color 3

### 3. Reciprocal Colour Family links

Import `output/03-colour-families-links.csv` into **Color Families**.

Choose **Link and update matching items**.

Map:
- Item ID → Item ID
- Color Family Name → Color Family Name
- Slug → Slug
- Colors → Colors

Expected after this step:
- 17 Colour Families
- 202 Colours
- both directions of the many-to-many relationship populated

### 4. Products

Before this step, place the final locally generated Product CSV at `migration/final/output/04-products.csv`. This file is intentionally supplied separately from the repository migration branch so it can be checked locally before import.

Import `migration/final/output/04-products.csv` into **Products** and choose **Import all as new items**.

Expected: 422 Products.

The final CSV deliberately uses final Website colour slugs. Optional content fields are blank where the supplied product-data workbooks contain no reliable content.

### 4b. Product retry for reserved deleted slugs

If the first Product import creates 63 of 422 items and the remaining 359 report Validation Failure, this is the known reserved-slug collision from the earlier deleted Product migration.

Do **not** re-import all 422 rows.

Import `output/04b-products-retry.csv` into **Products** and choose **Import all as new items**.

Expected:
- existing Products before retry: 63
- retry rows: 359
- final Products after retry: 422

The retry file keeps all Product data identical and changes only the failed Product slugs by appending the Product SKU, e.g.:
`womens-cool-stretch-bandless-slim-leg-pant` → `womens-cool-stretch-bandless-slim-leg-pant-10121`.

After this retry succeeds, regenerate the Image outputs locally before importing Images:

```bash
node migration/final/scripts/generate-image-csvs.mjs
node migration/final/scripts/validate-migration.mjs
```

### 5. Images

Import `05-images-001.csv` through `05-images-006.csv` into **Images**, in order.

Choose **Import all as new items** for every chunk.

Expected: 4,464 Images.

### 6. Product Hero Images

After Product and Image imports complete:

1. Export the Products Collection from Webflow to CSV.
2. Run:

```bash
node migration/final/scripts/build-product-hero-update.mjs "/path/to/webflow-products-export.csv"
```

3. Import the generated `output/06-product-hero-images-ready.csv` into Products.
4. Choose **Link and update matching items**.

Expected: 422 Product Hero Image references.

### 7. Restore Article → Product references

Use `article-product-reference-backup.json` to restore references by final Product SKU after the new Product IDs exist. Products no longer present in the final 422-product allowlist must not be restored.

### 8. QA before publish

Do not publish until all checks pass:

- 17 Colour Families
- 202 Colours
- 422 Products
- 4,464 Images
- no duplicate Product SKU
- every Product colour reference resolves
- every Image Product reference resolves
- all 422 Products have the intended Hero Image
- no stale Product/Image IDs remain
- Article → Product references restored only to final Products
