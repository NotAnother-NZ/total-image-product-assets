# Product Data & Asset Audit

This is a living audit log for product-data imports into the Total Image Webflow CMS.

The purpose of this file is to record source-data duplicates, missing asset matches, duplicate asset folders, and any manual SKU-to-asset decisions so there is a clear history of what was changed and why.

## Import rules

- Match product assets by SKU first.
- Do not silently map a product to a different SKU because the name or product type looks similar.
- Any non-exact SKU mapping must be reviewed and approved before it is used.
- Duplicate source products must be deduplicated before Webflow CMS import.
- When duplicate source rows contain conflicting non-empty values, do not silently overwrite one with the other. Record the conflict and choose the canonical value deliberately.
- Duplicate asset folders are not deleted or merged during the product-data import audit. They remain flagged until the image schema / asset migration is reviewed.

---

## 2026-09-21 — Accessories source audit

Source: `Product (Accessories)-Grid view.csv`

Asset inventory: `Total Image Product Assets`

### Summary

- Source rows: **47**
- Unique product SKUs: **46**
- Exact SKU asset matches: **38 unique SKUs**
- SKUs without an exact asset-folder match: **8**
- SKUs with multiple matching asset folders: **1**
- Duplicate source products: **1 SKU**

### SKUs without an exact asset-folder match

These products must not be attached to a candidate asset folder until the proposed mapping is approved.

| Source SKU | Product | Supplier | Closest asset-folder candidate | Confidence | Notes |
| --- | --- | --- | --- | --- | --- |
| `BB248M` | Men's Standard Belt | Fashion Biz | `RA972L_WOMEN'S_BELT` | Low | Closest existing belt folder by generic product type, but gender, SKU and product name differ. **Do not map without approval.** |
| `RA572M` | Men's Leather Belt | Fashion Biz | `RA972L_WOMEN'S_BELT` | Low | Closest existing leather/belt-type folder, but it is explicitly the women's product and has a different SKU. **Do not map without approval.** |
| `99300` | Men's Leather Reversible Belt | Fashion Biz | `RA972L_WOMEN'S_BELT` | Low | Only a broad belt-category candidate; SKU and product name do not correspond. **Do not map without approval.** |
| `H1026` | Slouch Hat With Break-Away Clip Strap | Winning Spirit | `4287_SURF_HAT` | Low | Closest broad brimmed-hat asset folder found, but there is no SKU or product-name correspondence. **Do not map without approval.** |
| `HB004` | Manhattan Chef Beanie | Chef Works | `5FC_CHEF'S_CAP` | Low | Closest chef-headwear asset folder; different SKU and product name. **Do not map without approval.** |
| `CH333` | Mesh Flat Top Hat | Fashion Biz | `5FC_CHEF'S_CAP` | Low | Closest chef-headwear asset folder; different SKU and product name. **Do not map without approval.** |
| `AS1130` | Access Cap | AS Colour | `1130_ACCESS_CAP` | High | Strong naming-discrepancy candidate: exact product-name match ("Access Cap") and the same numeric SKU `1130`; the asset folder appears to omit the supplier prefix `AS`. **Pending approval before mapping.** |
| `BA93` | Continental Style Full Length Apron | Fashion Biz | `A03_BIB APRON` | Low | Closest full-length apron form among available asset folders, but there is no SKU or product-name correspondence. **Do not map without approval.** |

### Duplicate asset folders

#### `BB10929` — Women's Slimline Belt

Two asset folders begin with the same source SKU:

1. `BB10929_SLIMLINE_WOMENS_BELT`
   - 3 files
   - Includes `BLACK_VIEW`, `BLACK_VIEW_2`, and `HERO_FRONT`
2. `BB10929_WOMEN'S_SLIMLINE_BELT`
   - 2 files
   - Includes a black product image and an additional black product image

**Current handling:** keep both folders untouched and flag them for the image-schema / asset review. No automatic merge, deletion, or canonical-folder choice has been made.

### Duplicate source product

#### `A33` — Capri Waist Apron

The Accessories source contains **two rows** for SKU `A33`.

The structured product data is effectively the same across both rows:

- Product Name: Capri Waist Apron
- Supplier: Identiee
- Fabric: 65% Polyester, 35% Cotton
- Colours: Black, Grey, Khaki, Navy, White
- Size Range: One Size
- Category/Subcategory: Accessories / Aprons
- Industry: Hospitality
- Gender: Unisex

The two records contain slightly different wording in the Description field.

**Import handling:** create **one** Webflow Product item for SKU `A33`, not two.

For deduplication, the first source occurrence is treated as the canonical row unless a later duplicate contains a value missing from the first. Missing values may be filled from another duplicate. Where both rows contain non-empty Description values, the longer Description is retained so information is not discarded. This merge rule was applied during the Webflow import.

### Manual mapping status

| Source SKU | Proposed asset folder | Status |
| --- | --- | --- |
| `AS1130` | `1130_ACCESS_CAP` | **Approved and used for import** |
| `BB248M` | `RA972L_WOMEN'S_BELT` | **Unresolved — low-confidence candidate only** |
| `RA572M` | `RA972L_WOMEN'S_BELT` | **Unresolved — low-confidence candidate only** |
| `99300` | `RA972L_WOMEN'S_BELT` | **Unresolved — low-confidence candidate only** |
| `H1026` | `4287_SURF_HAT` | **Unresolved — low-confidence candidate only** |
| `HB004` | `5FC_CHEF'S_CAP` | **Unresolved — low-confidence candidate only** |
| `CH333` | `5FC_CHEF'S_CAP` | **Unresolved — low-confidence candidate only** |
| `BA93` | `A03_BIB APRON` | **Unresolved — low-confidence candidate only** |

---

## Color schema decision

The source data confirms that one specific colour can belong to multiple broad colour families. For example, a colour such as `Navy/Brown` should be discoverable under both `Navy` and `Brown`.

The Webflow schema has therefore been updated to:

- **Color Families → Colors:** multi-reference
- **Colors → Color Families:** multi-reference
- **Products → Colors:** multi-reference

This preserves the specific product colour while supporting filtering/grouping by every relevant broad colour family.


---

## 2026-09-21 — Accessories Webflow import

The first Accessories batch has now been imported into the Total Image Webflow CMS as **draft content only**. Nothing from this import was published.

### Import result

- Source rows reviewed: **47**
- Unique source SKUs after deduplication: **46**
- Products imported to Webflow: **39**
- Duplicate source SKU merged before import: **A33**
- High-confidence manual SKU mapping approved and used: **AS1130 → 1130_ACCESS_CAP**
- Unresolved unmatched SKUs excluded from this import: **7**
- Images were **not** imported or attached because the Product image schema is still pending.

### Unmatched SKUs excluded

The following products were intentionally left out of Webflow until their asset mapping can be confirmed:

- `BB248M` — Men's Standard Belt
- `RA572M` — Men's Leather Belt
- `99300` — Men's Leather Reversible Belt
- `H1026` — Slouch Hat With Break-Away Clip Strap
- `HB004` — Manhattan Chef Beanie
- `CH333` — Mesh Flat Top Hat
- `BA93` — Continental Style Full Length Apron

No low-confidence candidate folder was used for any of these products.

### Approved manual SKU mapping

#### `AS1130` — Access Cap

Approved asset mapping:

`AS1130 → 1130_ACCESS_CAP`

Reason:

- Exact product-name match: **Access Cap**
- Same numeric SKU: **1130**
- The asset-folder naming appears to omit the supplier prefix `AS`

This product was included in the Webflow Product import.

### Source-data discrepancy: SKU `3980`

Product: **Recycled Breathable Poly Twill Cap**

The source field `Extra Filter Reference` contains:

`Accessories,Aprons`

This conflicts with the product type, which is clearly headwear/cap rather than an apron.

**Import handling:** the Product itself was imported, but its Product Subcategory was intentionally left unset. The source value was not silently corrected.

This remains a client/source-data issue to confirm before assigning a subcategory.

### Product taxonomy created

The following supporting CMS data was created:

- Product Category: **Accessories**
- Product Subcategories:
  - **Headwear**
  - **Aprons**
  - **Belts**

Products were linked to their supported subcategories, except SKU `3980` as documented above.

### Colour data imported

Supporting colour taxonomy created from the Accessories source:

- **70 specific Colors**
- **17 Color Families**

Products reference specific Colors directly.

Color Family relationships were only populated where the family was explicitly supported by the specific colour name. For example:

- `Navy/White → Navy + White`
- `Navy/Brown → Navy + Brown`
- `Indigo Blue → Blue`

Ambiguous specific colours were left without a family relationship rather than guessed.

### Hex field schema

The `Hex Code` field on both **Colors** and **Color Families** has been changed from Plain Text to Webflow's native **Color** field type.

At the time of replacement, all existing Hex Code values were empty, so no colour values were lost.

