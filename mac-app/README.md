# Total Image Asset Classifier for macOS

A small native macOS app for manually classifying the Total Image product assets while image processing continues in the background.

## What it does

- Drag and drop the full `ALL_PRODUCT_ASSETS` library, or choose it with the file picker.
- You can also drop a **single SKU folder** later for incremental updates.
- Shows one source image at a time.
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

Progress lives inside the selected assets folder:

```
assets/.total-image-classifier/progress.json
```

The path is ignored by Git.

Each saved record contains the relative source path, classification, source size/modification time, processing status and output path.

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

If old generated `webp` folders are still inside the product folders, use the app's **… → Clear generated outputs & progress…** action before beginning the new manual classification run.

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
