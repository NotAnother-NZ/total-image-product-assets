# Total Image Asset Classifier for macOS

A native macOS tool for classifying, syncing, and auditing the Total Image product asset migration.

## What it does

The app opens with two isolated workflows:

- **Classify / Sync Assets** — the existing classifier, smart source → destination comparison, and single-SKU update workflows.
- **Audit Final Assets** — a visual review queue for destination-only files, source-backed pixel duplicates, naming warnings, and missing finalized outputs.

- **Smart comparison mode:** drop the current `ALL_PRODUCT_ASSETS` source and the finalized GitHub-synced `assets` destination into separate drop zones.
- Reuses existing destination classifications when the corresponding WebP already exists.
- Safely maps renamed/merged product folders by preferring exact filename overlap, then only using conservative unique descriptor matches for clear renames.
- Automatically refreshes known changed/replacement source files into their existing Model/Product destination without asking you to classify them again.
- Leaves only genuinely unresolved source images in the manual M/P queue.
- Destination-only products/images are reported and preserved; the app never deletes them automatically.
- Classic mode is still available: drag and drop the full `ALL_PRODUCT_ASSETS` library, or choose it with the file picker.
- You can also drop a **single SKU folder** later for incremental updates.
- Shows one source image at a time when manual classification is required.
- Classify with:
  - **M** → Model
  - **P** → Product
  - **⌘Z** → Undo the most recent classification from the current session.
- Saves classification progress immediately after every click.
- Processes up to two images concurrently in the background while you keep classifying.
- Reopening the app and dropping the same assets folder resumes at the first unclassified image.
- If the app was closed while jobs were pending, those saved classifications are re-queued automatically.
- Existing source images are never modified.
- In single-SKU mode, only supported image files in the SKU folder root are scanned. Existing generated `webp/model` and `webp/product` folders are preserved and never treated as source files.
- If a root image was previously classified, the app reuses that classification from saved library progress (or an existing generated output) and automatically refreshes changed/replacement files.

## Audit Final Assets

Use this after classification/sync when the finalized `assets` directory needs a human review pass.

1. Drop the current `ALL_PRODUCT_ASSETS` folder into **Current Source**.
2. Drop the GitHub-synced `assets` folder into **Final Destination**.
3. Optionally add the client `.xlsx` workbook for additional SKU-aware rename validation.
4. Click **Build Audit Queue**.

Audit mode builds four queues:

- **Destination-only** — finalized WebPs that are no longer referenced by a current source record.
- **Pixel duplicates** — current source-backed outputs that are byte-identical, or that decode to identical pixels inside a logical collision group.
- **Naming warnings** — high-confidence filename typos such as `FRRONT`, `NACY`, or `CLOESUP`.
- **Missing outputs** — current source records whose saved finalized output no longer exists.

### Visual review

When a related output exists, the reviewer can switch between:

- side-by-side;
- primary only;
- related only;
- generated pixel-difference preview.

The current source path is shown whenever the output is source-backed.

### Review decisions

Destination-only outputs can be:

- kept;
- queued for deletion;
- queued for rename;
- marked for client review.

Source-backed duplicate outputs can be:

- kept both;
- marked as an intentional duplicate;
- flagged as a source issue;
- marked for client review.

**Source-backed outputs cannot be deleted from Audit mode.** This is enforced in both the UI and the apply engine.

Naming warnings can be kept or renamed. Renames are validated for:

- `.webp` extension;
- path safety;
- same-folder filename collisions;
- known high-confidence typo patterns;
- closeness to current source-backed output names;
- optional direct-SKU presence in the supplied client workbook.

### Review Changes → Apply

Delete and rename decisions are staged in a change plan. Nothing is modified while reviewing.

Before apply, the app:

1. re-checks every selected file;
2. creates a hash-verified backup under `~/Downloads/TotalImageAssetAuditBackups/`;
3. applies the queued operations;
4. updates `.total-image-classifier/progress.json` for active output renames so future syncs keep the corrected filename;
5. verifies every delete/rename;
6. writes JSON and CSV audit reports;
7. stores a rollback manifest.

The last apply can be rolled back from the app. Rollback is hash-guarded and stops if an affected file changed after the audit apply.

Audit review state is stored in:

```
assets/.total-image-audit/decisions.json
```

The audit state directory is ignored by Git.

## Smart source → destination comparison

Use this for the final migration workflow:

1. Drop the current source folder into **Source** (normally `ALL_PRODUCT_ASSETS`).
2. Drop the finalized repository folder into **Destination** (normally `total-image-product-assets/assets`).
3. The app scans both trees before showing any image.

For each source image the app:

- reuses an exact existing destination WebP classification when available;
- understands clear renamed product folders by looking at existing filename overlap;
- can transfer a classification across a clear filename-prefix/product-folder rename when the asset descriptor is unique;
- reserves exact matches first, so a new similarly named image can never steal an existing output that already belongs to another current source image;
- automatically reprocesses known replacements when the source is newer or saved source metadata changed;
- sends only images with no safe existing classification to the manual **Model / Product** queue.

In comparison mode, generated WebPs are written directly into the selected destination folder. Existing destination-only outputs are **not deleted**. This is deliberate: removed/legacy assets can be reviewed separately without the classifier silently destroying finalized migration work.

Once comparison mode has saved state, subsequent runs use the saved source file size/modification metadata as an additional replacement check.

## Output rules

### Model

Model images are written to:

```
PRODUCT_FOLDER/webp/model/
```

Processing:

- auto-orient
- preserve composition/aspect ratio
- max width 1200 px
- WebP quality 88
- strip metadata

### Product

Product images are written to:

```
PRODUCT_FOLDER/webp/product/
```

Processing:

- detect the largest visible non-white product component
- crop to the detected product bounds
- normalize the visible product to approximately 62.1% of canvas width
- centre it on a white 3:4 canvas
- expand the canvas when necessary so tall products are never cropped
- max width 1200 px
- WebP quality 88
- strip metadata

If product-bound detection fails, the job is marked **failed** rather than silently producing a fallback layout. The classification stays saved and the app retries failed/pending jobs when the folder is opened again.

## Resume data

In **smart comparison mode**, progress is stored in the destination folder:

```
assets/.total-image-classifier/progress.json
```

In classic full-library or single-SKU mode, progress remains inside the selected source folder as before.

The path is ignored by Git.

Each saved record contains the relative source path, classification, source size/modification time, processing status, output path, and (when needed) the mapped destination product folder/output stem.

If a classified source image changes later, the app retains its classification but automatically schedules it for reprocessing.

## Requirements

- macOS 14+
- Xcode / Swift toolchain
- ImageMagick

Install ImageMagick:

```bash
brew install imagemagick
```

The app looks for ImageMagick in the standard Apple Silicon Homebrew, Intel Homebrew and MacPorts paths.

## Build the .app

From the repository:

```bash
cd mac-app
./build-app.sh
```

The finished application is:

```
mac-app/dist/Total Image Asset Classifier.app
```

Open it:

```bash
open "dist/Total Image Asset Classifier.app"
```

The build is ad-hoc signed locally. It is not intended for public distribution or the Mac App Store.

## First run with the current asset library

For the new final-migration workflow, prefer **Smart source → destination comparison** so existing finalized classifications are reused.

The reset behavior below applies to **classic mode only**. In smart comparison mode, clearing saved comparison state never deletes finalized destination WebPs.

If old generated `webp` folders are still inside source product folders and you intentionally want a fresh classic-mode run, use the app's **… → Clear generated outputs & progress…** action before beginning.

That action removes only:

- nested `PRODUCT_FOLDER/webp/` directories
- `assets/.total-image-classifier/`

It does **not** remove the source JPG, JPEG, PNG, WebP or AVIF files.

Do not use the reset action while background processing is still active.


## Incremental single-SKU updates

After the main library has been classified, you can process a later correction without reopening the whole library.

Example:

```
ALL_PRODUCT_ASSETS/
  J510M_UNISEX_CHARGER_JACKET/
    J510M_..._BLACK_ROYAL_GREY_FRONT.jpg
    J510M_..._BLACK_ROYAL_GREY_BACK.jpg
    webp/
      model/
      product/
```

Drop `J510M_UNISEX_CHARGER_JACKET` directly into the app.

The app will:

- scan only supported image files in the SKU folder root;
- ignore and preserve existing `webp/model` and `webp/product` outputs;
- reuse saved classification for previously known filenames;
- automatically reprocess replacement files into their existing Model/Product destination;
- show only genuinely new, unclassified root images for manual classification;
- mirror single-SKU progress back into the parent `ALL_PRODUCT_ASSETS` progress file when it exists.
