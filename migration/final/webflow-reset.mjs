import fs from 'node:fs';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SNAPSHOT_DIR = path.join(HERE, 'snapshots');
const API = 'https://api.webflow.com/v2';
const TOKEN = process.env.WEBFLOW_API_TOKEN;
if (!TOKEN) throw new Error('WEBFLOW_API_TOKEN is required.');

const COLLECTIONS = {
  products: '6ab0acfdb063e14a30f65e5c',
  images: '6ab2df3d42b6657bfaed2936',
  colours: '6ab0acfcc9c82198b26f2292',
  colourFamilies: '6ab0b03d7e10c6ac95cde3d5',
  articles: '6ab260338f240726fe0f00d4'
};

async function request(method, url, body) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(API + url, {
      method,
      headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    if (res.status === 429 && attempt < 6) {
      await sleep(Math.max(1000, Number(res.headers.get('retry-after') || 1) * 1000));
      continue;
    }
    if (!res.ok) throw new Error(`${method} ${url} -> ${res.status}: ${await res.text()}`);
    if (res.status === 204) return null;
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }
}

async function listItems(collectionId) {
  const all = [];
  for (let offset = 0; ; offset += 100) {
    const data = await request('GET', `/collections/${collectionId}/items?limit=100&offset=${offset}`);
    all.push(...(data.items || []));
    if ((data.items || []).length < 100) break;
  }
  return all;
}

async function bulkUpdate(collectionId, items) {
  for (let i = 0; i < items.length; i += 100) {
    await request('PATCH', `/collections/${collectionId}/items?skipInvalidFiles=true`, { items: items.slice(i, i + 100) });
  }
}

async function bulkDelete(collectionId, ids) {
  for (let i = 0; i < ids.length; i += 100) {
    const batch = ids.slice(i, i + 100).map(id => ({ id }));
    try {
      await request('DELETE', `/collections/${collectionId}/items`, { items: batch });
    } catch (error) {
      console.warn(`Bulk delete fallback for ${collectionId}: ${error.message}`);
      for (const { id } of batch) await request('DELETE', `/collections/${collectionId}/items/${id}`);
    }
  }
}

function latestSnapshot() {
  const latest = path.join(SNAPSHOT_DIR, 'LATEST');
  if (!fs.existsSync(latest)) throw new Error('No snapshot exists. Run `node webflow-reset.mjs snapshot` first.');
  return JSON.parse(fs.readFileSync(path.join(SNAPSHOT_DIR, fs.readFileSync(latest, 'utf8').trim()), 'utf8'));
}

async function snapshot() {
  fs.mkdirSync(SNAPSHOT_DIR, { recursive: true });
  const [products, images, colours, colourFamilies, articles] = await Promise.all([
    listItems(COLLECTIONS.products), listItems(COLLECTIONS.images), listItems(COLLECTIONS.colours),
    listItems(COLLECTIONS.colourFamilies), listItems(COLLECTIONS.articles)
  ]);
  const data = { createdAt: new Date().toISOString(), collections: COLLECTIONS, products, images, colours, colourFamilies, articles };
  const filename = `webflow-before-${data.createdAt.replace(/[:.]/g, '-')}.json`;
  fs.writeFileSync(path.join(SNAPSHOT_DIR, filename), JSON.stringify(data, null, 2));
  fs.writeFileSync(path.join(SNAPSHOT_DIR, 'LATEST'), filename + '\n');
  console.log(JSON.stringify({ status: 'snapshotted', filename, counts: {
    products: products.length, images: images.length, colours: colours.length,
    colourFamilies: colourFamilies.length, articles: articles.length
  }}, null, 2));
}

async function cleanup() {
  const snap = latestSnapshot();
  console.log('Clearing Product Hero Image + Related Products references...');
  await bulkUpdate(COLLECTIONS.products, snap.products.map(p => ({
    id: p.id, fieldData: { 'hero-image': null, 'related-products': [] }
  })));

  const articleUpdates = snap.articles
    .filter(a => Array.isArray(a.fieldData?.products) && a.fieldData.products.length)
    .map(a => ({ id: a.id, fieldData: { products: [] } }));
  if (articleUpdates.length) {
    console.log(`Clearing Product references from ${articleUpdates.length} Articles...`);
    await bulkUpdate(COLLECTIONS.articles, articleUpdates);
  }

  console.log(`Deleting ${snap.images.length} Image CMS items...`);
  await bulkDelete(COLLECTIONS.images, snap.images.map(x => x.id));

  console.log(`Deleting ${snap.products.length} Product CMS items...`);
  await bulkDelete(COLLECTIONS.products, snap.products.map(x => x.id));

  const [imagesAfter, productsAfter] = await Promise.all([
    listItems(COLLECTIONS.images), listItems(COLLECTIONS.products)
  ]);
  if (imagesAfter.length || productsAfter.length) {
    throw new Error(`Cleanup verification failed: ${imagesAfter.length} Images and ${productsAfter.length} Products remain.`);
  }
  console.log(JSON.stringify({ status: 'clean', deleted: { images: snap.images.length, products: snap.products.length },
    cleared: { productItems: snap.products.length, articles: articleUpdates.length } }, null, 2));
}

const mode = process.argv[2];
if (mode === 'snapshot') await snapshot();
else if (mode === 'cleanup') await cleanup();
else throw new Error('Usage: node webflow-reset.mjs snapshot|cleanup');
