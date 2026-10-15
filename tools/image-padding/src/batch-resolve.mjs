/**
 * Targeted, opt-in resolution of seven unfinished images from the
 * 2026-10-15 Total Image padding audit. Never touches 101 accepted previews.
 * Preview-only: no Webflow CMS writes or publishing.
 */
import { readFile, writeFile, rename, mkdir, access } from 'node:fs/promises';
import { randomUUID, createHash } from 'node:crypto';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from 'dotenv';
import sharp from 'sharp';
import { normalize, inspect, mask, restore, solid, encode, W, H } from './image.mjs';
import { inspectPaddedPhoto } from './padding-fallback.mjs';
import { readVerifiedTarget } from './batch-cms.mjs';
import { edit } from './api.mjs';

export const GREY_INSET_IMAGES = Object.freeze([
  '6ac695326e49045ca5ee8dec', // Allegra White
  '6ac68d0b1552026a605e13d3', // Arc Eco Square Wireless Charger
  '6ac69536f4670283e5ab6e84', // Summit White
  '6ac6952900df4c45cf93d351'  // Sunrise Smoothie White
]);
export const LEAVE_ORIGINAL_IMAGES = Object.freeze([
  '6ac68f89d92cda95eb51ac8d', // Casual Braided Belt Navy Brown
  '6ac68f881c342211e8d597b9'  // Casual Braided Belt Black Black
]);
export const OAKLEIGH_FAILED_IMAGE = '6ac6948b14526571351528ef';
const allowedIds = new Set([...GREY_INSET_IMAGES, ...LEAVE_ORIGINAL_IMAGES, OAKLEIGH_FAILED_IMAGE]);
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
config({ path: resolve(root, '.env'), quiet: true });
config({ path: resolve(root, '../../.env'), quiet: true });

const sha256 = data => createHash('sha256').update(data).digest('hex');
const exists = path => access(path).then(() => true, () => false);
async function atomicWrite(path, contents) {
  await mkdir(dirname(path), { recursive: true });
  const tmp = path + '.' + randomUUID() + '.tmp';
  await writeFile(tmp, contents);
  await rename(tmp, path);
}
async function writeJson(path, value) {
  await atomicWrite(path, JSON.stringify(value, null, 2) + '\n');
}
async function loadTarget(folder, id) {
  const plan = JSON.parse(await readFile(join(folder, 'plan.json'), 'utf8'));
  if (!Array.isArray(plan.targets) || plan.targets.length !== 108 || plan.expectedProducts !== 47 || plan.expectedImages !== 108) {
    throw Error('Expected the original, complete 47-product / 108-image audit plan');
  }
  const matching = plan.targets.filter(t => t.imageItemId === id);
  if (!allowedIds.has(id) || matching.length !== 1) throw Error('Image not in the seven specifically reviewed targets: ' + id);
  const target = matching[0];
  const dir = join(folder, target.slug, target.imageItemId);
  const manifestPath = join(dir, 'manifest.json');
  const state = JSON.parse(await readFile(manifestPath, 'utf8'));
  for (const k of ['imageItemId', 'originalFileId', 'productId', 'slug', 'isHero']) {
    if (target[k] !== state.target?.[k]) throw Error('Checkpoint target mismatch on ' + id);
  }
  if (!state.source?.image || state.source.image.fieldData?.image?.fileId !== target.originalFileId) {
    throw Error('Missing intact original Webflow image backup on ' + id);
  }
  return { target, state, dir, manifestPath };
}
async function verifyUnchangedCms(item) {
  const { image, product } = await readVerifiedTarget(item.target);
  if (image.fieldData?.image?.fileId !== item.target.originalFileId ||
      image.lastUpdated !== item.state.source.image.lastUpdated ||
      product.fieldData?.slug !== item.target.slug) {
    throw Error('Webflow source asset or CMS item changed since the first preview; not processing ' + item.target.imageItemId);
  }
}
async function verifiedSource(item) {
  const original = await readFile(join(item.dir, 'original-source.bin'));
  const normalized = await readFile(join(item.dir, 'normalized.png'));
  if (sha256(await normalize(original)) !== sha256(normalized)) {
    throw Error('Normalized source differs from untouched original backup: ' + item.target.imageItemId);
  }
  return normalized;
}
async function savePreview(item, input, corrected, analysis, method) {
  const webp = await encode(corrected);
  const beforeAfter = await sharp({ create: { width: 2 * W, height: H, channels: 3, background: '#ffffff' } })
    .composite([{input, left: 0, top: 0}, {input: corrected, left: W, top: 0}])
    .jpeg({ quality: 85 }).toBuffer();
  await atomicWrite(join(item.dir, 'restored.png'), corrected);
  await atomicWrite(join(item.dir, 'before-after.jpg'), beforeAfter);
  await atomicWrite(join(item.dir, 'preview.webp'), webp);
  item.state.status = 'ready';
  item.state.previewHash = sha256(webp);
  item.state.analysis = analysis;
  item.state.route = method;
  item.state.engine = 'targeted-review-resolution';
  item.state.model = method === 'solid' ? null : item.state.model;
  item.state.reason = null;
  item.state.updatedAt = new Date().toISOString();
  await writeJson(item.manifestPath, item.state);
}

export async function resolveReviewedImages(folder) {
  let changed = 0, unchanged = 0, errors = 0;
  for (const id of GREY_INSET_IMAGES) {
    try {
      const item = await loadTarget(folder, id);
      if (item.state.status === 'ready') {
        console.log('Already ready, preserved:', item.target.slug, id);
        continue;
      }
      if (item.state.status !== 'skipped') throw Error('Expected skipped status for grey rectangle; saw ' + item.state.status);
      await verifyUnchangedCms(item);
      const input = await verifiedSource(item);
      const analysis = await inspectPaddedPhoto(input);
      if (analysis.detector !== 'uniform-edge-fallback' || !analysis.uniform) {
        throw Error('Expected verified uniform inset; will not use a different detection path');
      }
      const corrected = await solid(input, analysis);
      await savePreview(item, input, corrected, analysis, 'solid');
      changed++;
      console.log('SAFE PREVIEW:', item.target.slug, id, analysis.hex, analysis.rect);
    } catch (error) {
      errors++;
      console.error('MANUAL REVIEW:', id, error.message);
    }
  }

  for (const id of LEAVE_ORIGINAL_IMAGES) {
    try {
      const item = await loadTarget(folder, id);
      if (item.state.status === 'unchanged') {
        console.log('Already left intact:', item.target.slug, id);
        continue;
      }
      if (item.state.status !== 'skipped') throw Error('Expected previously skipped belt image, got ' + item.state.status);
      await verifyUnchangedCms(item);
      const normalized = await verifiedSource(item);
      const { data, info } = await sharp(normalized).removeAlpha().raw().toBuffer({ resolveWithObject: true });
      if (info.width !== W || info.height !== H) throw Error('Wrong source dimensions');
      const colour = (x, y) => Array.from(data.subarray((y * W + x) * 3, (y * W + x) * 3 + 3));
      for (const [x,y] of [[1,1],[W-2,1],[1,H-2],[W-2,H-2]]) {
        if (colour(x,y).some(v => v < 245)) throw Error('The original canvas corners are not white; require manual review');
      }
      // Documented visual decision for exactly two belt images:
      // no contrasting rectangle is visible; do not generate/upload replacements.
      item.state.status = 'unchanged';
      item.state.reason = 'Original white-on-white product image is already visually seamless; preserving original asset';
      item.state.updatedAt = new Date().toISOString();
      await writeJson(item.manifestPath, item.state);
      unchanged++;
      console.log('NO CHANGE NEEDED:', item.target.slug, id);
    } catch (error) {
      errors++;
      console.error('MANUAL REVIEW:', id, error.message);
    }
  }
  console.log('\nTargeted result: ' + changed + ' new lossless-interior previews, ' + unchanged +
    ' original images preserved, ' + errors + ' requiring manual review.');
  console.log('OpenAI requests: 0. New OpenAI cost: $0.');
  console.log('Next: npm run batch:summary && npm run batch:review');
  if (errors) process.exitCode = 1;
}

export async function retryOakleigh(folder, confirm, model) {
  if (!['gpt-image-2.5-sunburst', 'gpt-image-2.5-flare'].includes(model)) {
    throw Error('Unsupported OpenAI image model');
  }
  if (confirm !== 'RETRY_OAKLEIGH_MAY_INCUR_COST') {
    throw Error('Explicit approval required: --confirm RETRY_OAKLEIGH_MAY_INCUR_COST');
  }
  const item = await loadTarget(folder, OAKLEIGH_FAILED_IMAGE);
  if (item.state.status === 'ready') {
    console.log('Oakleigh already ready. No new OpenAI request.');
    return;
  }
  if (!['failed', 'manual-review'].includes(item.state.status)) {
    throw Error('Refusing Oakleigh retry from status ' + item.state.status);
  }
  const usagePath = join(item.dir, 'usage.json');
  const imagePath = join(item.dir, 'ai-output.png');
  if (await exists(usagePath) || await exists(imagePath)) {
    throw Error('An API usage receipt or generated image already exists; refusing another paid request');
  }
  await verifyUnchangedCms(item);
  const input = await verifiedSource(item);
  const analysis = await inspect(input);
  if (analysis.uniform !== true) throw Error('Expected the validated grey interior from original Oakleigh preview');
  const alpha = await mask(analysis.rect);
  await atomicWrite(join(item.dir, 'mask.png'), alpha);

  if (item.state.aiCallStartedAt) {
    item.state.previousUnreceiptedAttempts ??= [];
    item.state.previousUnreceiptedAttempts.push({
      startedAt: item.state.aiCallStartedAt,
      reason: item.state.reason ?? 'Previous API request did not return a usage receipt'
    });
  }
  item.state.aiCallStartedAt = new Date().toISOString();
  item.state.status = 'processing';
  item.state.reason = null;
  item.state.model = model;
  await writeJson(item.manifestPath, item.state);

  try {
    const result = await edit(input, alpha, analysis, model);
    // Persist usage before image postprocessing so any charge is accounted for.
    await writeJson(usagePath, result.usage);
    await atomicWrite(imagePath, result.image);
    const corrected = await restore(input, result.image, analysis);
    await savePreview(item, input, corrected, analysis, 'ai');
    console.log('Oakleigh retry completed. Original pixels preserved. Inspect the new before-after.jpg.');
  } catch (error) {
    item.state.status = 'failed';
    item.state.reason = error.message;
    await writeJson(item.manifestPath, item.state);
    throw error;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command,...args] = process.argv.slice(2);
  if (!['resolve','retry-oakleigh'].includes(command)) throw Error('Usage: node src/batch-resolve.mjs resolve|retry-oakleigh [--out PATH] [--confirm TOKEN] [--model MODEL]');
  const options = {};
  for(let i=0;i<args.length;i+=2){
    if(!args[i]?.startsWith('--') || !['out','confirm','model'].includes(args[i].slice(2)) || !args[i+1]) throw Error('Unexpected or incomplete option '+args[i]);
    options[args[i].slice(2)] = args[i+1];
  }
  const folder = resolve(root, options.out ?? 'output/batch-padding');
  const model = options.model ?? process.env.OPENAI_IMAGE_MODEL ?? 'gpt-image-2.5-sunburst';
  if(command==='resolve') {
    resolveReviewedImages(folder).catch(error => {console.error('RESOLUTION ERROR:',error.message);process.exitCode=1;});
  } else {
    retryOakleigh(folder,options.confirm,model).catch(error => {console.error('OAKLEIGH RETRY ERROR:',error.message);process.exitCode=1;});
  }
}
