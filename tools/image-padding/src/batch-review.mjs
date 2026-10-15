/**
 * Local-only review sheets for the Total Image padding batch.
 * Reads checkpointed files; never calls OpenAI, Webflow, or any network endpoint.
 */
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const defaultFolder = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'output/batch-padding');
const cellWidth = 410;
const cellHeight = 348;
const columns = 3;
const rows = 4;
const pageSize = columns * rows;

export function escapeXml(value) {
  return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

export function groupEntries(summary) {
  if (!Array.isArray(summary?.entries)) throw Error('Missing batch summary entries');
  const images = new Set();
  const grouped = { ready: [], unresolved: [], unchanged: [] };
  for (const entry of summary.entries) {
    if (!entry.imageItemId || !entry.slug || !entry.status) throw Error('Invalid summary entry');
    if (images.has(entry.imageItemId)) throw Error('Duplicate image ID in summary');
    images.add(entry.imageItemId);
    if (['ready', 'applied'].includes(entry.status)) grouped.ready.push(entry);
    else if (entry.status === 'unchanged') grouped.unchanged.push(entry);
    else grouped.unresolved.push(entry);
  }
  return grouped;
}

async function exists(path) { return access(path).then(() => true, () => false); }

async function thumb(path, width, height) {
  const bytes = await readFile(path);
  return sharp(bytes).rotate().resize(width, height, { fit: 'contain', background: '#f5f5f5' })
    .png().toBuffer();
}

function labelSvg(entry, x, y, availablePreview) {
  const title = escapeXml(entry.productName?.slice(0, 48) ?? entry.slug);
  const id = escapeXml(entry.imageItemId);
  const type = entry.isHero ? 'HERO' : 'GALLERY';
  const status = escapeXml(entry.status.toUpperCase());
  const statusLine = escapeXml((entry.reason ?? '').replace(/\s+/g, ' ').slice(0, 67));
  return [
    '<g>',
    '<rect x="' + x + '" y="' + y + '" width="400" height="338" rx="6" fill="#fff" stroke="#c6c6c6" stroke-width="1"/>',
    '<text x="' + (x + 12) + '" y="' + (y + 22) + '" font-size="15" font-weight="600" fill="#202020">' + title + '</text>',
    '<text x="' + (x + 12) + '" y="' + (y + 42) + '" font-size="12" fill="#555">' + type + ' | ' + status + ' | ' + id + '</text>',
    '<text x="' + (x + 12) + '" y="' + (y + 62) + '" font-size="12" fill="#555">' + (statusLine || ' ') + '</text>',
    '<text x="' + (x + 14) + '" y="' + (y + 329) + '" font-size="12" fill="#555">ORIGINAL</text>',
    '<text x="' + (x + 218) + '" y="' + (y + 329) + '" font-size="12" fill="#555">' + (availablePreview ? 'RESTORED PREVIEW' : 'NO PREVIEW / MANUAL REVIEW') + '</text>',
    '</g>'
  ].join('');
}

async function renderPage(entries, fileRoot, outputFile) {
  const layers = [], labels = [];
  const missing = [];
  for (let index = 0; index < entries.length; index++) {
    const entry = entries[index];
    const x = (index % columns) * cellWidth;
    const y = Math.floor(index / columns) * cellHeight;
    const dir = join(fileRoot, entry.slug, entry.imageItemId);
    const original = join(dir, 'normalized.png');
    const raw = join(dir, 'original-source.bin');
    const preview = join(dir, 'preview.webp');
    const hasOriginal = await exists(original) || await exists(raw);
    const hasPreview = await exists(preview);
    if (hasOriginal) {
      const b = await thumb(await exists(original) ? original : raw, 184, 242);
      layers.push({ input: b, left: x + 10, top: y + 76 });
    } else {
      missing.push({ id: entry.imageItemId, type: 'original' });
    }
    if (hasPreview) {
      const b = await thumb(preview, 184, 242);
      layers.push({ input: b, left: x + 210, top: y + 76 });
    } else if (['ready', 'applied'].includes(entry.status)) {
      missing.push({ id: entry.imageItemId, type: 'preview' });
    }
    labels.push(labelSvg(entry, x, y, hasPreview));
  }
  const canvasWidth = cellWidth * columns;
  const canvasHeight = cellHeight * rows;
  const markup = '<svg xmlns="http://www.w3.org/2000/svg" width="' + canvasWidth + '" height="' + canvasHeight + '">' +
    '<rect width="100%" height="100%" fill="#f5f5f5"/>' + labels.join('') + '</svg>';
  // Overlay labels first so exact original/restored photographs remain untouched by text.
  const result = await sharp({ create: { width: canvasWidth, height: canvasHeight, channels: 3, background: '#f5f5f5' } })
    .composite([{ input: Buffer.from(markup), top: 0, left: 0 }, ...layers]).webp({ quality: 87 }).toBuffer();
  await writeFile(outputFile, result);
  return missing;
}

export async function buildReviewSheets(folder = defaultFolder) {
  const summary = JSON.parse(await readFile(join(folder, 'summary.json'), 'utf8'));
  const grouped = groupEntries(summary);
  const output = join(folder, 'review-sheets');
  await mkdir(output, { recursive: true });
  const sheetIndex = [];
  const problems = [];
  for (const [key, items] of [['ready', grouped.ready], ['needs-attention', grouped.unresolved], ['unchanged', grouped.unchanged]]) {
    for (let start = 0; start < items.length; start += pageSize) {
      const pageNumber = Math.floor(start / pageSize) + 1;
      const filename = key + '-' + String(pageNumber).padStart(2, '0') + '.webp';
      const pageItems = items.slice(start, start + pageSize);
      const foundMissing = await renderPage(pageItems, folder, join(output, filename));
      problems.push(...foundMissing);
      sheetIndex.push({ sheet: filename, group: key, entries: pageItems.map(e => ({
        product: e.productName, slug: e.slug, imageItemId: e.imageItemId, isHero: e.isHero, status: e.status
      })) });
      console.log('Review sheet:', join(output, filename), '(' + pageItems.length + ' images)');
    }
  }
  await writeFile(join(output, 'index.json'), JSON.stringify({ sheets: sheetIndex, missingFiles: problems }, null, 2) + '\n');
  console.log('Completed local-only QA sheets. Generated image files:', sheetIndex.length);
  console.log('Unresolved images to review:', grouped.unresolved.length);
  if (problems.length) console.warn('Missing preview/original files:', problems.length);
  return { sheetIndex, missingFiles: problems };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 2 || args[0] !== '--out')) {
    console.error('Usage: node src/batch-review.mjs [--out output/batch-padding]');
    process.exitCode = 1;
  } else {
    buildReviewSheets(args.length ? resolve(args[1]) : defaultFolder)
      .catch(e => { console.error('REVIEW ERROR:', e.message); process.exitCode = 1; });
  }
}
