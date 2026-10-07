import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FINAL_DIR = path.resolve(HERE, '..');
const HERO_MAP = path.join(FINAL_DIR, 'output', 'hero-image-map.json');

function parseCsv(text) {
  const rows = [];
  let row = [], field = '', i = 0, quoted = false;
  while (i < text.length) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i += 2; continue; }
        quoted = false; i++; continue;
      }
      field += ch; i++; continue;
    }
    if (ch === '"') { quoted = true; i++; continue; }
    if (ch === ',') { row.push(field); field = ''; i++; continue; }
    if (ch === '\r') { i++; continue; }
    if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ''; i++; continue; }
    field += ch; i++;
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  const headers = rows.shift() || [];
  return rows.filter(r => r.some(v => v !== '')).map(r => Object.fromEntries(headers.map((h, idx) => [h, r[idx] ?? ''])));
}

function esc(v) {
  const s = String(v ?? '');
  return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

function stringifyCsv(rows, headers) {
  return [headers.map(esc).join(','), ...rows.map(r => headers.map(h => esc(r[h])).join(','))].join('\r\n') + '\r\n';
}

const input = process.argv[2];
const output = process.argv[3] || path.join(FINAL_DIR, 'output', '06-product-hero-images-ready.csv');
if (!input) {
  throw new Error('Usage: node build-product-hero-update.mjs <webflow-products-export.csv> [output.csv]');
}

const exportRows = parseCsv(fs.readFileSync(input, 'utf8').replace(/^\uFEFF/, ''));
const heroMap = JSON.parse(fs.readFileSync(HERO_MAP, 'utf8'));

const bySku = new Map();
for (const row of exportRows) {
  const sku = String(row['Product SKU'] || row['product-sku'] || '').trim();
  if (sku) bySku.set(sku, row);
}

const missing = [];
const out = [];
for (const [sku, hero] of Object.entries(heroMap)) {
  const row = bySku.get(sku);
  if (!row) { missing.push(sku); continue; }
  const id = row['Item ID'] || row['item id'] || row['ID'] || '';
  if (!id) throw new Error(`Webflow export row for ${sku} has no Item ID.`);
  out.push({
    'Item ID': id,
    'Product Name': row['Product Name'] || row['Name'] || '',
    'Slug': row['Slug'] || hero.product_slug,
    'Product SKU': sku,
    'Hero Image': hero.image_slug
  });
}

if (missing.length) throw new Error(`Missing ${missing.length} Products from Webflow export: ${missing.join(', ')}`);
if (out.length !== 422) throw new Error(`Expected 422 hero-update rows, got ${out.length}`);

fs.writeFileSync(output, stringifyCsv(out, ['Item ID','Product Name','Slug','Product SKU','Hero Image']), 'utf8');
console.log(JSON.stringify({ input, output, rows: out.length, status: 'ready' }, null, 2));
