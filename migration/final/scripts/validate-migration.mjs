import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FINAL_DIR = path.resolve(HERE, '..');
const OUT = path.join(FINAL_DIR, 'output');

function fail(message) {
  console.error('\n❌ PREFLIGHT FAILED\n' + message);
  process.exit(1);
}
function assert(condition, message) {
  if (!condition) fail(message);
}
function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        field += ch;
      }
      continue;
    }
    if (ch === '"') quoted = true;
    else if (ch === ',') { row.push(field); field = ''; }
    else if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (ch !== '\r') field += ch;
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }

  const headers = rows.shift() || [];
  return rows
    .filter(r => r.some(v => v !== ''))
    .map(r => Object.fromEntries(headers.map((h, i) => [h, r[i] ?? ''])));
}
function loadCsv(file) {
  const full = path.join(OUT, file);
  assert(fs.existsSync(full), `Missing file: ${full}`);
  return parseCsv(fs.readFileSync(full, 'utf8').replace(/^\uFEFF/, ''));
}
function refs(value) {
  return String(value || '').split(';').map(v => v.trim()).filter(Boolean);
}
function unique(values) {
  return new Set(values).size;
}
function checkRefs(rows, field, allowed, label) {
  const invalid = [];
  for (const row of rows) {
    for (const ref of refs(row[field])) {
      if (!allowed.has(ref)) {
        invalid.push({
          item: row['Product SKU'] || row['Slug'] || row['Color Name'] || row['Color Family Name'],
          ref
        });
      }
    }
  }
  assert(invalid.length === 0, `${label} has invalid references:\n${JSON.stringify(invalid.slice(0, 20), null, 2)}`);
}

const families = loadCsv('01-colour-families.csv');
const colours = loadCsv('02-colours.csv');
const familyLinks = loadCsv('03-colour-families-links.csv');
const products = loadCsv('04-products.csv');

const imageFiles = fs.readdirSync(OUT)
  .filter(name => /^05-images-\d+\.csv$/.test(name))
  .sort();
assert(imageFiles.length === 6, `Expected 6 Image CSVs, found ${imageFiles.length}`);
const images = imageFiles.flatMap(loadCsv);

const heroMap = JSON.parse(fs.readFileSync(path.join(OUT, 'hero-image-map.json'), 'utf8'));
const imageReport = JSON.parse(fs.readFileSync(path.join(OUT, 'image-validation-report.json'), 'utf8'));

assert(families.length === 17, `Expected 17 Colour Families, got ${families.length}`);
assert(colours.length === 202, `Expected 202 Colours, got ${colours.length}`);
assert(familyLinks.length === 17, `Expected 17 Family link rows, got ${familyLinks.length}`);
assert(products.length === 422, `Expected 422 Products, got ${products.length}`);
assert(images.length === 4464, `Expected 4464 Images, got ${images.length}`);

const existingColours = colours.filter(r => r['Item ID']);
const newColours = colours.filter(r => !r['Item ID']);
assert(existingColours.length === 189, `Expected 189 retained Colours, got ${existingColours.length}`);
assert(newColours.length === 13, `Expected 13 new Colours, got ${newColours.length}`);

assert(unique(products.map(r => r['Product SKU'])) === 422, 'Product SKUs are not unique');
assert(unique(products.map(r => r['Slug'])) === 422, 'Product slugs are not unique');
assert(unique(colours.map(r => r['Slug'])) === 202, 'Colour slugs are not unique');
assert(unique(images.map(r => r['Slug'])) === 4464, 'Image slugs are not unique');

const familySlugs = new Set(families.map(r => r['Slug']));
const colourSlugs = new Set(colours.map(r => r['Slug']));
const productSlugs = new Set(products.map(r => r['Slug']));
const imageSlugs = new Set(images.map(r => r['Slug']));

checkRefs(colours, 'Color Families', familySlugs, 'Colour → Colour Family');
checkRefs(familyLinks, 'Colors', colourSlugs, 'Colour Family → Colour');
checkRefs(products, 'Colors', colourSlugs, 'Product → Colour');

const categorySlugs = new Set([
  'tops','bottoms','outerwear','suiting','hi-vis-and-workwear','shoes','accessories'
]);
const industrySlugs = new Set([
  'workwear-and-hi-vis','teamwear-and-fitness','retail','hospitality','healthcare',
  'government','education','corporate','automotive','aged-care'
]);
const subcategorySlugs = new Set([
  'dresses','trousers','blazers','notebooks','pens','bags','drinkware',
  'promotional-merchandise','sustainable','3-4-sleeve','tunics','scrubs','tees',
  'first-nations','polos','fleece','chef-jackets','puffers','soft-shells',
  'knitwear','jackets','vests','safety-vests','short-sleeve','long-sleeve',
  'shirts','hi-vis','workwear','chinos','shorts','skirts','pants','belts',
  'aprons','headwear'
]);

checkRefs(products, 'Category', categorySlugs, 'Product → Category');
checkRefs(products, 'Industries', industrySlugs, 'Product → Industry');
checkRefs(products, 'Subcategories', subcategorySlugs, 'Product → Subcategory');

const badGenders = products.filter(r => r['Gender'] && !['Men','Women','Unisex'].includes(r['Gender']));
assert(badGenders.length === 0, `Invalid Gender values:\n${JSON.stringify(badGenders.slice(0,20), null, 2)}`);

const badImageProducts = images.filter(r => !productSlugs.has(r['Product']));
assert(badImageProducts.length === 0, `${badImageProducts.length} Images reference an unknown Product`);

const badImageColours = images.filter(r => r['Color'] && !colourSlugs.has(r['Color']));
assert(badImageColours.length === 0, `${badImageColours.length} Images reference an unknown Colour`);

assert(Object.keys(heroMap).length === 422, `Expected 422 Hero mappings, got ${Object.keys(heroMap).length}`);
const badHeroes = [];
for (const [sku, hero] of Object.entries(heroMap)) {
  if (!productSlugs.has(hero.product_slug)) badHeroes.push(`${sku}: unknown Product slug ${hero.product_slug}`);
  if (!imageSlugs.has(hero.image_slug)) badHeroes.push(`${sku}: unknown Image slug ${hero.image_slug}`);
}
assert(badHeroes.length === 0, `Invalid Hero mappings:\n${badHeroes.slice(0,20).join('\n')}`);

assert(imageReport.products === 422, 'Image report Product count mismatch');
assert(imageReport.asset_folders === 422, 'Image report folder count mismatch');
assert(imageReport.images === 4464, 'Image report Image count mismatch');
assert(imageReport.model_images === 2048, 'Image report model Image count mismatch');
assert(imageReport.product_images === 2416, 'Image report product Image count mismatch');
assert(imageReport.hero_images === 422, 'Image report Hero count mismatch');
assert(imageReport.status === 'ready', 'Image report is not marked ready');

console.log(`
✅ TOTAL IMAGE MIGRATION PREFLIGHT PASSED

Colour Families:       ${families.length}
Colours:                ${colours.length}
  Existing:             ${existingColours.length}
  New:                  ${newColours.length}

Products:               ${products.length}
Unique Product SKUs:    ${unique(products.map(r => r['Product SKU']))}
Unique Product slugs:   ${unique(products.map(r => r['Slug']))}

Images:                 ${images.length}
Unique Image slugs:     ${unique(images.map(r => r['Slug']))}
Model Images:           ${imageReport.model_images}
Product Images:         ${imageReport.product_images}

Hero mappings:          ${Object.keys(heroMap).length}
Images without Colour:  ${imageReport.images_without_colour_reference}

All references valid.
Ready for Webflow import.
`);
