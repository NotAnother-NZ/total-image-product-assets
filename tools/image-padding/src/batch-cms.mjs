import { createHash } from 'node:crypto';
import { target as siteTarget, wf } from './api.mjs';
import { AFFECTED_PRODUCT_SLUGS } from './batch-targets.mjs';

export const EXPECTED_PRODUCTS = 47;
export const EXPECTED_IMAGES = 108;
export const CMS = Object.freeze({
  site: siteTarget.site,
  products: siteTarget.products,
  images: siteTarget.images
});

// GET is safe to retry on transient rate limiting; never retry a CMS PATCH or asset POST blindly.
async function wfRead(path) {
  for (let attempt = 0; ; attempt++) {
    try { return await wf(path); }
    catch (error) {
      if (attempt >= 5 || !/HTTP (429|500|502|503|504)\b/.test(String(error.message))) throw error;
      await new Promise(resolve => setTimeout(resolve, Math.min(30000, 1500 * 2 ** attempt)));
    }
  }
}

export async function listEveryItem(collectionId) {
  const items = [];
  const limit = 100;
  for (let offset = 0; ;) {
    const page = await wfRead('/collections/' + collectionId + '/items?limit=' + limit + '&offset=' + offset);
    if (!Array.isArray(page.items) || !page.pagination || !Number.isInteger(page.pagination.total)) {
      throw Error('Malformed Webflow list response for ' + collectionId);
    }
    items.push(...page.items);
    offset += page.items.length;
    if (items.length >= page.pagination.total) break;
    if (!page.items.length) throw Error('Webflow collection pagination stopped before reaching total');
    if (items.length > 25000) throw Error('Unreasonably large CMS result; stopping');
  }
  return items;
}

export function createTargetPlan(products, images, slugs = AFFECTED_PRODUCT_SLUGS, expected = EXPECTED_IMAGES) {
  if (new Set(slugs).size !== slugs.length || slugs.length !== EXPECTED_PRODUCTS) {
    throw Error('Product shortlist must contain 47 distinct slugs');
  }
  const bySlug = new Map();
  for (const product of products) {
    const slug = product.fieldData?.slug;
    if (!slug) continue;
    if (bySlug.has(slug)) throw Error('Duplicate product slug ' + slug);
    bySlug.set(slug, product);
  }
  const chosen = slugs.map(slug => {
    const p = bySlug.get(slug);
    if (!p) throw Error('Product missing from CMS: ' + slug);
    if (!p.fieldData?.['hero-image']) throw Error('Product missing hero reference: ' + slug);
    return p;
  });
  const byProductId = new Map(chosen.map(p => [p.id, p]));
  const buckets = new Map(chosen.map(p => [p.id, []]));
  const seen = new Set();
  for (const image of images) {
    if (!byProductId.has(image.fieldData?.product)) continue;
    if (seen.has(image.id)) throw Error('Duplicated Images CMS item: ' + image.id);
    seen.add(image.id);
    const field = image.fieldData.image;
    if (!field?.fileId || !field?.url) throw Error('Missing image asset on ' + image.id);
    if (image.isArchived || image.isDraft) throw Error('Image is draft/archived: ' + image.id);
    buckets.get(image.fieldData.product).push(image);
  }
  const targets = [];
  for (const p of chosen) {
    const mine = buckets.get(p.id);
    if (!mine.length) throw Error('Product has no Images CMS items: ' + p.fieldData.slug);
    if (!mine.some(i => i.id === p.fieldData['hero-image'])) {
      throw Error('Hero image is not linked to its product: ' + p.fieldData.slug);
    }
    mine.sort((a, b) => {
      if (a.id === p.fieldData['hero-image']) return -1;
      if (b.id === p.fieldData['hero-image']) return 1;
      return (a.fieldData['sort-order'] ?? 9999) - (b.fieldData['sort-order'] ?? 9999) || a.id.localeCompare(b.id);
    });
    for (const i of mine) targets.push({
      slug: p.fieldData.slug,
      productName: p.fieldData.name,
      productId: p.id,
      imageItemId: i.id,
      originalFileId: i.fieldData.image.fileId,
      imageName: i.fieldData.name,
      isHero: i.id === p.fieldData['hero-image']
    });
  }
  if (targets.length !== expected) {
    throw Error('Expected ' + expected + ' linked images from the audit, but live CMS has ' + targets.length + '. Stop and review before proceeding.');
  }
  if (targets.filter(x => x.isHero).length !== slugs.length) throw Error('Expected one verified hero per product');
  return {
    version: 1, siteId: CMS.site, collections: CMS,
    createdAt: new Date().toISOString(), expectedProducts: slugs.length,
    expectedImages: expected, targets
  };
}

export async function discoverPlan() {
  const [products, images] = await Promise.all([listEveryItem(CMS.products), listEveryItem(CMS.images)]);
  return createTargetPlan(products, images);
}

function otherFields(fieldData) {
  const copy = structuredClone(fieldData);
  delete copy.image;
  return copy;
}

export function assertOtherFieldsUnchanged(original, current) {
  if (JSON.stringify(otherFields(original.fieldData)) !== JSON.stringify(otherFields(current.fieldData))) {
    throw Error('Non-image fields changed. Refusing to overwrite existing CMS data');
  }
}

export async function readVerifiedTarget(t) {
  const [image, product] = await Promise.all([
    wfRead('/collections/' + CMS.images + '/items/' + t.imageItemId),
    wfRead('/collections/' + CMS.products + '/items/' + t.productId)
  ]);
  if (product.id !== t.productId || product.fieldData?.slug !== t.slug) {
    throw Error('Product identity changed: ' + t.slug);
  }
  if (image.id !== t.imageItemId || image.fieldData?.product !== t.productId) {
    throw Error('Image-product relationship changed: ' + t.imageItemId);
  }
  if (t.isHero && product.fieldData?.['hero-image'] !== t.imageItemId) {
    throw Error('Hero image reference changed: ' + t.slug);
  }
  return { image, product };
}

export function assetFilenameFor(t) {
  // Webflow Upload Asset requires fileName to be strictly shorter than 100 characters.
  // Keep the unique Images CMS ID in the name; truncate only the descriptive slug prefix.
  const suffix = t.imageItemId + '-padding-restored.webp';
  const maximumSlugLength = 99 - 1 - suffix.length;
  if (maximumSlugLength < 1 || !/^[a-z0-9-]+$/.test(t.slug) ||
      !/^[0-9a-f]{24}$/.test(t.imageItemId)) {
    throw Error('Invalid asset name components');
  }
  const shortSlug = t.slug.slice(0, maximumSlugLength).replace(/-+$/, '');
  const name = shortSlug + '-' + suffix;
  if (name.length >= 100) throw Error('Webflow upload filename is too long');
  return name;
}

export async function uploadAsset(bytes, t) {
  const fileName = assetFilenameFor(t);
  const metadata = await wf('/sites/' + CMS.site + '/assets', 'POST', {
    fileName, fileHash: createHash('md5').update(bytes).digest('hex')
  });
  if (!metadata.id || !metadata.hostedUrl || !metadata.uploadUrl || !metadata.uploadDetails) {
    throw Error('Webflow asset creation returned incomplete upload data');
  }
  const form = new FormData();
  for (const [name, value] of Object.entries(metadata.uploadDetails)) form.append(name, String(value));
  form.append('file', new Blob([bytes], { type: 'image/webp' }), fileName);
  const res = await fetch(metadata.uploadUrl, { method: 'POST', body: form, signal: AbortSignal.timeout(180000) });
  if (!res.ok) throw Error('Webflow asset upload failed with HTTP ' + res.status);
  return { fileId: metadata.id, url: metadata.hostedUrl };
}

export async function waitForHostedAsset(url) {
  for (let attempt = 0; attempt < 8; attempt++) {
    try {
      const result = await fetch(url, { method: 'HEAD', signal: AbortSignal.timeout(20000) });
      if (result.ok) return;
    } catch { /* Webflow asset CDN propagation may take a moment */ }
    await new Promise(resolve => setTimeout(resolve, 1500 * (attempt + 1)));
  }
  throw Error('Uploaded asset has not appeared on Webflow CDN; CMS image was not changed');
}

export async function updateImageOnly(t, field) {
  return wf('/collections/' + CMS.images + '/items', 'PATCH', {
    items: [{ id: t.imageItemId, fieldData: { image: field } }]
  });
}
