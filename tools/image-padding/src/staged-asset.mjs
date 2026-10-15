import { createHash } from 'node:crypto';
import sharp from 'sharp';
import { assetFilenameFor } from './batch-cms.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');

/**
 * Webflow can copy an uploaded site asset into a CMS image field and assign a
 * *new* fileId and canonical URL. Compare the actual staged content, not the
 * temporary upload receipt identifiers.
 */
export function validateCmsImageUrl(target, imageField) {
  if (!/^[0-9a-f]{24}$/.test(imageField?.fileId ?? '')) {
    throw Error('Staged CMS image is missing a valid Webflow file ID: ' + target.imageItemId);
  }
  let url;
  try { url = new URL(imageField?.url); }
  catch { throw Error('Staged CMS image has an invalid asset URL: ' + target.imageItemId); }
  if (url.protocol !== 'https:' || url.hostname !== 'cdn.prod.website-files.com' ||
      !url.pathname.startsWith('/6a5cf9aea7826c08d8c44b43/')) {
    throw Error('Staged CMS image is not on the expected Total Image asset CDN: ' + target.imageItemId);
  }
  const name = decodeURIComponent(url.pathname.split('/').at(-1));
  if (!name.endsWith(assetFilenameFor(target))) {
    throw Error('Staged CMS image filename does not match the reviewed target: ' + target.imageItemId);
  }
  return url.toString();
}

export async function verifyStagedAssetBytes(target, imageField, expectedSha256, get = fetch) {
  if (!/^[0-9a-f]{64}$/.test(expectedSha256 ?? '')) {
    throw Error('Missing approved preview SHA-256: ' + target.imageItemId);
  }
  if (imageField.fileId === target.originalFileId) {
    throw Error('CMS still points at the original image: ' + target.imageItemId);
  }
  const url = validateCmsImageUrl(target, imageField);
  let bytes;
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const response = await get(url, { signal: AbortSignal.timeout(30000) });
      if (!response.ok) throw Error('Asset CDN returned HTTP ' + response.status);
      const lengthHeader = Number(response.headers?.get('content-length') ?? 0);
      if (lengthHeader > 8 * 1024 * 1024) throw Error('CDN asset too large');
      bytes = Buffer.from(await response.arrayBuffer());
      if (!bytes.length || bytes.length > 8 * 1024 * 1024) throw Error('Invalid CDN asset size');
      break;
    } catch (error) {
      if (attempt === 4 || /CDN asset too large|Invalid CDN asset size/.test(error.message)) {
        throw Error('Unable to verify staged CDN asset for ' + target.imageItemId + ': ' + error.message);
      }
      await new Promise(done => setTimeout(done, 1200 * (attempt + 1)));
    }
  }
  const actualHash = hash(bytes);
  if (actualHash !== expectedSha256) {
    throw Error('Staged CDN bytes do not match the approved preview for ' + target.imageItemId +
      ' (expected ' + expectedSha256.slice(0, 12) + ', got ' + actualHash.slice(0, 12) + '). STOP; no new upload.');
  }
  const metadata = await sharp(bytes).metadata();
  if (metadata.width !== 1200 || metadata.height !== 1600 || metadata.format !== 'webp') {
    throw Error('Staged Webflow image has wrong dimensions or format for ' + target.imageItemId);
  }
  return {
    fileId: imageField.fileId,
    url: imageField.url,
    alt: imageField.alt ?? null
  };
}

export function preserveCanonicalAsset(state, verifiedCmsAsset) {
  if (!state.uploaded?.fileId || !state.uploaded?.url) {
    throw Error('No original Webflow upload receipt in checkpoint');
  }
  if (!state.assetUpload) state.assetUpload = { ...state.uploaded };
  state.uploaded = { ...verifiedCmsAsset };
  state.status = 'applied';
  state.stageVerifiedAt = new Date().toISOString();
  return state;
}
