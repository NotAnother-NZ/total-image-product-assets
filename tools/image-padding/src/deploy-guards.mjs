export const ORIGINAL_IMAGE_COUNT = 108;
export const REPLACEMENT_COUNT = 106;
export const BELT_IDS = Object.freeze([
  '6ac68f89d92cda95eb51ac8d',
  '6ac68f881c342211e8d597b9'
]);
export const PRIMARY_CMS_LOCALE = '6a5cf9aea7826c08d8c44b42';
export const SITE_ID = '6a4b7d4c587f58adf63bad93';
export const IMAGES_COLLECTION_ID = '6ab2df3d42b6657bfaed2936';

function equalValue(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
function exceptImage(fields) {
  const copy = { ...(fields || {}) };
  delete copy.image;
  return copy;
}
function requireItemId(id) {
  if (!/^[0-9a-f]{24}$/.test(id ?? '')) throw Error('Invalid Images CMS item ID');
}

export function validateLocalBatch(plan, snapshots) {
  if (plan?.version !== 1 || plan?.siteId !== SITE_ID ||
      plan?.collections?.images !== IMAGES_COLLECTION_ID || plan?.expectedProducts !== 47 ||
      plan?.expectedImages !== ORIGINAL_IMAGE_COUNT || plan?.targets?.length !== ORIGINAL_IMAGE_COUNT ||
      !Array.isArray(snapshots) || snapshots.length !== ORIGINAL_IMAGE_COUNT) {
    throw Error('Batch plan does not match the audited 47-product / 108-image manifest');
  }
  const targets = new Map(plan.targets.map(t => [t.imageItemId, t]));
  if (targets.size !== ORIGINAL_IMAGE_COUNT) throw Error('Duplicate Images CMS IDs in batch plan');
  const seen = new Set(), replacements = [], unchanged = [];
  for (const s of snapshots) {
    const t = targets.get(s.target?.imageItemId);
    if (!t) throw Error('Checkpoint contains image outside audited target plan');
    requireItemId(t.imageItemId);
    if (seen.has(t.imageItemId)) throw Error('Duplicate checkpoint for ' + t.imageItemId);
    seen.add(t.imageItemId);
    if (s.target.originalFileId !== t.originalFileId || s.target.productId !== t.productId ||
        s.target.slug !== t.slug || s.target.isHero !== t.isHero) {
      throw Error('Checkpoint and plan disagree for ' + t.imageItemId);
    }
    const original = s.source?.image;
    const product = s.source?.product;
    if (original?.id !== t.imageItemId || original?.fieldData?.image?.fileId !== t.originalFileId ||
        original?.fieldData?.product !== t.productId || product?.id !== t.productId ||
        product?.fieldData?.slug !== t.slug ||
        (t.isHero && product?.fieldData?.['hero-image'] !== t.imageItemId)) {
      throw Error('Original Images CMS backup or product reference is invalid for ' + t.imageItemId);
    }
    if (original.cmsLocaleId !== PRIMARY_CMS_LOCALE || original.isArchived || original.isDraft ||
        !original.lastPublished) {
      throw Error('Image is not an originally published primary-locale item: ' + t.imageItemId);
    }
    if (BELT_IDS.includes(t.imageItemId)) {
      if (s.status !== 'unchanged' || s.uploaded) throw Error('A belt must remain unchanged: ' + t.imageItemId);
      unchanged.push({target:t,state:s});
    } else {
      if (!['ready','applied'].includes(s.status) || !/^[a-f0-9]{64}$/.test(s.previewHash ?? '')) {
        throw Error('Unapproved or missing preview for ' + t.imageItemId);
      }
      if (s.status === 'applied' && (!s.uploaded?.fileId || !s.uploaded?.url)) {
        throw Error('Applied checkpoint is missing uploaded Webflow asset details: ' + t.imageItemId);
      }
      replacements.push({target:t,state:s});
    }
  }
  if (replacements.length !== REPLACEMENT_COUNT || unchanged.length !== BELT_IDS.length || seen.size !== ORIGINAL_IMAGE_COUNT ||
      new Set(plan.targets.map(t => t.slug)).size !== 47 ||
      plan.targets.filter(t => t.isHero).length !== 47) {
    throw Error('Unexpected deployment plan totals: expected 106 replacements + 2 original belts');
  }
  return {replacements, unchanged};
}

export function verifyStagedImage(original, staged, expected, t) {
  if (staged?.id !== t.imageItemId || staged.fieldData?.product !== t.productId ||
      staged.cmsLocaleId !== PRIMARY_CMS_LOCALE || staged.isArchived) {
    throw Error('Staged item identity / locale / product changed: ' + t.imageItemId);
  }
  if (!equalValue(exceptImage(staged.fieldData),exceptImage(original.fieldData))) {
    throw Error('Unrelated staged CMS fields changed for ' + t.imageItemId);
  }
  const actual = staged.fieldData?.image;
  if (actual?.fileId !== expected.fileId || actual?.url !== expected.url) {
    throw Error('Staged image does not match uploaded asset for ' + t.imageItemId);
  }
  if (actual.alt !== (original.fieldData?.image?.alt ?? null) &&
      !(actual.alt === undefined && original.fieldData?.image?.alt == null)) {
    throw Error('Staged image alt changed unexpectedly for ' + t.imageItemId);
  }
}

export function classifyLiveImage(original, live, uploaded, t) {
  if (live?.id !== t.imageItemId || live.fieldData?.product !== t.productId ||
      live.cmsLocaleId !== PRIMARY_CMS_LOCALE || live.isArchived) {
    throw Error('Live item missing or incorrect for ' + t.imageItemId);
  }
  if (!equalValue(exceptImage(original.fieldData),exceptImage(live.fieldData))) {
    throw Error('Existing live fields differ from original source for ' + t.imageItemId + '; refusing to publish unrelated changes');
  }
  const current = live.fieldData?.image?.fileId;
  if (current === uploaded?.fileId) {
    if (live.fieldData?.image?.url !== uploaded.url) throw Error('Live uploaded URL mismatch: ' + t.imageItemId);
    return 'already-live';
  }
  if (current === original.fieldData?.image?.fileId) return 'not-yet-live';
  throw Error('Live image was modified outside this migration: ' + t.imageItemId);
}

export function validatePublishedIds(requested, response) {
  if (!Array.isArray(requested) || !requested.length || requested.length > 20 ||
      new Set(requested).size !== requested.length || !Array.isArray(response?.publishedItemIds)) {
    throw Error('Unexpected Webflow publish response or invalid request batch');
  }
  const a = new Set(response.publishedItemIds);
  if ((response.errors?.length ?? 0) !== 0 ||
      a.size !== requested.length || requested.some(id=> !a.has(id))) {
    throw Error('Webflow returned a partial publish result: ' + JSON.stringify(response).slice(0,1500));
  }
}
