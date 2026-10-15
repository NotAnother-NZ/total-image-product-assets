/** Checkpointed 108-image padding batch. Existing single-image workflow is unchanged. */
import { mkdir, readFile, rename, writeFile, access } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID, createHash } from 'node:crypto';
import { config } from 'dotenv';
import sharp from 'sharp';
import { normalize, inspect, mask, restore, solid, encode, W, H } from './image.mjs';
import { edit } from './api.mjs';
import {
  discoverPlan, readVerifiedTarget, assertOtherFieldsUnchanged,
  uploadAsset, updateImageOnly, waitForHostedAsset, EXPECTED_IMAGES
} from './batch-cms.mjs';
import { aggregateUsage, printTotalUsage, createProgress } from './batch-report.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
config({ path: resolve(root, '.env'), quiet: true });
config({ path: resolve(root, '../../.env'), quiet: true });

const [command, ...argv] = process.argv.slice(2);
const commands = new Set(['plan', 'preview', 'apply', 'rollback', 'summary']);
if (!commands.has(command)) throw Error('Use: node src/batch.mjs plan|preview|apply|rollback|summary');

function parseOptions(args) {
  const allowed = new Set(['out', 'model', 'engine', 'limit', 'confirm', 'reviewed', 'retry-failed']);
  const result = {};
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i]?.replace(/^--/, '');
    if (!args[i]?.startsWith('--') || !allowed.has(key) || !args[i + 1]) {
      throw Error('Unknown or malformed option ' + args[i]);
    }
    result[key] = args[i + 1];
  }
  if (result.limit !== undefined && (!/^\d+$/.test(result.limit) || Number(result.limit) < 1)) {
    throw Error('--limit must be a positive integer');
  }
  if (result.engine && !['auto', 'ai', 'solid'].includes(result.engine)) {
    throw Error('--engine must be auto, ai, or solid');
  }
  if (result.model && !['gpt-image-2.5-sunburst', 'gpt-image-2.5-flare'].includes(result.model)) {
    throw Error('--model must be gpt-image-2.5-sunburst or gpt-image-2.5-flare');
  }
  return result;
}
const options = parseOptions(argv);
const out = resolve(root, options.out ?? 'output/batch-padding');
const file = (...parts) => join(out, ...parts);
const manifestPath = t => file(t.slug, t.imageItemId, 'manifest.json');
const itemDir = t => file(t.slug, t.imageItemId);
const hasFile = path => access(path).then(() => true, () => false);
const isYes = v => v === 'yes';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
let shouldStop = false;
process.on('SIGINT', () => {
  if (!shouldStop) console.log('\nInterrupt requested. Completing this item and writing checkpoints before stopping.');
  shouldStop = true;
});

async function atomicWrite(path, bytes) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = path + '.' + randomUUID() + '.tmp';
  await writeFile(temporary, bytes);
  await rename(temporary, path);
}
async function saveJson(path, value) { await atomicWrite(path, JSON.stringify(value, null, 2) + '\n'); }
async function readJson(path) { return JSON.parse(await readFile(path, 'utf8')); }
async function getState(t) { return await hasFile(manifestPath(t)) ? readJson(manifestPath(t)) : null; }
async function saveState(t, state) {
  await saveJson(manifestPath(t), { ...state, updatedAt: new Date().toISOString() });
}

function validatePlan(plan) {
  if (plan?.version !== 1 || plan.expectedProducts !== 47 || plan.expectedImages !== EXPECTED_IMAGES ||
      !Array.isArray(plan.targets) || plan.targets.length !== EXPECTED_IMAGES ||
      plan.siteId !== '6a4b7d4c587f58adf63bad93') {
    throw Error('Saved plan is not the audited 47-product/108-image Total Image plan');
  }
  const ids = new Set(), heroes = new Set(), slugs = new Set();
  for (const t of plan.targets) {
    if (!/^[0-9a-f]{24}$/.test(t.imageItemId) || !/^[0-9a-f]{24}$/.test(t.productId) ||
        !/^[a-z0-9-]+$/.test(t.slug) || !/^[0-9a-f]{24}$/.test(t.originalFileId)) {
      throw Error('Invalid CMS target identifier in plan');
    }
    if (ids.has(t.imageItemId)) throw Error('Duplicated Images CMS item in plan');
    ids.add(t.imageItemId);
    slugs.add(t.slug);
    if (t.isHero) {
      if (heroes.has(t.slug)) throw Error('Multiple hero targets for ' + t.slug);
      heroes.add(t.slug);
    }
  }
  if (slugs.size !== 47 || heroes.size !== 47) throw Error('Plan is missing expected products or hero references');
  return plan;
}

async function loadOrCreatePlan() {
  if (await hasFile(file('plan.json'))) return validatePlan(await readJson(file('plan.json')));
  console.log('Reading Products and Images CMS collections to verify all 108 image relationships...');
  const plan = validatePlan(await discoverPlan());
  await saveJson(file('plan.json'), plan);
  console.log('Saved plan: ' + plan.expectedProducts + ' products, ' + plan.targets.length +
    ' images, ' + plan.targets.filter(t => t.isHero).length + ' heroes.');
  return plan;
}

async function downloadSource(url) {
  const u = new URL(url);
  if (u.hostname !== 'cdn.prod.website-files.com' || u.protocol !== 'https:') {
    throw Error('Unexpected Webflow image URL; stopping');
  }
  const response = await fetch(url, { signal: AbortSignal.timeout(60000) });
  if (!response.ok) throw Error('Source image download failed: HTTP ' + response.status);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length > 50 * 1024 * 1024 || !bytes.length) throw Error('Invalid source asset size');
  return bytes;
}

function consistentTarget(originalTarget, stateTarget) {
  const keys = ['imageItemId', 'originalFileId', 'productId', 'slug', 'isHero'];
  for (const k of keys) {
    if (originalTarget[k] !== stateTarget?.[k]) throw Error('Checkpoint target differs from the saved plan');
  }
}

async function previewOne(t, engine, model, retryFailed) {
  const dir = itemDir(t);
  let state = await getState(t);
  if (state) consistentTarget(t, state.target);
  const previewPath = join(dir, 'preview.webp');
  if (state && ['ready', 'applied'].includes(state.status)) {
    if (!await hasFile(previewPath) || hash(await readFile(previewPath)) !== state.previewHash) {
      throw Error('Completed preview checksum failed; inspect before proceeding');
    }
    return 'cached';
  }
  if (state?.status === 'skipped') return 'skipped';
  if (state?.status === 'unchanged') return 'unchanged';
  if (['failed', 'manual-review'].includes(state?.status) && !retryFailed) return 'manual-review';

  const { image, product } = await readVerifiedTarget(t);
  if (image.fieldData.image.fileId !== t.originalFileId) {
    throw Error('CMS source asset changed since plan; refusing paid image generation');
  }
  if (state?.source?.image && image.lastUpdated !== state.source.image.lastUpdated) {
    throw Error('CMS item changed since checkpoint; refusing to resume');
  }
  state ??= { version: 1, target: t, createdAt: new Date().toISOString() };
  state.source ??= { image, product };
  state.status = 'processing';
  await saveState(t, state);

  const original = await downloadSource(image.fieldData.image.url);
  await atomicWrite(join(dir, 'original-source.bin'), original);
  const input = await normalize(original);
  await atomicWrite(join(dir, 'normalized.png'), input);
  let analysis;
  try { analysis = await inspect(input); }
  catch (e) {
    state.status = 'skipped';
    state.reason = 'No safe rectangular padding detected: ' + e.message;
    await saveState(t, state);
    return 'skipped';
  }
  state.analysis = analysis;
  const route = engine === 'auto' ? (analysis.uniform ? 'solid' : 'ai') : engine;
  state.engine = engine;
  state.route = route;
  state.model = route === 'ai' ? model : null;
  if (route === 'solid' && !analysis.uniform) {
    state.status = 'skipped';
    state.reason = 'Nonuniform background requires AI; solid fill refused';
    await saveState(t, state);
    return 'skipped';
  }
  await saveState(t, state);

  let restored;
  if (route === 'solid') {
    restored = await solid(input, analysis);
  } else {
    const alphaMask = await mask(analysis.rect);
    await atomicWrite(join(dir, 'mask.png'), alphaMask);
    const imagePath = join(dir, 'ai-output.png');
    const usagePath = join(dir, 'usage.json');
    let modelOutput;
    if (await hasFile(imagePath)) {
      modelOutput = await readFile(imagePath);
    } else {
      if ((await hasFile(usagePath)) || state.aiCallStartedAt) {
        state.status = 'manual-review';
        state.reason = 'Prior API request may have been billed but output is missing; refusing automatic repeat';
        await saveState(t, state);
        return 'manual-review';
      }
      state.aiCallStartedAt = new Date().toISOString();
      await saveState(t, state);
      const result = await edit(input, alphaMask, analysis, model);
      // Metered usage is persisted immediately, before any potentially failing image processing.
      await saveJson(usagePath, result.usage);
      await atomicWrite(imagePath, result.image);
      modelOutput = result.image;
    }
    restored = await restore(input, modelOutput, analysis);
  }

  await atomicWrite(join(dir, 'restored.png'), restored);
  const webp = await encode(restored);
  const beforeAfter = await sharp({ create: { width: W * 2, height: H, channels: 3, background: '#fff' } })
    .composite([{ input, left: 0, top: 0 }, { input: restored, left: W, top: 0 }])
    .jpeg({ quality: 85 }).toBuffer();
  await atomicWrite(join(dir, 'before-after.jpg'), beforeAfter);
  await atomicWrite(previewPath, webp);
  state.status = 'ready';
  state.previewHash = hash(webp);
  state.reason = null;
  await saveState(t, state);
  return 'ready';
}

async function applyOne(t) {
  const dir = itemDir(t);
  const state = await getState(t);
  if (!state) return 'not-previewed';
  consistentTarget(t, state.target);
  if (state.status === 'skipped' || state.status === 'manual-review') return state.status;
  if (!['ready', 'applied'].includes(state.status)) return 'not-ready';

  const webp = await readFile(join(dir, 'preview.webp'));
  if (hash(webp) !== state.previewHash) throw Error('Preview checksum mismatch');
  const originalImage = state.source?.image;
  if (!originalImage) throw Error('Missing original CMS backup in manifest');
  const { image, product } = await readVerifiedTarget(t);
  assertOtherFieldsUnchanged(originalImage, image);
  if (product.fieldData?.slug !== state.source?.product?.fieldData?.slug) throw Error('Product identity changed');
  if (t.isHero && product.fieldData['hero-image'] !== t.imageItemId) throw Error('Hero image reference changed');

  if (state.uploaded?.fileId && image.fieldData.image.fileId === state.uploaded.fileId) {
    if (image.fieldData.image.url !== state.uploaded.url) throw Error('Uploaded URL mismatch');
    state.status = 'applied';
    await saveState(t, state);
    return 'cached-applied';
  }
  if (image.fieldData.image.fileId !== t.originalFileId || image.lastUpdated !== originalImage.lastUpdated) {
    throw Error('Current CMS image changed since preview; refusing to overwrite');
  }
  if (!state.uploaded) {
    state.uploaded = await uploadAsset(webp, t);
    await saveState(t, state); // Uploaded asset can be reused if a later step fails.
  }

  // Recheck after uploading so concurrent CMS changes are never overwritten.
  const latest = await readVerifiedTarget(t);
  assertOtherFieldsUnchanged(originalImage, latest.image);
  if (latest.image.fieldData.image.fileId !== t.originalFileId ||
      latest.image.lastUpdated !== originalImage.lastUpdated) {
    throw Error('CMS changed during upload; uploaded asset retained for safe retry, no field updated');
  }
  await waitForHostedAsset(state.uploaded.url);
  const replacement = {
    fileId: state.uploaded.fileId,
    url: state.uploaded.url,
    alt: originalImage.fieldData.image.alt ?? null
  };
  await updateImageOnly(t, replacement);
  const verified = await readVerifiedTarget(t);
  assertOtherFieldsUnchanged(originalImage, verified.image);
  if (verified.image.fieldData.image.fileId !== replacement.fileId ||
      verified.image.fieldData.image.url !== replacement.url) {
    throw Error('Webflow returned unexpected image field after update; check CMS before proceeding');
  }
  state.status = 'applied';
  await saveState(t, state);
  return 'applied';
}

async function rollbackOne(t) {
  const state = await getState(t);
  if (!state || !['applied', 'rolled-back'].includes(state.status)) return 'not-applied';
  consistentTarget(t, state.target);
  if (state.status === 'rolled-back') return 'already-rolled-back';
  const { image } = await readVerifiedTarget(t);
  assertOtherFieldsUnchanged(state.source.image, image);
  if (image.fieldData.image.fileId !== state.uploaded?.fileId) {
    throw Error('Current image no longer matches this batch upload; refusing rollback');
  }
  await updateImageOnly(t, state.source.image.fieldData.image);
  const verified = await readVerifiedTarget(t);
  if (verified.image.fieldData.image.fileId !== t.originalFileId) throw Error('Rollback verification failed');
  assertOtherFieldsUnchanged(state.source.image, verified.image);
  state.status = 'rolled-back';
  await saveState(t, state);
  return 'rolled-back';
}

async function summarize(plan, results = []) {
  const counts = { ready: 0, applied: 0, unchanged: 0, skipped: 0, failed: 0, manualReview: 0, notStarted: 0, rolledBack: 0 };
  const entries = [], reports = [];
  let uncertainCalls = 0;
  for (const t of plan.targets) {
    const state = await getState(t);
    const status = state?.status ?? 'not-started';
    const key = ({ ready: 'ready', applied: 'applied', skipped: 'skipped', failed: 'failed',
      'manual-review': 'manualReview', 'not-started': 'notStarted', 'rolled-back': 'rolledBack', unchanged: 'unchanged' })[status] ?? 'notStarted';
    counts[key]++;
    const receipt = file(t.slug, t.imageItemId, 'usage.json');
    uncertainCalls += state?.previousUnreceiptedAttempts?.length ?? 0;
    if (await hasFile(receipt)) reports.push(await readJson(receipt));
    else if (state?.aiCallStartedAt) uncertainCalls++;
    entries.push({
      slug: t.slug, productName: t.productName, imageItemId: t.imageItemId, isHero: t.isHero,
      status, reason: state?.reason ?? null, route: state?.route ?? null,
      preview: state?.previewHash ? file(t.slug, t.imageItemId, 'preview.webp') : null
    });
  }
  const usage = aggregateUsage(reports);
  usage.unknownApiRequests = uncertainCalls;
  // An HTTP/network failure after an API call starts may still be billable.
  // Do not mark the overall batch cost complete just because all received receipts were priced.
  usage.completeCost = usage.completeCost && uncertainCalls === 0;
  const summary = { updatedAt: new Date().toISOString(), counts, uncertainCalls, usage, entries, recentResults: results };
  await saveJson(file('summary.json'), summary);
  console.log('\nBATCH STATUS:', JSON.stringify(counts));
  printTotalUsage(usage);
  if (uncertainCalls) {
    console.warn('WARNING: ' + uncertainCalls +
      ' OpenAI request(s) may have been billed without a response receipt; recorded cost may be incomplete.');
  }
  console.log('Saved local checkpoint report:', file('summary.json'));
  return summary;
}

async function main() {
  if (['apply', 'rollback'].includes(command)) {
    const expected = command === 'apply' ? 'APPLY_REVIEWED_108_IMAGES' : 'ROLLBACK_108_IMAGES';
    if (options.confirm !== expected || !isYes(options.reviewed)) {
      throw Error('For ' + command + ', pass: --reviewed yes --confirm ' + expected);
    }
  }

  const plan = await loadOrCreatePlan();
  if (command === 'plan') {
    console.log('Verified plan with ' + plan.targets.length + ' images. No OpenAI or CMS writes.');
    return;
  }
  if (command === 'summary') {
    await summarize(plan);
    return;
  }

  const model = options.model ?? process.env.OPENAI_IMAGE_MODEL ?? 'gpt-image-2.5-sunburst';
  if (!['gpt-image-2.5-sunburst', 'gpt-image-2.5-flare'].includes(model)) throw Error('Unsupported OpenAI image model');
  const engine = options.engine ?? 'ai';
  const limit = options.limit ? Number(options.limit) : Infinity;
  const retryFailed = isYes(options['retry-failed']);
  let attempted = 0, complete = 0;
  const results = [];
  const progress = createProgress(plan.targets.length);
  console.log('Mode: ' + command + '. Images: ' + plan.targets.length + '. Engine: ' + engine + '. Model: ' + model + '.');
  if (command === 'preview') console.log('READ-ONLY in Webflow. Existing successful previews are reused.');
  if (command === 'apply') console.log('Staged Images CMS field updates only; no publishing or deletion.');

  try {
    for (const t of plan.targets) {
      if (shouldStop || attempted >= limit) break;
      if (command === 'preview') {
        const state = await getState(t);
        if (state && ['ready', 'applied', 'skipped', 'unchanged'].includes(state.status)) {
          try {
            const result = await previewOne(t, engine, model, retryFailed);
            results.push({ image: t.imageItemId, result });
          } catch (e) {
            results.push({ image: t.imageItemId, result: 'failed', message: e.message });
            progress.note('ERROR ' + t.slug + '/' + t.imageItemId + ': ' + e.message);
          }
          complete++;
          progress.step('checkpoint reused');
          continue;
        }
        if (state && ['failed', 'manual-review'].includes(state.status) && !retryFailed) {
          complete++;
          progress.step('review required');
          continue;
        }
      } else if (command === 'apply') {
        const state = await getState(t);
        if (!state || ['skipped', 'unchanged', 'manual-review', 'failed', 'processing'].includes(state.status)) {
          complete++;
          progress.step('no approved preview');
          continue;
        }
        if (state.status === 'applied') {
          complete++;
          progress.step('already applied');
          continue;
        }
      } else if (command === 'rollback') {
        const state = await getState(t);
        if (!state || !['applied', 'rolled-back'].includes(state.status)) {
          complete++;
          progress.step('nothing to roll back');
          continue;
        }
        if (state.status === 'rolled-back') {
          complete++;
          progress.step('already rolled back');
          continue;
        }
      }

      progress.update(t.productName.slice(0, 25) + (t.isHero ? ' (hero)' : ''));
      attempted++;
      let result;
      try {
        if (command === 'preview') result = await previewOne(t, engine, model, retryFailed);
        if (command === 'apply') result = await applyOne(t);
        if (command === 'rollback') result = await rollbackOne(t);
        results.push({ image: t.imageItemId, result });
      } catch (e) {
        result = 'failed';
        results.push({ image: t.imageItemId, result, message: e.message });
        progress.note('ERROR ' + t.slug + '/' + t.imageItemId + ': ' + e.message);
        if (command === 'preview') {
          const state = await getState(t);
          if (state && state.status === 'processing') {
            state.status = 'failed';
            state.reason = e.message;
            await saveState(t, state);
          }
        }
      }
      complete++;
      progress.step(result + ' ' + t.slug.slice(0, 22) + ' (' + complete + '/' + plan.targets.length + ')');
    }
  } finally {
    progress.close();
    const summary = await summarize(plan, results);
    if (summary.counts.failed || summary.counts.manualReview) {
      console.log('Some images need manual review; see summary.json. No unsafe automatic retries.');
    }
    if (shouldStop) console.log('Stopped cleanly after checkpointing. Re-run the same command to resume.');
  }
}

main().catch(e => {
  console.error('ERROR:', e.message);
  process.exitCode = 1;
});
