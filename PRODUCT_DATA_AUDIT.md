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



---

## 2026-09-21 — Bottoms source audit and Webflow import

Source: `Product (Bottoms)-Grid view.csv`

Asset inventory: `Total Image Product Assets`

### Summary

- Source rows: **32**
- Unique product SKUs after deduplication: **29**
- Exact SKU asset matches with one folder: **18**
- Exact SKU asset matches with multiple folders: **9**
- Non-exact SKU asset matches reviewed manually: **2**
- Duplicate source SKUs merged before import: **3**
- Products imported to Webflow: **29**
- Products excluded from import: **0**
- All imported CMS items remain **drafts**. Nothing was published.
- Images were **not** imported or attached because the Product image schema is still pending.

### Product taxonomy created

Product Category:

- **Bottoms**

Product Subcategories:

- **Pants**
- **Skirts**
- **Shorts**
- **Chinos**

Source naming was normalised before import:

- `Skirt` → **Skirts**
- `Chino` → **Chinos**
- `Chinos` → **Chinos**

This avoids carrying inconsistent Airtable naming into the Webflow taxonomy.

### Duplicate source products merged

The following SKUs appeared more than once in the source and were merged into one Webflow Product each:

#### `BS724M` — Men's Lawson Chino Pant

Two source rows existed.

Differences:

- One row had `Bottoms,Pants`
- One row had `Bottoms,Pants,Chinos`
- Description wording differed slightly

**Import handling:** merged to one Product, retained all supported taxonomy values, and assigned both **Pants** and **Chinos**. The more complete Description was retained.

#### `BS724L` — Ladies Lawson Chino Pant

Two source rows existed.

Differences:

- One row had `Bottoms,Pants`
- One row had `Bottoms,Pants,Chinos`

**Import handling:** merged to one Product and assigned both **Pants** and **Chinos**.

#### `BS022L` — Lawson Ladies Chino Skirt

Two source rows existed.

Differences:

- One row used `Bottoms,Skirt,Chino`
- One row used `Bottoms,Skirt,Chinos`
- Description wording differed slightly

**Import handling:** merged to one Product, normalised the taxonomy to **Skirts** + **Chinos**, and retained the more complete Description.

### Non-exact SKU mappings reviewed and used

Both non-exact matches were considered high confidence and were used for this import.

#### `RGS264L-BIZ` — Traveller Women's Chino Skirt

Mapped asset folder:

`RGS264L-BIZ → RGS264L_TRAVELLER_WOMEN'S_CHINO_SKIRT`

Reason:

- Exact product-name match
- Base SKU `RGS264L` matches
- The source SKU appears to add the `-BIZ` suffix only

**Status:** high-confidence mapping, used for import.

#### `CA3P` — So Ezy Pant

Mapped asset folder:

`CA3P → CA3PSO_EZY_ PANT`

Reason:

- Product name matches **So Ezy Pant**
- Asset folder begins with the same base SKU `CA3P`
- The folder appears to concatenate the product name directly after the SKU

**Status:** high-confidence mapping, used for import.

### Duplicate asset folders

These were recorded only. No asset folders were deleted, merged, or renamed.

| SKU | Product | Duplicate asset folders |
| --- | --- | --- |
| `BS125L` | Ladies Bella Pant | `BS125L_LADIES_BELLA_PANT`; `BS125L_Womens_Bella_Pant` |
| `BS724L` | Ladies Lawson Chino Pant | `BS724L_LADIES_LAWSON_CHINO_PANT`; `BS724L__LADIES_LAWSON_CHINO_PANT` |
| `BS724M` | Men's Lawson Chino Pant | `BS724M_MEN'S_LAWSON_CHINO_PANT`; `BS724M_Mens_Lawson_Chino_Pant` |
| `BS909L` | Ladies Remy Pant | `BS909L_LADIES_REMY_PANT`; `BS909L_Ladies Remy Pant` |
| `CH432M` | Men's Saffron Chef Flex Pant | `CH432M_MEN'S_SAFFRON_CHEF_FLEX _PANT`; `CH432M_MEN'S_SAFFRON_CHEF_FLEX_PANT` |
| `CL955LL` | Women's Comfort Waist Straight Leg Pant | `CL955LL_WOMEN'S_COMFORT_WAIST_STRAIGHT_LEG_PANT`; `CL955LL_Women_Comfort_Waist Straight_Leg_Pant` |
| `CL960MS` | Men's Comfort Waist Cargo Short | `CL960MS_Comfort_Waist_Mens_Cargo_Short`; `CL960MS_MEN'S_COMFORT_WAIST_CARGO_SHORT` |
| `RGP263L` | Traveller Women's Slim Leg Chino | `RGP263L_TRAVELLER_WOMEN'S_SLIM_LEG_CHINO`; `RGP263L_Traveller_Womens_Slim_Leg_Chino` |
| `RGP263M` | Traveller Men's Tapered Chino | `RGP263M_TRAVELLER_MEN'S_TAPERED_CHINO`; `RGP263M_TRAVELLER_MEN’S_TAPERED_CHINO` |

**Current handling:** keep all duplicate folders untouched until the image-schema / asset migration stage.

### Supporting CMS data created

New Product Category:

- **Bottoms**

New Product Subcategories:

- **Pants**
- **Skirts**
- **Shorts**
- **Chinos**

New Industry:

- **Beauty**

New specific Colors:

- **Dark Grey**
- **Desert**
- **Taupe**
- **Dark Stone**
- **Toffee**

Existing specific colour `olive` from the source was normalised to the existing CMS item **Olive**.

### Color Family relationships added

The Bottoms source provides enough evidence to add these broader family relationships:

- **Dark Grey → Grey**
- **Desert → Brown**
- **Taupe → Brown**
- **Dark Stone → Brown**
- **Toffee → Brown**
- **Olive → Green**
- **Stone → Brown**

Existing Color Family relationships were preserved. Because Colors support multiple Color Families, this means a specific colour such as **Stone** can retain its existing family relationship while also being grouped under **Brown** where this source explicitly does so.



---

## 2026-09-21 — First Nations source audit — pending client confirmation

Source: `Product (First Nations)-Grid view.csv`

### Summary

- Source rows: **14**
- Unique product SKUs: **14**
- Duplicate source SKUs: **0**
- Source Product Category / filters: **Polos → Short Sleeve → First Nations**
- Source Industry Reference: **First Nations** on all 14 rows
- Webflow import status: **Not imported**
- Reason: the meaning of `First Nations` in the source taxonomy needs client confirmation before creating or assigning CMS taxonomy.

### Why this set was paused

The source uses `First Nations` in two places:

- `Extra Filter Reference`: `Polos,Short Sleeve,First Nations`
- `Industry Reference`: `First Nations`

However, `First Nations` does not appear to represent an industry in the same sense as the existing Webflow Industries such as Corporate, Hospitality, Healthcare, Retail, Government, or Workwear & Hi-Vis.

In an Australian context, **First Nations** is an umbrella term referring to Aboriginal and Torres Strait Islander peoples. The products in this source also appear to be culturally themed apparel featuring First Nations artwork / artist collaborations.

Because of that, creating **First Nations** as a Webflow Industry would risk mixing a cultural/community classification with commercial industry verticals.

### Current recommendation

Do **not** create a `First Nations` Industry and do **not** import this batch until the client confirms the intended taxonomy.

The likely alternatives are:

1. Treat **First Nations** as a product tag / filter / collection rather than an Industry.
2. Treat the products normally as **Polos → Short Sleeve**, with a separate `First Nations` attribute for cultural/artwork classification.
3. If the client explicitly confirms that they intentionally use `First Nations` as an Industry in their product taxonomy, retain it as supplied.

No assumption has been made yet.

### Source observations

- All 14 products are polo shirts.
- All 14 rows use `Polos,Short Sleeve,First Nations`.
- All 14 rows use `First Nations` as the Industry Reference.
- There are no duplicate SKUs in this source.
- Supplier information is mostly blank in the CSV; one row explicitly lists **Yarn Corp**.
- Product names include artwork/design ranges such as:
  - A Bright Future
  - Family
  - Future Dreaming
  - Guiding Light
  - Knowledge Holders
  - Legacy
  - Mountains

### Client confirmation required

Ask the client:

> We noticed the First Nations product set is tagged as `First Nations` under both filters and Industry. We currently treat Industry as commercial sectors such as Corporate, Hospitality, Healthcare, Retail, etc. Should `First Nations` genuinely be treated as an Industry on the website, or is it intended as a product collection/filter for First Nations artwork and designs?

Until this is confirmed, this set remains intentionally unimported.

### Asset coverage

The First Nations/Yarn source was also checked against the product asset inventory.

Asset-folder coverage:

- **8 of 14 source SKUs have a high-confidence corresponding asset folder**
- **6 of 14 source SKUs do not have a separate matching asset folder**

High-confidence mappings:

| Source SKU | Asset folder | Status |
| --- | --- | --- |
| `BRIGHT-YARN` | `BRIGHT_YARN_A_BRIGHT_FUTURE_ESSENCE_POLO_SHIRT` | High confidence |
| `BRIGHT-YARN- UNISEX` | `BRIGHT_YARN_UNISEX_A_BRIGHT_FUTURE_ESSENCE_POLO_SHIRT` | High confidence |
| `FAMILY-YARN-UNISEX` | `FAMILY_YARN_UNISEX_FAMILY_BLACK_BAMBOO_(SIMPSON)_POLO_SHIRT` | High confidence |
| `FUTURE-YARN-UNISEX` | `FUTURE_YARN_UNISEX_FUTURE_DREAMING_ESSENCE_POLO_SHIRT` | High confidence |
| `GUIDING-YARN- UNISEX` | `GUIDING_YARN_UNISEX_GUIDING_LIGHT_BLACK_BAMBOO_(SIMPSON)_POLO_SHIRT` | High confidence |
| `KNOWLEDGE-YARN-UNISEX` | `KNOWLEDGE_YARN_UNISEX_KNOWLEDGE_HOLDERS_BLACK_BAMBOO_(SIMPSON)_POLO_SHIRT` | High confidence |
| `LEGACY-YARN-UNISEX` | `LEGACY_YARN_UNISEX_LEGACY_POLO_SHIRT` | High confidence |
| `MOUNTAINS-YARN-UNISEX` | `MOUNTAINS_YARN_UNISEX_MOUNTAINS_WHITE_BAMBOO_(SIMPSON)_POLO_SHIRT` | High confidence |

Source SKUs without a separate matching asset folder:

- `FAMILY-YARN`
- `FUTURE-YARN`
- `GUIDING-YARN`
- `KNOWLEDGE-YARN`
- `LEGACY-YARN`
- `MOUNTAINS-YARN`

For these six products, only the corresponding **Unisex** asset folder was found.

**Current handling:** do not automatically reuse the Unisex imagery for the non-Unisex / women's source products. That relationship needs client confirmation before images are assigned.

This is a second reason the First Nations batch remains intentionally paused alongside the taxonomy question.



---

## 2026-09-21 — Hi Vis & Workwear source audit and Webflow import

Source: `Product (Hi Vis & Workwear)-Grid view.csv`

Asset inventory: `Total Image Product Assets`

### Summary

- Source rows: **90**
- Non-empty unique source SKUs before deduplication: **65**
- Duplicate source SKUs: **24**
- Additional source row with a blank SKU: **1**
- Final unique products after deduplication / blank-row reconciliation: **65**
- Exact asset-folder matches: **50**
- Unresolved SKUs without an exact asset-folder match: **15**
- Duplicate asset folders among the 50 exact matches: **0**
- Products imported to Webflow: **50**
- Products intentionally excluded from this import: **15**
- All imported items remain **drafts**. Nothing was published.
- Images were **not** imported or attached because the Product image schema is still pending.

### Blank SKU source row

One source row had no SKU:

- Product: **Women's Outdoor Long Sleeve Shirt**
- Supplier: **Syzmik**
- Category/filter data: `Workwear,Shirts,Long Sleeve`

This row was reconciled with SKU `ZW760` — **Women's Outdoor L/S Shirt** — because the product identity, supplier, gender, colours and product type align with the existing `ZW760` rows.

**Import handling:** no separate CMS Product was created. The blank-SKU row was merged into the `ZW760` source group before import.

### Duplicate source SKUs merged

The following 24 SKUs appeared more than once in the source. Each was reduced to a single source product before any Webflow import:

- `6HVSV` — Hi Vis Safety Vest
- `6HVSZ` — Hi Vis Zip Safety Vest
- `BPC6008` — Stretch Cotton Drill Cargo Pants
- `BPC6088T` — Recycle Taped Biomotion Cargo Work Pant
- `BPC6334T` — Flx And Move™ Taped Stretch Cargo Cuffed Pants
- `SW19A` — Hi-Vis Reversible Safety Vest With 3m Tapes
- `ZP230` — Men's Essential Basic Stretch Cargo Pant
- `ZP504` — Men's Rugged Cooling Cargo Pant (Regular)
- `ZP730` — Women's Essential Basic Stretch Cargo Pant
- `ZP733` — Women's Essential Stretch Taped Cargo Pant
- `ZP735` — Women's Essential Stretch Taped Cargo Pant - Cuffed
- `ZP820` — Men's Streetworx Heritage Pant
- `ZP923` — Men's Essential Stretch Taped Cargo Pant
- `ZP935` — Men's Essential Stretch Taped Cargo Pant - Cuffed
- `ZT210` — Unisex Streetworx Lightweight 1/4 Zip Polar Fleece
- `ZV245` — Unisex Streetworx Hooded Puffer Vest
- `ZW120` — Men's Light Weight Tradie S/S Shirt
- `ZW121` — Men's Lightweight Tradie L/S Shirt
- `ZW460` — Men's Outdoor L/S Shirt
- `ZW465` — Men's Outdoor S/S Shirt
- `ZW468` — Men's Hi Vis Outdoor L/S Shirt
- `ZW760` — Women's Outdoor L/S Shirt
- `ZW765` — Women's Outdoor Short Sleeve Shirt
- `ZWL120` — Women's Lightweight Tradie S/S Shirt

Where duplicate rows differed, the import merge rule was:

- preserve the union of colours, industries and filter/subcategory values;
- retain the more complete non-empty Description / Fabric / Size Range value;
- never create two Webflow Products for the same SKU.

Some duplicate source rows had conflicting or incomplete size values, for example `ZW765`, `ZWL120`, `SW19A` and `6HVSZ`; the more complete size-range value was retained.

### Unresolved SKUs excluded from Webflow

The following 15 products do not have an exact asset-folder match and were intentionally left out of this import:

| SKU | Product |
| --- | --- |
| `6HVPF` | Hi Vis 1/2 Zip Polar Fleece |
| `6HVSZ` | Hi Vis Zip Safety Vest |
| `BJ6078T` | Taped Two Tone Hi Vis 3 In 1 Soft Shell Jacket |
| `BJ6766T` | Taped Hi Vis Recycled Rain Shell Jacket |
| `ZJ240` | Unisex Streetworx Hooded Puffer Jacket |
| `ZJ532` | Men's Hi Vis 4 In 1 Waterproof Jacket |
| `ZJ553` | Unisex Hi Vis Antarctic Softshell Taped Jacket |
| `ZJ616` | Men's Hi Vis X Back Taped 4 In 1 Waterproof Jacket |
| `ZJ770` | Women's Hi Vis Nsw Rail X Back 2 In 1 Softshell Jacket |
| `ZT210` | Unisex Streetworx Lightweight 1/4 Zip Polar Fleece |
| `ZT462` | Hi Vis Polar Fleece Jumper - Shoulder Taped |
| `ZT476` | Unisex Hi Vis Half Zip Pullover |
| `ZT640` | Unisex Hi Vis Vic Rail 1/4 Zip Pullover |
| `ZT867` | Unisex Streetworx Water Resistant Hoodie With Segmented Tape |
| `ZV228` | Unisex Hi Vis Waterproof Reversible Vest |

Several have visually or semantically similar asset folders, but none were strong enough to justify using another SKU's asset folder without client approval.

**Current handling:** no guessed mappings were used. These 15 products remain pending manual SKU/asset review.

### Product taxonomy created

New Product Category:

- **Hi Vis & Workwear**

Canonical Product Subcategories created for this category:

- **Workwear**
- **Hi Vis**
- **Pants**
- **Shirts**
- **Long Sleeve**
- **Short Sleeve**
- **Safety Vests**
- **Shorts**
- **Vests**

Source taxonomy was normalised before import:

- `Shirt` → **Shirts**
- `Vest` / `Vests` → **Vests**
- `Safety Vest` → **Safety Vests**

The broader source values **Workwear** and **Hi Vis** are retained as subcategories/filters because individual products use them distinctly, while all products also retain the existing **Workwear & Hi-Vis** Industry relationship.

### Color data

The batch uses a mixture of existing colours plus additional Hi Vis / workwear-specific values.

New specific Color items created from this source include:

- **Charcoal Blue**
- **Green**
- **Lime/Black**
- **Lime/Navy**
- **Lime/Purple**
- **Lt Blue**
- **Orange/Black**
- **Orange/Charcoal**
- **Orange/Navy**
- **Pea Green**
- **Pink/Navy**
- **Vic Rail Orange**
- **Yellow**
- **Yellow/Bottle**
- **Yellow/Charcoal**
- **Yellow/Navy**

Some of these belong only to the 15 currently excluded products. They were still created because they are valid source taxonomy values and can be reused when those products are resolved later.

### Final Webflow QA

After the five import batches completed, the Hi Vis & Workwear category was checked directly in Webflow:

- **50 Product items found**
- **50/50 are drafts**
- **0 missing Gender values**
- **0 missing Category references**
- **0 missing Color references**
- **0 missing Subcategory references**

The category's reverse Subcategories relationship was also populated.



---

## 2026-09-21 — Hi Vis & Workwear source audit and Webflow import

Source: `Product (Hi Vis & Workwear)-Grid view.csv`

Asset inventory: `Total Image Product Assets`

### Summary

- Source rows: **90**
- Unique product SKUs after deduplication / blank-SKU reconciliation: **65**
- Duplicate non-empty source SKUs: **24**
- Blank-SKU source rows: **1**
- Exact asset-folder matches: **50**
- Unresolved SKUs without an exact asset-folder match: **15**
- Duplicate asset folders among exact matches: **0**
- Products imported to Webflow: **50**
- Products intentionally excluded from import: **15**
- All imported Webflow items remain **drafts**. Nothing was published.
- Images were **not** attached because the Product image schema is still pending.

### Duplicate source SKUs merged

The following source SKUs occurred more than once and were merged into one Product record per SKU before import:

- `ZW460`
- `ZW765`
- `ZW468`
- `ZW465`
- `ZW760`
- `ZW121`
- `ZW120`
- `ZWL120`
- `SW19A`
- `6HVSZ`
- `6HVSV`
- `ZP820`
- `ZV245`
- `ZT210`
- `BPC6008`
- `ZP504`
- `ZP230`
- `ZP730`
- `ZP735`
- `ZP935`
- `BPC6088T`
- `ZP923`
- `ZP733`
- `BPC6334T`

Merge rule:

- keep one Product per SKU
- combine non-conflicting category/filter/reference values
- retain the most complete Description / Fabric / Size Range values
- do not create duplicate Webflow Products for repeated Airtable rows

### Blank-SKU source row

One source row had no SKU:

- **Women's Outdoor Long Sleeve Shirt**

The row is the same product as the existing source product:

- `ZW760 — Women's Outdoor L/S Shirt`

The blank-SKU row was therefore folded into the `ZW760` source record rather than imported as a separate Product.

This reconciliation was based on the matching product identity and overlapping source data; no new SKU was invented.

### Unresolved asset SKUs — excluded from Webflow

The following 15 SKUs do not have an exact asset-folder match and were intentionally not imported:

- `6HVSZ`
- `ZJ240`
- `ZT210`
- `ZT867`
- `BJ6078T`
- `BJ6766T`
- `ZJ532`
- `ZJ616`
- `ZJ553`
- `ZJ770`
- `ZV228`
- `ZT476`
- `ZT640`
- `ZT462`
- `6HVPF`

**Current handling:** no approximate asset mapping has been used for these products. They remain pending manual review / client confirmation.

### Product taxonomy created

Product Category:

- **Hi Vis & Workwear**

Subcategories used for this category:

- **Workwear**
- **Hi Vis**
- **Pants**
- **Shirts**
- **Long Sleeve**
- **Short Sleeve**
- **Safety Vests**
- **Shorts**
- **Vests**

Source naming was normalised before import:

- `Shirt` → **Shirts**
- `Shirts` → **Shirts**
- `Vest` / `Vests` → **Vests**
- `Safety Vest` → **Safety Vests**

### Shared subcategory correction

**Pants** and **Shorts** already existed from the Bottoms taxonomy.

During the first support-data pass, duplicate Pants / Shorts subcategory records were temporarily created for Hi Vis & Workwear.

This was corrected before completion:

- all Set 4 Product references were moved to the existing shared **Pants** / **Shorts** items
- the shared subcategories now reference both **Bottoms** and **Hi Vis & Workwear**
- the temporary duplicate Pants / Shorts items were deleted

The CMS therefore retains one canonical reusable subcategory item for each shared taxonomy value.

### Colors added for imported products

New specific Colors retained for the 50 imported products:

- **Lt Blue**
- **Orange/Charcoal**
- **Orange/Navy**
- **Pea Green**
- **Pink/Navy**
- **Vic Rail Orange**
- **Yellow/Bottle**
- **Yellow/Charcoal**
- **Yellow/Navy**
- **Green**
- **Yellow**

The following Colors were initially encountered in the full source but only belonged to unresolved / excluded products. They were removed again so unused data was not left in the CMS:

- `Charcoal Blue`
- `Lime/Black`
- `Lime/Navy`
- `Lime/Purple`
- `Orange/Black`

### Color Family relationships added

Only clear, defensible family relationships were added:

- **Lt Blue → Blue**
- **Orange/Charcoal → Orange + Charcoal**
- **Orange/Navy → Orange + Navy**
- **Pea Green → Green**
- **Pink/Navy → Pink + Navy**
- **Vic Rail Orange → Orange**
- **Yellow/Bottle → Yellow**
- **Yellow/Charcoal → Yellow + Charcoal**
- **Yellow/Navy → Yellow + Navy**
- **Green → Green**
- **Yellow → Yellow**

No extra family was inferred for **Bottle** in `Yellow/Bottle`; only the explicit **Yellow** relationship was applied.

### Import execution

The 50 eligible Products were imported in five controlled batches:

- Batch 1: **10**
- Batch 2: **10**
- Batch 3: **10**
- Batch 4: **10**
- Batch 5: **10**

Final Webflow QA confirmed all 50 imported Products have:

- Product Category
- at least one Product Subcategory
- Gender
- at least one Color
- draft status

No Set 4 Product was published.


---

## 2026-09-21 — Outerwear source audit and Webflow import

Source: `Product (Outerwear)-Grid view.csv`

Asset inventory: `Total Image Product Assets`

### Summary

- Source rows: **56**
- Unique SKUs after source deduplication: **52**
- Duplicate source SKUs: **4**
- Exact asset-folder matches: **42**
- High-confidence non-exact asset mapping used: **1**
- Unresolved SKUs excluded: **9**
- Duplicate asset-folder cases among source SKUs: **12**
- Products imported to Webflow: **43**
- All imported items remain **drafts**
- Nothing was published
- Images were not attached because the Product image schema is still pending

### Duplicate source SKUs merged

The following SKUs appeared twice in the source and were merged to one Product record per SKU:

- `CO342LJ` — Nova Women's Knit Jacket
- `CO342MJ` — Nova Men's Knit Jacket
- `CO343LV` — Nova Women's Knit Vest
- `CO343MV` — Nova Men's Knit Vest

Merge handling:

- retained one Product per SKU
- combined non-conflicting reference/taxonomy values
- retained the more complete Description / Fabric / Size Range values
- `CO342MJ` contained different Industry Reference coverage across the duplicate rows; the merged record preserves the full supported set
- `CO343LV` remained excluded because its asset match is unresolved

### Approved high-confidence manual asset mapping

#### `CH230ML-BIZ` — Al Dente Men's Chef Jacket

Mapped asset folder:

`CH230ML-BIZ → CH230ML_AL_DENTE_MEN'S_CHEF_JACKET`

Reason:

- same base SKU `CH230ML`
- exact product-name match
- the source SKU adds the `-BIZ` suffix only

**Status:** high-confidence mapping used for this import.

### Unresolved asset SKUs — excluded from Webflow

The following 9 products were intentionally not imported because no exact or sufficiently reliable asset mapping was available:

- `1513` — Men's Olympus Soft Shell Jacket
- `CO343LV` — Nova Women's Knit Vest
- `J213L` — Expedition Women's Vest
- `J29123` — Ladies Soft Shell Vest
- `J830M` — Men's Apex Vest
- `JK63` — Men's Sustainable Softshell Corporate Jacket
- `LP618L` — Ladies Milano Pullover
- `RJP266M` — Osaka Men's Pineapple Knit Jumper
- `WV619M` — Men's Milano Vest

No opposite-gender or merely similar product asset folder was reused for any of these products.

### Duplicate asset folders

These were recorded only. No folders were deleted, merged or renamed.

| SKU | Duplicate asset folders |
| --- | --- |
| `2513` | `2513_LADIES_OLYMPUS_SOFT_SHELL_JACKET`; `2513_OLYMPUS_LADY_JACKETS` |
| `BJ2602L` | `BJ2602L_TAILOR_WOMENS_JACKET`; `BJ2602L_WOMEN'S_TAILOR_JACKET` |
| `CH232ML` | `CH232ML_ZEST_MENS_LS_CHEF_JACKET`; `CH232ML_ZEST_MENS_LS_CHEF_JACKET (1)` |
| `CO342LJ` | `CO342LJ_NOVA_WOMEN'S_KNIT_JACKET`; `CO342LJ_NOVA_WOMENS_ZIP_FRONT_JUMPER` |
| `CO343MV` | `CO343MV_NOVA_MEN'S_KNIT_VEST`; `CO343MV_NOVA_MEN'S_ZIP_FRONT_VEST`; `CO343MV_NOVA_MENS_ZIP_FRONT_VEST` |
| `J211L` | `J211L_ALPINE_LADIES_PUFFER_VEST`; `J211L_ALPINE_WOMENS_VEST` |
| `J307L` | `J307L_GENEVA_WOMENS_JACKET`; `J307L_LADIES_GENEVA_JACKET` |
| `J510M` | `J510M_CHARGER_UNISEX_JACKET`; `J510M_UNISEX_CHARGER_JACKET` |
| `J740L` | `J740L_APEX_WOMENS_JACKET`; `J740L_LADIES_APEX_LIGHTWEIGHT_SOFTSHELL_JACKET` |
| `J750M` | `J750M_EXPEDITION_MENS_JACKET`; `J750M_MEN'S_EXPEDITION_QUILTED_JACKET` |
| `TW1827` | `TW1827_MEN'S_CREW_PULLOVER`; `TW1827_MENS_CREW_PULLOVER` |
| `WP417M` | `WP417M_MEN'S_MILANO_PULLOVER`; `WP417M_MILANO_MENS_PULLOVER` |

### Product taxonomy created

Product Category:

- **Outerwear**

Subcategories:

- **Jackets**
- **Knitwear**
- **Soft Shells**
- **Puffers**
- **Chef Jackets**
- **Fleece**
- **Vests** — reused from the existing shared subcategory

Source naming was normalised:

- `Soft Shell` → **Soft Shells**
- `Soft Shells` → **Soft Shells**
- `Chef Jacket` → **Chef Jackets**

The existing **Vests** subcategory is now shared between **Hi Vis & Workwear** and **Outerwear**, avoiding duplicate taxonomy items.

### New specific Colors created

- **Asphalt Marle/Black**
- **Black Marle**
- **Black/Red**
- **Brick**
- **Cyan**
- **Grey Smoke**
- **Ink Blue**
- **Navy Marle**
- **Sky Blue**
- **White/Black**
- **black/cyan**
- **black/fluoro orange/grey**
- **black/graphite**
- **black/green/grey**
- **black/purple/grey**
- **black/red/grey**
- **black/royal/grey**
- **navy/graphite**

### Color Family relationships

Only clear relationships were assigned:

- **Asphalt Marle/Black → Black**
- **Black Marle → Black**
- **Black/Red → Black + Red**
- **Grey Smoke → Grey**
- **Ink Blue → Blue**
- **Navy Marle → Navy**
- **Sky Blue → Blue**
- **White/Black → White + Black**
- **black/cyan → Black**
- **black/fluoro orange/grey → Black + Orange + Grey**
- **black/graphite → Black**
- **black/green/grey → Black + Green + Grey**
- **black/purple/grey → Black + Purple + Grey**
- **black/red/grey → Black + Red + Grey**
- **black/royal/grey → Black + Grey**
- **navy/graphite → Navy**

**Brick** and **Cyan** were intentionally left without a Color Family rather than assuming Red or Blue.

### Import execution

The 43 eligible products were imported in controlled batches:

- Batch 1: **10**
- Batch 2: **10**
- Batch 3: **10**
- Batch 4: **10**
- Batch 5: **3**

Final QA confirmed all 43 products have:

- Product Category
- at least one Product Subcategory
- at least one Color
- draft status

One QA issue was caught and fixed:

- `J750L — Ladies Expedition Quilted Jacket` initially imported without Gender
- source confirms **Women's**
- Webflow Gender was corrected to **Female**

No Outerwear Product was published.


---

## 2026-09-21 — Polos source audit and Webflow import

Source: `Product (Polos)-Grid view.csv`

Asset inventory: `Total Image Product Assets`

### Summary

- Source rows: **40**
- Non-empty unique SKUs: **39**
- Duplicate non-empty source SKUs: **0**
- Blank-SKU source rows: **1**
- Exact SKU asset matches with one clearly matching folder: **35**
- Asset-SKU collision requiring manual review: **1**
- High-confidence non-exact asset mapping used: **1**
- Unresolved source products excluded: **3**
- Products imported to Webflow: **37**
- All imported items remain **drafts**
- Nothing was published
- Images were not attached because the Product image schema is still pending

### Blank-SKU source product — excluded

One source row has no SKU:

- **Men's City Polo**

No reliable asset-folder mapping could be established without inventing a SKU.

**Current handling:** do not import this product until the client confirms the correct SKU / asset relationship.

### High-confidence manual asset mapping

#### `N2306` — Keira Ladies' Polos

Mapped asset folder:

`N2306 → 2306_KEIRA_LADIES_POLOS`

Reason:

- exact product-name match
- numeric SKU component `2306` matches
- asset folder appears to omit the source prefix `N`

**Status:** high-confidence mapping used for this import.

### Asset-SKU collision: `2151`

Source product:

- `2151 — Silvertech Polo - Ladies`

Two asset folders begin with the same numeric SKU:

- `2151_SILVERTECH_POLO_LADIES`
- `2151_EZYLIN_TUNIC`

Only `2151_SILVERTECH_POLO_LADIES` matches the source Product Name and product type.

**Import handling:** `2151_SILVERTECH_POLO_LADIES` is treated as the valid product asset folder. `2151_EZYLIN_TUNIC` is recorded as an asset-SKU collision and is not associated with the Polo product.

No folder was deleted or renamed.

### Unresolved products — excluded from Webflow

The following source products were intentionally left out because no reliable asset mapping was available:

- `2053 — Silvertech Polo - Men's`
- `1061 — Freshen Polo Men's`
- blank SKU — **Men's City Polo**

No approximate or opposite-product assets were reused.

### Product taxonomy

Product Category:

- **Polos**

The category reuses the existing shared subcategories:

- **Short Sleeve**
- **Long Sleeve**

The existing Short Sleeve / Long Sleeve subcategory records now reference both **Hi Vis & Workwear** and **Polos** where applicable.

No duplicate sleeve subcategories were created.

### Industry normalisation

The source value:

- `Teamwear and Fitness`

is mapped to the existing Webflow Industry:

- **Teamwear & Fitness**

All other source Industry Reference values were mapped to their existing Webflow Industry items.

### Colour canonicalisation

The Polos source contains a large number of specific colour strings.

Obvious duplicate spellings / formatting variants were normalised before references were created, including:

- `mid blue/navy` → **Mid Blue/Navy**
- `Nordic blue/ Navy` → **Nordic Blue/Navy**
- `Royal Blue-Navy` → **Royal Blue/Navy**
- `black/silver` → **Black/Silver**
- `orange` → existing **Orange**

### New colour creation

The staged colour import initially created **89** Color items.

During final QA, four exact duplicate Color names were detected because they had been included in two split creation passes:

- **Nordic Blue/Navy**
- **Ocean Blue**
- **Ocean Blue/Silver**
- **Ocean Marle**

The newer duplicate items were deleted before completion.

**Net new unique Colors retained from Set 6: 85.**

Final QA confirmed there are **no exact duplicate Color names** remaining in the Colors collection.

### Color Family relationships

Color Family links were populated conservatively.

A family was assigned only where the family name is explicitly represented in the specific colour name, for example:

- **Royal Blue/Navy → Blue + Navy**
- **Red/White → Red + White**
- **Black/Charcoal → Black + Charcoal**
- **Green/Navy → Green + Navy**
- **Hot Pink/White → Pink + White**
- **steel grey/black/white → Grey + Black + White**

Colours whose broader family would require interpretation rather than explicit evidence were left without an inferred family.

Both directions were updated:

- **Color → Color Families**
- **Color Family → Colors**

### Source-data discrepancy requiring client confirmation

#### `TW1825 — Women's Signature Long Sleeve Polo`

The Product Name says:

- **Women's Signature Long Sleeve Polo**

but the source `GENDER` field says:

- **Men's**

The Webflow import currently preserves the source Gender value rather than silently correcting it.

**Client confirmation required:** confirm whether `TW1825` should be **Female**.

### Import execution

The 37 eligible products were imported in controlled batches:

- Batch 1: **10**
- Batch 2: **10**
- Batch 3: **10**
- Batch 4: **7**

Batch 1:

- `TW1822`
- `BP2616LS`
- `TW1823`
- `P400MS`
- `TW1825`
- `P400LS`
- `BP2610MS`
- `1062`
- `TW1824`
- `P105MS`

Batch 2:

- `1064`
- `BP2616MS`
- `1164`
- `N2306`
- `2LPS`
- `P901MS`
- `P112LS`
- `P700LS`
- `P112MS`
- `P400ML`

Batch 3:

- `1054`
- `210XL`
- `210`
- `1154`
- `PS91`
- `PS92`
- `P400LL`
- `1161`
- `P227LS`
- `P901LS`

Batch 4:

- `2151`
- `2LCP`
- `BP2610LS`
- `P227MS`
- `1143`
- `1043`
- `1162`

### Final Webflow QA

Final read-back confirms:

- **37** Polos Products exist
- all **37 are drafts**
- no Product is missing Gender
- no Product is missing Category
- no Product is missing Colors
- no Product is missing Subcategories
- no exact duplicate Color names remain

The `TW1825` Gender discrepancy remains intentionally unresolved pending client confirmation.



---

## 2026-09-21 — Promotional Merchandise source audit — pending client confirmation

Source: `Product (Promotional Merchandise)-Grid view.csv`

### Summary

- Source rows: **31**
- Unique SKUs: **31**
- Duplicate source SKUs: **0**
- Blank-SKU rows: **0**
- Source top-level filter: **Promo Merch**
- Source subgroups:
  - **Drinkware** — 9
  - **Bags** — 9
  - **Pens** — 9
  - **Note Books** — 4
- Webflow import status: **Not imported**
- Reason: there is no defensible existing Product Category for this set, and the source Industry taxonomy also requires confirmation.

### Product Category question

Current Product Categories in Webflow are:

- **Accessories**
- **Bottoms**
- **Hi Vis & Workwear**
- **Outerwear**
- **Polos**

The Promotional Merchandise set contains drink bottles, coffee cups, tumblers, bags, pens, notebooks and a wireless charger.

Although some items could loosely be considered accessories, assigning the full set to **Accessories** would mix a distinct promotional-merchandise range into an apparel/accessories taxonomy that currently contains items such as Headwear, Aprons and Belts.

The source itself consistently uses:

- `Promo Merch`

as the top-level filter, with the four clear subgroups listed above.

**Current handling:** do not create a Product Category or import this set until the client confirms whether **Promotional Merchandise / Promo Merch** should become its own Product Category.

### Industry taxonomy question

Every row uses:

- **Promotional Merchandise**

as an `Industry Reference`.

Nine rows also use:

- **Sustainable**

as an `Industry Reference`.

Neither **Promotional Merchandise** nor **Sustainable** currently exists in the Webflow Industries collection.

These values also do not read like conventional industries in the same sense as Corporate, Hospitality, Healthcare, Retail, Government, etc.:

- **Promotional Merchandise** appears to describe the product range itself.
- **Sustainable** appears to describe a product attribute / filter rather than a commercial industry.

**Current handling:** do not create either value as a Webflow Industry until the client confirms the intended taxonomy.

### Client confirmation required

Recommended question:

> We’ve reached the Promotional Merchandise product set. All 31 products are grouped under `Promo Merch`, with subgroups for Drinkware, Bags, Pens and Note Books, but we don’t currently have a matching Product Category in the new CMS. Should **Promotional Merchandise** be added as a new Product Category?
>
> We also noticed `Promotional Merchandise` is being used as an Industry on every row, and `Sustainable` is used as an Industry on 9 products. Our current Industries are commercial sectors such as Corporate, Hospitality, Healthcare, Retail, etc. Should either of these genuinely be Industries, or should they instead be treated as product categories / filters / attributes?

Until this is confirmed, Set 7 remains intentionally unimported.

### CMS cleanup noted during review

During the Set 7 category check, an unused duplicate **Polos** Product Category created during the split Set 6 workflow was found.

- duplicate category had **0 Products**
- canonical Polos category already contains the imported Set 6 Products
- unused duplicate Polos category was deleted

No Product data was affected.


---

## 2026-09-21 — Full taxonomy reconciliation — Batch 1 (source rows 1–100)

This is the first bounded reconciliation pass across the fresh 15-set product export.

Scope:

- **100 source rows**
- Accessories: **47 rows**
- Bottoms: **32 rows**
- First Nations: **14 rows**
- Hi Vis & Workwear: **first 7 rows**
- After within-scope duplicate SKU merging: **96 unique products**

This review did **not** modify Webflow.

### Fixed Product Category model

The approved seven Product Categories are treated as fixed:

- Tops
- Bottoms
- Outerwear
- Suiting
- Workwear & Hi-vis
- Shoes
- Accessories

All 96 unique products in this batch fit this model.

Batch 1 category allocation:

- **Accessories:** 46 products
- **Bottoms:** 29 products
- **Tops:** 14 products
- **Workwear & Hi-vis:** 7 products

No additional Product Category is required.

### Reusable Product Subcategories / filters

Subcategories are treated as reusable filter tags with two-way multi-reference relationships to Product Categories.

Required by this batch:

**Accessories**
- Headwear
- Aprons
- Belts

**Bottoms**
- Pants
- Shorts
- Skirts
- Chinos

**Tops**
- Polos
- Short Sleeve
- First Nations

**Workwear & Hi-vis**
- Workwear
- Shirts
- Long Sleeve
- Short Sleeve

Shared values such as **Short Sleeve** should exist once and be linked to every applicable Product Category.

### Fixed Industry model

Only the ten approved Figma Industries are considered valid:

- Aged Care
- Automotive
- Workwear & Hi-Vis
- Retail
- Corporate
- Hospitality
- Healthcare
- Education
- Teamwear & Fitness
- Government

Within this batch:

- **82 / 96 products** can be assigned entirely to those approved Industries.
- **14 / 96 products** currently have no approved Industry assignment.

Non-approved source values:

- **Services** appears on 18 products.
- **Beauty** appears on 11 products.

Every product carrying Services or Beauty in this batch also has at least one approved Industry, so these two source values can be dropped without leaving those products Industry-less.

The only unresolved Industry cases are the **14 First Nations products**, whose source Industry value is only `First Nations`.

**Client decision required:** define which of the approved ten Industries should apply to the First Nations range, or confirm that these products may intentionally have no Industry.

### Source duplicate SKUs

Four SKUs occur more than once within the first 100 source rows:

- `A33`
- `BS724M`
- `BS724L`
- `BS022L`

These should resolve to one Product per SKU, preserving the union of supported taxonomy/reference values and the most complete descriptive content.

### Asset reconciliation

Across the 96 unique products:

- **72** have exact SKU-folder matches
- **11** have high-confidence manual / naming-variant matches
- **13** have no safe corresponding asset folder

Usable asset coverage:

- **83 / 96 products**
- **86.5%**

#### High-confidence non-exact mappings

- `AS1130 → 1130_ACCESS_CAP`
- `CA3P → CA3PSO_EZY_ PANT`
- `RGS264L-BIZ → RGS264L_TRAVELLER_WOMEN'S_CHINO_SKIRT`
- `BRIGHT-YARN → BRIGHT_YARN_A_BRIGHT_FUTURE_ESSENCE_POLO_SHIRT`
- `BRIGHT-YARN- UNISEX → BRIGHT_YARN_UNISEX_A_BRIGHT_FUTURE_ESSENCE_POLO_SHIRT`
- `FAMILY-YARN-UNISEX → FAMILY_YARN_UNISEX_FAMILY_BLACK_BAMBOO_(SIMPSON)_POLO_SHIRT`
- `FUTURE-YARN-UNISEX → FUTURE_YARN_UNISEX_FUTURE_DREAMING_ESSENCE_POLO_SHIRT`
- `GUIDING-YARN- UNISEX → GUIDING_YARN_UNISEX_GUIDING_LIGHT_BLACK_BAMBOO_(SIMPSON)_POLO_SHIRT`
- `KNOWLEDGE-YARN-UNISEX → KNOWLEDGE_YARN_UNISEX_KNOWLEDGE_HOLDERS_BLACK_BAMBOO_(SIMPSON)_POLO_SHIRT`
- `LEGACY-YARN-UNISEX → LEGACY_YARN_UNISEX_LEGACY_POLO_SHIRT`
- `MOUNTAINS-YARN-UNISEX → MOUNTAINS_YARN_UNISEX_MOUNTAINS_WHITE_BAMBOO_(SIMPSON)_POLO_SHIRT`

#### Products without safe asset matches

Accessories:

- `BB248M`
- `RA572M`
- `99300`
- `H1026`
- `HB004`
- `CH333`
- `BA93`

First Nations:

- `FAMILY-YARN`
- `FUTURE-YARN`
- `GUIDING-YARN`
- `KNOWLEDGE-YARN`
- `LEGACY-YARN`
- `MOUNTAINS-YARN`

For those six First Nations products, only corresponding Unisex asset folders were identified. Those images should not be reused for the non-Unisex products without client confirmation.

### Batch 1 conclusion

- Fixed seven Product Categories: **works**
- Reusable multi-reference Subcategories: **works**
- Fixed ten Industries: **works for 82 / 96 products**
- Unresolved Industry assignment: **14 First Nations products**
- Asset coverage: **83 / 96 usable**
- No Webflow changes were made during this reconciliation pass


---

## 2026-09-21 — Full taxonomy reconciliation — Batch 2 (source rows 101–200)

This is the second bounded reconciliation pass across the fresh 15-set product export.

Scope:

- **100 source rows**
- Hi Vis & Workwear: source rows **8–90** = 83 rows
- Outerwear: source rows **1–17** = 17 rows
- Product identities after duplicate / blank-SKU reconciliation: **82**
- Product identities already encountered in Batch 1: **7**
- Genuinely new products added by this batch: **75**
- Cumulative unique product identities after rows 1–200: **171**

This review did **not** modify Webflow.

### Cross-batch duplicate / reconciliation handling

Seven Hi Vis & Workwear SKUs in this batch are second occurrences of products already seen in Batch 1:

- `ZW460`
- `ZW765`
- `ZW468`
- `ZW465`
- `ZW760`
- `ZW121`
- `ZW120`

Their Batch 2 rows should merge into the existing product identity rather than create new products.

One additional blank-SKU row appears in this batch:

- **Women's Outdoor Long Sleeve Shirt**

This is the same product identity as `ZW760` and should be folded into that record rather than treated as a separate product.

Within Batch 2 itself, 17 additional non-empty SKUs occur twice:

- `ZWL120`
- `SW19A`
- `6HVSZ`
- `6HVSV`
- `ZP820`
- `ZV245`
- `ZT210`
- `BPC6008`
- `ZP504`
- `ZP230`
- `ZP730`
- `ZP735`
- `ZP935`
- `BPC6088T`
- `ZP923`
- `ZP733`
- `BPC6334T`

These resolve to one product per SKU, preserving the union of supported source values.

### Fixed Product Category model

The approved seven Product Categories remain sufficient.

Batch 2 allocation:

- **Workwear & Hi-vis:** 65 product identities
- **Outerwear:** 17 product identities

No additional top-level Product Category is required.

### Reusable Product Subcategories / filters

Subcategories continue to be treated as reusable filter tags with two-way Product Category relationships.

Required by Batch 2:

**Workwear & Hi-vis**
- Workwear
- Hi Vis
- Shirts
- Pants
- Shorts
- Jackets
- Vests
- Safety Vests
- Long Sleeve
- Short Sleeve

**Outerwear**
- Jackets
- Soft Shells
- Puffers
- Knitwear
- Chef Jackets

Source normalisation applied conceptually:

- `Shirt` → **Shirts**
- `Vest` / `Vests` → **Vests**
- `Safety Vest` → **Safety Vests**
- `Chef Jacket` → **Chef Jackets**

The raw `Outerwear` marker inside Extra Filter Reference is not required as a duplicate filter when the Product Category / specific garment filter already represents the product.

### Fixed Industry model

Only the ten approved Figma Industries are treated as valid:

- Aged Care
- Automotive
- Workwear & Hi-Vis
- Retail
- Corporate
- Hospitality
- Healthcare
- Education
- Teamwear & Fitness
- Government

All **82 / 82 product identities** in this batch have at least one approved Industry.

Approved Industry references represented in Batch 2:

- **Workwear & Hi-Vis:** 65 products
- **Corporate:** 14
- **Government:** 14
- **Healthcare:** 14
- **Retail:** 14
- **Automotive:** 9
- **Hospitality:** 2

Non-approved source value:

- **Services:** 15 products

Every product carrying Services in this batch already has at least one approved Industry, so Services can be dropped without leaving any product Industry-less.

**Batch 2 unresolved Industry count: 0.**

### Asset reconciliation

Across the 82 product identities in this batch:

- **65** have exact SKU-prefix asset matches
- of those, **5 SKUs have multiple matching asset folders**
- **17** have no safe exact or high-confidence manual asset mapping

Batch-scope usable asset coverage:

- **65 / 82 = 79.3%**

Because all seven cross-batch repeated products have valid exact assets, the 75 genuinely new products contributed by Batch 2 have:

- **58 / 75 usable asset matches = 77.3%**
- **17 / 75 unresolved asset products**

No non-exact mapping in this batch was judged strong enough to use safely.

#### Duplicate asset-folder cases

These are audit-only. No folders should be merged, renamed, or deleted.

- `2513 — Ladies Olympus Soft Shell Jacket`
  - `2513_LADIES_OLYMPUS_SOFT_SHELL_JACKET`
  - `2513_OLYMPUS_LADY_JACKETS`

- `BJ2602L — Women's Tailor Jacket`
  - `BJ2602L_TAILOR_WOMENS_JACKET`
  - `BJ2602L_WOMEN'S_TAILOR_JACKET`

- `J740L — Women's Apex Lightweight Softshell Jacket`
  - `J740L_APEX_WOMENS_JACKET`
  - `J740L_LADIES_APEX_LIGHTWEIGHT_SOFTSHELL_JACKET`

- `CO342LJ — Nova Women's Knit Jacket`
  - `CO342LJ_NOVA_WOMEN'S_KNIT_JACKET`
  - `CO342LJ_NOVA_WOMENS_ZIP_FRONT_JUMPER`

- `J510M — Charger Unisex Jacket`
  - `J510M_CHARGER_UNISEX_JACKET`
  - `J510M_UNISEX_CHARGER_JACKET`

#### Products without safe asset matches

Hi Vis & Workwear:

- `6HVSZ — Hi Vis Zip Safety Vest`
- `ZJ240 — Unisex Streetworx Hooded Puffer Jacket`
- `ZT210 — Unisex Streetworx Lightweight 1/4 Zip Polar Fleece`
- `ZT867 — Unisex Streetworx Water Resistant Hoodie With Segmented Tape`
- `BJ6078T — Taped Two Tone Hi Vis 3 In 1 Soft Shell Jacket`
- `BJ6766T — Taped Hi Vis Recycled Rain Shell Jacket`
- `ZJ532 — Men's Hi Vis 4 In 1 Waterproof Jacket`
- `ZJ616 — Men's Hi Vis X Back Taped 4 In 1 Waterproof Jacket`
- `ZJ553 — Unisex Hi Vis Antarctic Softshell Taped Jacket`
- `ZJ770 — Women's Hi Vis Nsw Rail X Back 2 In 1 Softshell Jacket`
- `ZV228 — Unisex Hi Vis Waterproof Reversible Vest`
- `ZT476 — Unisex Hi Vis Half Zip Pullover`
- `ZT640 — Unisex Hi Vis Vic Rail 1/4 Zip Pullover`
- `ZT462 — Hi Vis Polar Fleece Jumper - Shoulder Taped`
- `6HVPF — Hi Vis 1/2 Zip Polar Fleece`

Outerwear:

- `1513 — Men's Olympus Soft Shell Jacket`
- `JK63 — Men's Sustainable Softshell Corporate Jacket`

Similar-looking folders exist for some unresolved products, but they represent different SKUs, genders, or product variants and were therefore **not** treated as valid asset mappings.

### Batch 2 conclusion

- Fixed seven Product Categories: **works**
- Reusable multi-reference Subcategories: **works**
- Fixed ten Industries: **works for 82 / 82 products**
- Non-approved Services reference can be removed safely in this batch
- Asset coverage: **65 / 82 usable**
- Genuinely new products contributed: **75**
- Cumulative unique products reconciled through source row 200: **171**
- No Webflow changes were made during this reconciliation pass


---

## 2026-09-21 — Full taxonomy reconciliation — Batch 3 (source rows 201–300)

This is the third bounded reconciliation pass across the fresh 15-set product export.

Scope:

- **100 source rows**
- Outerwear: remaining **39 rows**
- Polos: all **40 rows**
- Promotional Merchandise: first **21 rows**
- Product identities after within-batch duplicate SKU reconciliation: **97**
- Product identities already encountered in Batch 2: **1**
- Genuinely new products added by this batch: **96**
- Cumulative unique product identities after rows 1–300: **267**

This review did **not** modify Webflow.

### Source duplicate / cross-batch reconciliation

Three Outerwear SKUs occur twice within Batch 3:

- `CO342MJ`
- `CO343LV`
- `CO343MV`

These resolve to one Product identity per SKU, preserving the union of supported reference/filter values and the most complete source content.

One additional Outerwear product was already encountered in Batch 2:

- `CO342LJ — Nova Women's Knit Jacket`

Its Batch 3 occurrence should merge into the existing product identity rather than create a second Product.

The Polos source also contains one blank-SKU product:

- **Men's City Polo**

It remains a valid source product identity for taxonomy review, but it has no safe SKU/asset mapping and should not be imported until the client confirms the SKU.

### Fixed Product Category model

The approved seven Product Categories remain sufficient.

Batch 3 allocation:

- **Outerwear:** 36 product identities
- **Tops:** 40 product identities from the Polos set
- **Accessories:** 21 product identities from Promotional Merchandise

No additional top-level Product Category is required.

### Reusable Product Subcategories / filters

Subcategories continue to be treated as reusable filter tags with two-way Product Category relationships.

Required by Batch 3:

**Outerwear**
- Jackets
- Vests
- Knitwear
- Soft Shells
- Puffers
- Fleece
- Chef Jackets

**Tops**
- Polos
- Short Sleeve
- Long Sleeve

**Accessories**
- Promotional Merchandise
- Drinkware
- Bags
- Pens
- Notebooks
- Sustainable

Source normalisation applied conceptually:

- `Chef Jacket` → **Chef Jackets**
- `Soft Shell` / `Soft Shells` → **Soft Shells**
- `Promo Merch` → **Promotional Merchandise**
- `Note Books` → **Notebooks**

The **Sustainable** filter is required on the two Promotional Merchandise products in this slice whose source data includes Sustainable. It should be the same reusable Sustainable subcategory used across all applicable Product Categories.

### Fixed Industry model

Only the ten approved Figma Industries are treated as valid:

- Aged Care
- Automotive
- Workwear & Hi-Vis
- Retail
- Corporate
- Hospitality
- Healthcare
- Education
- Teamwear & Fitness
- Government

Across the 97 Batch 3 product identities:

Approved Industry references include:

- **Corporate:** 62
- **Healthcare:** 47
- **Government:** 46
- **Retail:** 45
- **Hospitality:** 14
- **Education:** 14
- **Workwear & Hi-Vis:** 4
- **Automotive:** 4
- **Teamwear & Fitness:** 1

Non-approved source values:

- **Services:** 59 products
- **Promotional Merchandise:** 21 products
- **Sustainable:** 2 products

All products carrying **Services** also have at least one approved Industry, so Services can be dropped safely.

All **21 Promotional Merchandise products** in this slice have **no approved Industry assignment**. Their source Industry is Promotional Merchandise, with two also carrying Sustainable.

**Client decision required:** define which of the approved ten Industries should apply to Promotional Merchandise products, or confirm that these products may intentionally have no Industry.

Batch 3 unresolved Industry count:

- **21 / 97 products**
- all are Promotional Merchandise products

### Asset reconciliation

Across the 97 Batch 3 product identities:

- **64** have exact SKU-prefix asset matches
- **2** have high-confidence manual / naming-variant mappings
- **31** have no safe asset mapping

Usable asset coverage:

- **66 / 97 = 68.0%**

Excluding the one cross-batch product already counted previously, the 96 genuinely new products contributed by Batch 3 have:

- **65 / 96 usable asset matches = 67.7%**
- **31 / 96 unresolved asset products**

#### High-confidence non-exact mappings

- `CH230ML-BIZ — Al Dente Men's Chef Jacket`
  - `CH230ML-BIZ → CH230ML_AL_DENTE_MEN'S_CHEF_JACKET`
  - exact product-name match and matching base SKU; source adds `-BIZ`

- `N2306 — Keira Ladies' Polos`
  - `N2306 → 2306_KEIRA_LADIES_POLOS`
  - exact product-name match and matching numeric SKU; asset folder omits the source `N` prefix

#### Duplicate asset-folder cases

These are audit-only. No folders should be merged, renamed, or deleted.

Outerwear:

- `J307L — Ladies Geneva Jacket`
  - `J307L_GENEVA_WOMENS_JACKET`
  - `J307L_LADIES_GENEVA_JACKET`

- `J750M — Men's Expedition Quilted Jacket`
  - `J750M_EXPEDITION_MENS_JACKET`
  - `J750M_MEN'S_EXPEDITION_QUILTED_JACKET`

- `CH232ML — Zest Men's L/S Chef Jacket`
  - `CH232ML_ZEST_MENS_LS_CHEF_JACKET`
  - `CH232ML_ZEST_MENS_LS_CHEF_JACKET (1)`

- `J211L — Alpine Ladies Puffer Vest`
  - `J211L_ALPINE_LADIES_PUFFER_VEST`
  - `J211L_ALPINE_WOMENS_VEST`

- `CO343MV — Nova Men's Knit Vest`
  - `CO343MV_NOVA_MEN'S_KNIT_VEST`
  - `CO343MV_NOVA_MEN'S_ZIP_FRONT_VEST`
  - `CO343MV_NOVA_MENS_ZIP_FRONT_VEST`

- `CO342LJ — Nova Women's Knit Jacket`
  - `CO342LJ_NOVA_WOMEN'S_KNIT_JACKET`
  - `CO342LJ_NOVA_WOMENS_ZIP_FRONT_JUMPER`

- `TW1827 — Men's Crew Pullover`
  - `TW1827_MEN'S_CREW_PULLOVER`
  - `TW1827_MENS_CREW_PULLOVER`

- `WP417M — Men's Milano Pullover`
  - `WP417M_MEN'S_MILANO_PULLOVER`
  - `WP417M_MILANO_MENS_PULLOVER`

#### Asset-SKU collision

`2151 — Silvertech Polo - Ladies` has two SKU-prefix folders:

- `2151_SILVERTECH_POLO_LADIES` — correct matching product
- `2151_EZYLIN_TUNIC` — unrelated product using the same numeric prefix

Only the Silvertech Polo folder is considered valid for product `2151`.

#### Products without safe asset matches

Outerwear:

- `J830M — Men's Apex Vest`
- `WV619M — Men's Milano Vest`
- `J29123 — Ladies Soft Shell Vest`
- `CO343LV — Nova Women's Knit Vest`
- `J213L — Expedition Women's Vest`
- `RJP266M — Osaka Men's Pineapple Knit Jumper`
- `LP618L — Ladies Milano Pullover`

Polos:

- blank SKU — **Men's City Polo**
- `2053 — Silvertech Polo - Men's`
- `1061 — Freshen Polo Men's`

Promotional Merchandise:

- `S909 — Summit 750ml Drink Bottle`
- `S400 — Oakleigh Coffee Cup (354mL)`
- `S990 — Arlo 1L Glass Water Bottle`
- `S777 — Byron 1L Drink Bottle`
- `S895 — Sunrise Smoothie 500mL Tumbler`
- `S901 — Allegra 750ml Bottle`
- `S3101 — Vidro 750ml Bottle`
- `RB1053 — The Buddy Drawstring Bag`
- `RB1043 — Willow Natural Tote`
- `RB1040 — Rara Cooler Bag`
- `D605.R — ECO NOVA Computer Backpack`
- `P093 — The Gravity 3+1 Metal Pen`
- `P131 — The Heritage Wooden + Metal Ball Pen`
- `P381 — Paper Pen`
- `P603 — SmartScribe Re-AL NFC Pen`
- `P602 — Monarch Re-AL Ball Pen`
- `P734 — RABS Mini Ballpoint Pen`
- `P740 — Cambridge Colourful Gel Ink Pen`
- `P129 — Tirana Pen`
- `F501 — Bloa Pen`
- `LL9753 — Stone Paper Notebook`

No Promotional Merchandise product in this Batch 3 slice has a safe asset match in the supplied asset package.

### Batch 3 conclusion

- Fixed seven Product Categories: **works**
- Reusable multi-reference Subcategories: **works**
- Polos fit under **Tops**
- Promotional Merchandise fits under **Accessories**
- Sustainable works as a reusable subcategory/filter
- Fixed ten Industries: **works for 76 / 97 products**
- Unresolved Industry assignment: **21 Promotional Merchandise products**
- Services can be removed safely from this batch
- Asset coverage: **66 / 97 usable**
- Genuinely new products contributed: **96**
- Cumulative unique products reconciled through source row 300: **267**
- No Webflow changes were made during this reconciliation pass


---

## 2026-09-21 — Full taxonomy reconciliation — Batch 4 (source rows 301–400)

This is the fourth bounded reconciliation pass across the fresh 15-set product export.

Scope:

- **100 source rows**
- Promotional Merchandise: remaining **10 rows**
- Scrubs: all **32 rows**
- Shirts: first **58 rows**
- Product identities after duplicate / blank-SKU reconciliation: **81**
- Product identities already encountered in earlier batches: **19**
- Genuinely new products added by this batch: **62**
- Cumulative unique product identities after rows 1–400: **329**

This review did **not** modify Webflow.

### Source duplicate / blank-SKU reconciliation

The Scrubs set contains 15 duplicated non-empty SKUs in this batch:

- `CL541LL`
- `CL542UL`
- `CSP042LL`
- `CSP047LL`
- `CSP047ML`
- `CSP241LL`
- `CST043LS`
- `CST043MS`
- `CST141LS`
- `CST141MS`
- `CST245LS`
- `CU543LS`
- `CU544US`
- `M7660`
- `M9710`

The Shirts slice contains three duplicated non-empty SKUs:

- `1637HL`
- `1637S`
- `1637WZ`

These resolve to one Product identity per SKU, preserving the union of supported source values.

Two blank-SKU rows occur:

1. **Women's Avery Multi-Pocket Straight Leg Pant**
   - no SKU in the source
   - unique asset folder strongly identifies the product as:
     `CSP944LL_WOMEN'S_AVERY_MULTI_POCKET_STRAIGHT_LEG_PANT`
   - treat this as a high-confidence asset identity, but do not silently invent the missing source SKU without client/source confirmation

2. **Womens Outdoor Long Sleeve Shirt**
   - same product identity as existing `ZW760 — Women's Outdoor L/S Shirt`
   - fold into `ZW760`; do not create a separate Product

### Cross-batch repeated products

Nineteen Shirts SKUs in Batch 4 were already encountered in the Hi Vis & Workwear source and therefore must not create duplicate Products:

- `6HDNL`
- `BS1896`
- `BS6266XT`
- `BS6896`
- `ZW115`
- `ZW120`
- `ZW121`
- `ZW128`
- `ZW229`
- `ZW400`
- `ZW460`
- `ZW465`
- `ZW468`
- `ZW680`
- `ZW760`
- `ZW765`
- `ZW815`
- `ZW835`
- `ZWL120`

The blank Outdoor Long Sleeve Shirt row also folds into the already-listed `ZW760` identity.

### Fixed Product Category model

The approved seven Product Categories remain sufficient.

Batch 4 allocation:

- **Tops:** 43 product identities
- **Workwear & Hi-vis:** 20 product identities
- **Accessories:** 10 product identities
- **Bottoms:** 8 product identities

No additional top-level Product Category is required.

Category handling rules validated in this batch:

- Scrub tops → **Tops**
- Scrub pants → **Bottoms**
- Scrubs remains one reusable Subcategory linked to both Tops and Bottoms
- ordinary Shirts → **Tops**
- Shirts whose source Industry is Hi Vis & Workwear → **Workwear & Hi-vis**
- Promotional Merchandise → **Accessories**

### Reusable Product Subcategories / filters

Subcategories continue to be treated as reusable filter tags with two-way Product Category relationships.

Required by Batch 4:

**Accessories**
- Promotional Merchandise
- Bags
- Drinkware
- Notebooks
- Sustainable

**Tops**
- Scrubs
- Shirts
- Long Sleeve
- Short Sleeve
- Sustainable

**Bottoms**
- Scrubs

**Workwear & Hi-vis**
- Shirts
- Long Sleeve
- Short Sleeve
- Sustainable

Important taxonomy decision confirmed by this batch:

- do **not** create separate `Scrub Tops` and `Scrub Pants` filters unless the client explicitly wants them
- use one **Scrubs** Subcategory related to both Tops and Bottoms
- the fixed Product Category already distinguishes whether the item is a top or bottom

Likewise, **Sustainable** remains one reusable Subcategory/filter and is linked to every Product Category where sustainable products occur.

### Fixed Industry model

Only the ten approved Figma Industries are treated as valid:

- Aged Care
- Automotive
- Workwear & Hi-Vis
- Retail
- Corporate
- Hospitality
- Healthcare
- Education
- Teamwear & Fitness
- Government

Across the 81 Batch 4 product identities, approved Industry references include:

- **Corporate:** 31
- **Education:** 31
- **Government:** 31
- **Healthcare:** 20
- **Workwear & Hi-Vis:** 20
- **Automotive:** 9
- **Hospitality:** 5

Non-approved source values:

- **Services:** 31 product identities
- **Promotional Merchandise:** 10
- **Sustainable:** 7

Every Product carrying **Services** in this batch already has at least one approved Industry, so Services can be dropped safely.

The only Industry-unresolved products are the **10 remaining Promotional Merchandise products**. Their source Industry values are Promotional Merchandise, with seven also carrying Sustainable.

**Client decision required:** define which approved Industries apply to Promotional Merchandise products, or confirm that Promotional Merchandise products may intentionally have no Industry.

Batch 4 unresolved Industry count:

- **10 / 81 products**
- all are Promotional Merchandise products

### Asset reconciliation

Across the 81 Batch 4 product identities:

- **62** have exact SKU-prefix asset matches
- **4** have strong manual / naming-variant asset matches
- **15** remain without a safe asset mapping

Usable asset coverage:

- **66 / 81 = 81.5%**

All 19 cross-batch repeated products have valid exact asset matches.

For the **62 genuinely new products** contributed by Batch 4:

- **47 / 62 usable asset matches = 75.8%**
- **15 / 62 unresolved asset products**

#### High-confidence manual / naming-variant matches

- blank SKU — **Women's Avery Multi-Pocket Straight Leg Pant**
  - asset: `CSP944LL_WOMEN'S_AVERY_MULTI_POCKET_STRAIGHT_LEG_PANT`
  - exact product-name match; source SKU is missing

- `1520L — Premium Poplin Long Sleeve Shirt`
  - asset: `1520WL_PREMIUM_POPLIN_LONG_SLEEVE_SHIRT`
  - same base numeric SKU and exact product name; asset code contains an additional `W`

- `2103L — Ashton Cotton Oxford Shirt`
  - asset: `2103WL_ASHTON_COTTON_OXFORD_SHIRT`
  - same base numeric SKU and exact product name; asset code contains an additional `W`

- `1701L — Balmoral Royal Oxford Shirt`
  - asset: `1701WL_BALMORAL_ROYAL_OXFOR_SHIRT`
  - same base numeric SKU and exact product name; asset code contains an additional `W`

These mappings should be retained in the audit trail because the folder SKU is not textually identical to the source SKU.

#### Duplicate asset-folder cases

These are audit-only. No folders should be renamed, merged, or deleted.

- `LB3601 — Ladies Plain Oasis Short Sleeve Shirt`
  - `LB3601_LADIES_PLAIN_OASIS_SHORT_SLEEVE_SHIRT`
  - `LB3601_Womens_Oasis_Short_Sleeve_Shirt`

- `S421LL — Womens Soul Long Sleeve Shirt`
  - `S421LL_Soul_Womens_Long_Sleeve_Shirt`
  - `S421LL_WOMEN'S_SOUL_LONG_SLEEVE_SHIRT`
  - `S421LL_Womens_Soul_Long_Sleeve_Shirt`

- `RS968LS — Womens Charlie S/S Shirt`
  - `RS968LS_WOMEN'S_CHARLIE_S_S_SHIRT`
  - `RS968LS_WOMENS_CHARLIE_SS_SHIRT`

#### Products without safe asset matches

Promotional Merchandise:

- `LL9757 — Amazon Bamboo Notebook`
- `LL0944 — Tourist A5 Notebook`
- `LL0226 — Arc Eco Square Wireless Charger`
- `LL0461 — Vienna Coffee Cup / Snap Lid / Cork Band`
- `LL0427 — Vienna Coffee Cup / Silicone Lid`
- `5198 — Urban Sports Backpack`
- `BR1013 — Bellroy Classic Daypack`
- `DA1007 — Darani GRS Recycled Canvas Anti-Theft 15" 21L Laptop Backpack`
- `DA1003 — Darani 15" 19L Computer Backpack In Repreve Recycled Material`
- `TL1001 — Thule Achiever 16" Laptop Backpack`

Scrubs:

- `M9710 — Men's V-Neck Contrast Trim Scrub Top`
  - the asset package contains `M7650_MEN'S_V_NECK_CONTRAST_TRIM_SCRUB_TOP`
  - product name matches closely, but the SKU is materially different; do not treat as a safe mapping without confirmation

Shirts:

- `1712L — Oxford Check Long Sleeve Shirt`
- `1899L — Bradford Fine Oxford Long Sleeve Slim Fit Shirt`
  - nearby `1899WL` folders are explicitly Women's and are not safe to reuse
- `RS070ML — Noah L/S Shirt`
- `W47 — Ladies Miller Short Sleeve Shirt`
  - nearby `W47Q` asset is a Ladies Miller 3/4 Sleeve Shirt and is therefore a different product

### Batch 4 conclusion

- Fixed seven Product Categories: **works**
- Reusable multi-reference Subcategories: **works**
- Scrubs works cleanly as one shared filter across Tops and Bottoms
- Sustainable works cleanly as a reusable filter
- Fixed ten Industries: **works for 71 / 81 products**
- Unresolved Industry assignment: **10 Promotional Merchandise products**
- Services can be removed safely from this batch
- Asset coverage: **66 / 81 usable**
- Genuinely new products contributed: **62**
- Cumulative unique products reconciled through source row 400: **329**
- No Webflow changes were made during this reconciliation pass


---

## 2026-09-21 — Full taxonomy reconciliation — Batch 5 (source rows 401–500)

This is the fifth bounded reconciliation pass across the fresh 15-set product export.

Scope:

- **100 source rows**
- Shirts: final **5 rows**
- Shoes: all **14 rows**
- Suiting: all **40 rows**
- Sustainable: first **41 rows**
- Product identities after within-batch duplicate / cross-set reconciliation: **91**
- Product identities already encountered in Batches 1–4: **30**
- Genuinely new products added by this batch: **61**
- Cumulative unique product identities after rows 1–500: **390**

This review did **not** modify Webflow.

### Duplicate / cross-set reconciliation

Within Batch 5, the following product identities appear more than once:

- `1765WJ — Women's Washable One Button Jacket`
  - appears twice in Suiting
- `1762WT — Women's Washable Slim Leg Pant`
  - appears twice in Suiting
- `CU544US — Unisex Pulse V-Neck Scrub Top`
  - appears twice in Sustainable
- `BB2606L — Women's Soft Stretch Pant`
  - appears in Suiting and Sustainable
- `RGP408M — Renew Men's Adjustable Waist Straight Leg Pant`
  - appears in Suiting and Sustainable
- `RGP407M — Renew Men's Slim Fit Flat Front Pant`
  - appears in Suiting and Sustainable
- `RGS403L — Renew Women's Functional Pencil Skirt`
  - appears in Suiting and Sustainable
- `RGP404L — Renew Women's Tapered Adjustable Waist Pant`
  - appears in Suiting and Sustainable
- `RGP406L — Renew Women's 7/8 Mid-Waist Slim Leg Pant`
  - appears in Suiting and Sustainable

Thirty Batch 5 identities had already appeared in earlier batches and therefore must merge into the existing Product identity rather than create a second Product.

These include Bottoms/Suiting overlaps, Scrubs/Sustainable overlaps, Polos/Sustainable overlaps, Outerwear/Sustainable overlaps, and Accessories/Sustainable overlaps.

### Fixed Product Category model

The approved seven Product Categories remain sufficient.

Batch 5 allocation:

- **Suiting:** 38 product identities
- **Tops:** 28
- **Shoes:** 14
- **Bottoms:** 5
- **Outerwear:** 3
- **Accessories:** 3

No additional top-level Product Category is required.

Important precedence rules continue to hold:

- products appearing in both Bottoms and Suiting use **Suiting** as the primary Product Category
- Sustainable does not become a Product Category; it remains a reusable Subcategory/filter
- Scrub tops/tunics remain under **Tops**
- Scrub pants remain under **Bottoms**

### Reusable Product Subcategories / filters

Required / validated by Batch 5:

**Tops**
- Shirts
- Polos
- Tees
- Scrubs
- Tunics
- Short Sleeve
- Long Sleeve
- Sustainable

**Bottoms**
- Pants
- Scrubs
- Sustainable

**Outerwear**
- Jackets
- Soft Shells
- Sustainable

**Suiting**
- Blazers
- Trousers
- Skirts
- Dresses
- Sustainable

**Accessories**
- Headwear
- Sustainable

**Shoes**
- no additional source-supported Subcategory required in this batch

For Suiting, **Trousers** is the preferred Suiting filter rather than adding a redundant Pants filter purely because some of the same SKUs also appeared in the Bottoms source.

The Sustainable set confirms the intended two-way filter model: Sustainable products span Tops, Bottoms, Outerwear, Suiting and Accessories while retaining their normal primary Product Category.

### Fixed Industry model

Only the ten approved Figma Industries are treated as valid:

- Aged Care
- Automotive
- Workwear & Hi-Vis
- Retail
- Corporate
- Hospitality
- Healthcare
- Education
- Teamwear & Fitness
- Government

All **91 / 91 product identities** in Batch 5 have at least one approved Industry after references are merged across duplicate/cross-listed source records.

Approved Industry usage represented in Batch 5 includes:

- **Corporate:** 71
- **Government:** 66
- **Healthcare:** 22
- **Education:** 20
- **Retail:** 12
- **Workwear & Hi-Vis:** 11
- **Hospitality:** 5
- **Teamwear & Fitness:** 4

Non-approved source values:

- **Services:** 67 product identities
- **Beauty:** 8

Every product carrying Services or Beauty in this batch also has at least one approved Industry, so both values can be dropped safely.

**Batch 5 unresolved Industry count: 0.**

No additional Industry is required.

### Asset reconciliation

Across the 91 Batch 5 product identities:

- **66** have exact SKU-prefix asset-folder matches
- **1** uses a previously established high-confidence manual mapping
- **24** have no safe asset mapping

Usable asset coverage:

- **67 / 91 = 73.6%**

For the **61 genuinely new products** contributed by Batch 5:

- **39 / 61** have usable exact assets
- **22 / 61** are unresolved
- usable new-product coverage: **63.9%**

#### High-confidence mapping carried forward

- `CA3P — So Ezy Pant`
  - `CA3P → CA3PSO_EZY_ PANT`

This mapping was already established in the Bottoms audit and remains the valid asset relationship.

### Shoes — complete asset gap

All **14 Shoes products** in this set have no matching asset folder in the supplied asset package:

- `49-430 — Slip On Shoe`
- `440 — Premium Elastic Sided Boot W/ Scuff Cap`
- `49-445Z — Women's Black Zip Sided Boot`
- `49-450Z — Women’s Stone Zip Sided Low-Cut Boot`
- `49-432Z — Women's Wheat Zip Sided Boot`
- `630797W — Women's Tornado`
- `34-652 — Men's Black Lace Up Derby Shoe`
- `45-627 — Men's Brown Elastic Sided Boot`
- `ROLLIE-CLUB — Men's Courtclub`
- `ROLLIE-DERBY — Men’s Derby`
- `SC01535 — Women's Court Club`
- `SC00129 — Women's Derby City`
- `261 — Men's Zipsider Boot`
- `240 — Elastic Sided Boot`

**Client / source follow-up required:** product assets are missing for the entire Shoes set.

### Other products without safe asset matches

Suiting:

- `RBL068M — Men's Arden Blazer`
- `RBL068L — Arden Blazer`
- `1766WSK — Women's Washable Box Pleat Skirt`
- `1732WT — Elliot Washable 7/8th Pant`
- `1723WT — Women's Washable Cigarette Pant`
- `60717 — Siena Women's Longline Jacket`
- `RJ400L — Renew Women's Double Breasted Longline Jacket`

Tops:

- `CA4T — City Active Top`

Outerwear:

- `JK63 — Men's Sustainable Softshell Corporate Jacket`
  - already known from the Outerwear reconciliation

Accessories:

- `CH333 — Mesh Flat Top Hat`
  - already known from the Accessories reconciliation

### Important Suiting asset-SKU collision

The source contains two distinct products:

- `RJ400L — Renew Women's Double Breasted Longline Jacket`
- `RJ401L — Renew Women's Single Button Mid Length Jacket`

The asset package contains:

- `RJ401L_RENEW_WOMEN'S_SINGLE_BUTTON_MID_LENGTH_JACKET`
- `RJ401L_RENEW_WOMENS_DOUBLE_BREASTED_LONGLINE_JACKET`

Therefore the Double Breasted Longline asset appears to be filed under the **RJ401L** prefix even though the source SKU for that product is **RJ400L**.

Because `RJ401L` is itself a real separate source product, the Double Breasted folder must **not** be automatically reassigned to `RJ400L` without confirmation.

This is recorded as an asset-SKU collision / likely asset naming error requiring source confirmation.

### Duplicate asset-folder cases

These are audit-only. No folders should be renamed, merged, or deleted.

- `1520WL — Womens Nicholson Premium Poplin Long Sleeve Shirt`
  - `1520WL_PREMIUM_POPLIN_LONG_SLEEVE_SHIRT`
  - `1520WL_WOMEN'S_NICHOLSON_PREMIUM_POPLIN_LONG_SLEEVE_SHIRT`

- `1899WL — Bradford Womens Fine Oxford Long Sleeve Shirt`
  - `1899WL_BRADFORD_WOMEN'S_FINE_OXFORD_LONG_SLEEVE_SHIRT`
  - `1899WL_BRADFORD_WOMENS_FINE_OXFORD_LONG_SLEEVE_SHIRT`

- `1765WJ — Women's Washable One Button Jacket`
  - `1765WJ_WOMEN'S_WASHABLE_ONE_BUTTON_JACKET`
  - `1765WJ_WOMENS_WASHABLE_ONE_BUTTON_JACKET`

- `BS732L — Ladies Bianca Jacket`
  - `BS732L_BIANCA_WOMEN'S_JACKET`
  - `BS732L_LADIES_BIANCA_JACKET`

- `1724WSK — Women's Washable Pencil Skirt`
  - `1724WSK_WOMEN'S_WASHABLE_PENCIL_SKIRT`
  - `1724WSK_WOMENS_WASHABLE_PENCIL_SKIRT`

- `20717 — Women's Bandless Pencil Skirt`
  - `20717_Siena_Womens_Bandless_Pencil_Skirt`
  - `20717_WOMEN'S_BANDLESS_PENCIL_SKIRT`

- `CL955LL — Women's Comfort Waist Straight Leg Pant`
  - `CL955LL_WOMEN'S_COMFORT_WAIST_STRAIGHT_LEG_PANT`
  - `CL955LL_Women_Comfort_Waist Straight_Leg_Pant`

- `BS909L — Ladies Remy Pant`
  - `BS909L_LADIES_REMY_PANT`
  - `BS909L_Ladies Remy Pant`

- `10722 — Women's Bandless Elastic Waist Pant`
  - `10722_Siena_Womens_Bandless_Elastic_Waist_Pant`
  - `10722_WOMEN'S_BANDLESS_ELASTIC_WAIST_PANT`

- `RGP308L — Siena 7/8 Mid-Waist Slim Leg Pant`
  - `RGP308L_SIENA_7_8_MID-WAIST_SLIM_LEG_PANT`
  - `RGP308L_Siena_Womens_7-8_Mid-waist_Slim_Leg_Pant`

- `60719 — Siena Women's Mid Length Jacket`
  - `60719_SIENA_WOMEN'S_MID_LENGTH_JACKET`
  - `60719_Siena_Womens_Mid_Length_Jacket`

- `RJ401L — Renew Women's Single Button Mid Length Jacket`
  - `RJ401L_RENEW_WOMEN'S_SINGLE_BUTTON_MID_LENGTH_JACKET`
  - `RJ401L_RENEW_WOMENS_DOUBLE_BREASTED_LONGLINE_JACKET`
  - second folder is the separate Double Breasted product and represents the collision described above

- `S421LL — Women's Soul Long Sleeve Shirt`
  - `S421LL_Soul_Womens_Long_Sleeve_Shirt`
  - `S421LL_WOMEN'S_SOUL_LONG_SLEEVE_SHIRT`
  - `S421LL_Womens_Soul_Long_Sleeve_Shirt`

### Batch 5 conclusion

- Fixed seven Product Categories: **works**
- Reusable multi-reference Subcategories: **works**
- Sustainable continues to work as a shared filter rather than a Product Category
- Fixed ten Industries: **works for 91 / 91 products**
- Services and Beauty can be removed safely from this batch
- No additional Industry is required
- Asset coverage: **67 / 91 usable**
- Entire Shoes set is missing from the supplied asset package
- Genuinely new products contributed: **61**
- Cumulative unique products reconciled through source row 500: **390**
- No Webflow changes were made during this reconciliation pass
