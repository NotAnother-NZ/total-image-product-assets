# Deploy and stage 106 restored Total Image images — publishing currently disabled

Updated 15 October 2026.

## Exactly what is in scope

- **47 products, 108 Images CMS records** from the reviewed white-padding report.
- **106 approved 1200 × 1600 WebP previews** will replace only the `image` field of the existing Images CMS records.
- **2 Casual Braided Belt images** are already seamless and stay untouched.
- The original Images CMS IDs, Product and Color references, Sort Order, Name, Slug, Hero references, and alt text are preserved.
- No images are regenerated. **OpenAI requests/cost for deployment: $0**.
- Every original asset and CMS backup remains in `output/batch-padding`.
- Code changes are isolated to `tools/image-padding`.

**Warning about publishing domains:** the Total Image Webflow subdomain was last site-published on 15 October 2026, while both custom domains (`totalimage.com.au` and `www.totalimage.com.au`) were last site-published on 6 August 2026. Webflow may block item-level CMS publishing when domain site-publish times differ. Publishing selected CMS items is not limited to `na26-total-image.webflow.io`; it may also affect the custom **production** domains. If production should remain unchanged, **STOP AFTER STAGING** and do not run publish.

This tool will **never call `POST /v2/sites/:site_id/publish`**. A full-site publish could release unrelated design/content changes and requires a separate decision outside this script.

## Setup and tests

Run from the repository:

```bash
git fetch origin
git switch feat/image-padding-restoration-test
git pull --ff-only origin feat/image-padding-restoration-test
cd tools/image-padding
npm install
npm test
```

Your ignored `.env` should already contain `WEBFLOW_API_TOKEN`. The deployment requires `cms:read`, `cms:write`, `assets:write`, and `sites:read` scopes. (OpenAI is **not** contacted during deployment.) Use the same local `output/batch-padding` folder that holds your 106 approved previews, original-image backups, per-item manifests, and plan.

## Recommended production-safe, two-step sequence

### 1. Read-only preflight

```bash
npm run batch:deploy:check
```

This checks the local 108-item plan and all 106 file hashes, dimensions, original backup records, required locale, and the site's configured domains. If any of the files or records are missing or modified, it stops. This command makes **no Webflow writes**.

### 2. Upload and stage the 106 image replacements

```bash
npm run batch:deploy:stage -- --reviewed yes --confirm APPLY_REVIEWED_108_IMAGES
```

This reuses the **existing checkpointed `batch:apply` script**. It uploads a new WebP asset per approved image, patches *only* the original Images CMS item's `image` field, and verifies it. It does not publish, modify products or colors, delete originals, or touch the two unchanged belts.

**Do not proceed to publish if the staging summary is anything other than `applied:106`, `unchanged:2`, and zero failures.** If staging stops or hits a rate limit, inspect `summary.json` and re-run the same command; completed uploads are reused.

### 3. Publish only those 106 Images CMS items (may affect production)

**Only run this if you intend to publish these CMS changes across all currently configured live domains, including custom production domains**:

```bash
npm run batch:deploy:publish -- --confirm PUBLISH_106_TOTAL_IMAGE_IMAGES_ALL_DOMAINS --ack-all-domains yes
```

The script first verifies all 106 staged assets, 2 untouched belts, 47 product/hero relationships, and live original CMS values. It aborts *before publishing anything* if it detects unrelated edits or a changed asset. It publishes CMS item IDs only via `POST /v2/collections/{images_collection_id}/items/publish`, in small groups of up to 10, and verifies each published asset using the Webflow **live item** API.

It does **not** publish the site. If domain state prevents CMS item publishing, it stops with an error—**do not automatically fall back to full-site publishing**.

**Interrupted or partially successful publish?** Re-run the same publish command after checking the log: the script reads the live CMS records and skips those already showing the approved file ID. HTTP 202 responses can contain per-item errors; the script requires every requested ID to be acknowledged. It never blindly retries a timed-out POST.

### 4. Verify all 108 live records

```bash
npm run batch:deploy:verify
npm run batch:summary
```

Expected result: **106 updated live image items** and **2 original belts retained**, with all product references unchanged. The summary still records `applied` for staged replacements; publishing is separately verified by the live API.

Finally, visually spot-check:

- `https://na26-total-image.webflow.io/products`
- Relevant product detail pages, especially Men's Derby, the white-colour bottles, Oakleigh Coffee Cup, and Arc Eco Square Wireless Charger
- Custom domains **only if** you intended to change them

The CDN/site UI may take a short time to reflect the published CMS item change. API verification confirms item data, not every rendered template/cache on every domain.

## Optional: one-command stage + publish

If you explicitly want **both staging and production-domain CMS publication** in one uninterrupted run, this command performs the same checkpointed staging, validates that all 106 succeeded, then publishes and verifies the exact Images CMS records:

```bash
npm run batch:deploy -- --confirm PUBLISH_106_TOTAL_IMAGE_IMAGES_ALL_DOMAINS --ack-all-domains yes
```

The safer recommended workflow is the separate stage and publish commands above because you can inspect the staged CMS result before releasing anything live.

## Safety and recovery

- If an original CMS item, image file ID, locale, hero reference, color, sort order, name or slug is different from the backup, the tool refuses to publish it.
- If even **one of 106** approved WebP files fails its SHA-256 or 1200 × 1600 validation, it refuses to start.
- If one of the two preserved belt images has changed, publishing is stopped.
- If a CMS item publish returns a partial response or publication verification fails, it stops and leaves an audit checkpoint. It does not publish other CMS records to compensate.
- Re-running **staging** reuses uploaded assets. Re-running **publishing** skips verified live replacements.
- No Webflow site-wide publish, no product record mutations, no automatic deletions, and no AI generation.
- The original CMS image fields and assets remain in each `manifest.json`; published rollback would require restoring these original fields **and republishing those same CMS items**. The existing `batch:rollback` command restores *staged* records only and does **not** reverse previously published changes. Do not use it as a live rollback.

Official reference:
- [Update staged CMS items](https://developers.webflow.com/data/reference/cms/collection-items/staged-items/update-items)
- [Publish selected CMS items](https://developers.webflow.com/data/reference/cms/collection-items/staged-items/publish-item)
- [Read live CMS item](https://developers.webflow.com/data/reference/cms/collection-items/live-items/get-item-live)


## Webflow canonical image IDs: staged PATCH recovery

If staging previously printed `Webflow returned unexpected image field after update`, **do not delete files, reset checkpoints, or regenerate images.** Webflow can accept the image PATCH while returning a new CMS-specific `fileId` and canonical CDN URL, different from the initial site-asset upload receipt.

As of the 15 October interrupted run, **four Allegra Images CMS items were verified to contain the replacement image links**, while none of the four local manifests was marked `applied`. The current batch script now handles this correctly:

- It checks that product, hero, locale, and unrelated CMS fields are unchanged.
- It checks the **actual Webflow CDN WebP bytes** against the already approved local preview SHA-256 and verifies the 1200 x 1600 WebP format.
- If the hash matches, it saves the canonical `fileId` and URL in the checkpoint, retains the original upload receipt in `assetUpload`, and **skips uploading/PATCHing that item again**.
- If the actual CDN image bytes do not match, the tool stops on that item with a specific error. It does not overwrite the existing CMS image or upload a replacement blindly.
- All subsequent images use this canonical verification immediately after staging.

Resume safely with:

```bash
git pull --ff-only origin feat/image-padding-restoration-test
npm test
npm run batch:deploy:stage -- --reviewed yes --confirm APPLY_REVIEWED_108_IMAGES
npm run batch:summary
```

The expected result after a successful run is **106 applied, 2 unchanged**. Publication remains **blocked** on this site because the selected-item publish endpoint is not staging-domain-only and could affect `totalimage.com.au`.

