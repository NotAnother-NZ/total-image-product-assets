/**
 * Total Image: stage and individually publish 106 approved Images CMS assets.
 * NEVER publishes the entire site. CMS item publication can affect all live domains.
 */
import { readFile, writeFile, rename, mkdir } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import sharp from 'sharp';
import { config } from 'dotenv';
import { wf } from './api.mjs';
import { createProgress } from './batch-report.mjs';
import {
  SITE_ID, IMAGES_COLLECTION_ID, PRIMARY_CMS_LOCALE, REPLACEMENT_COUNT,
  validateLocalBatch, verifyStagedImage, classifyLiveImage, validatePublishedIds
} from './deploy-guards.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
config({ path: join(root, '.env'), quiet: true });
config({ path: resolve(root, '../../.env'), quiet: true });

// SAFETY: The selected-CMS-item publish API is not domain-scoped.
// This site has production custom domains. Fail closed for every publication mode.
if (process.argv.slice(2).some(a => ['publish','deploy'].includes(a))) {
  console.error('BLOCKED: Webflow CMS item publishing is not restricted to the staging subdomain. Production custom domains must remain untouched.');
  console.error('Staging CMS changes is permitted; publication requires a separately verified staging-only method.');
  process.exit(1);
}
const [mode, ...rawOptions] = process.argv.slice(2);
if (!['check', 'publish', 'verify', 'deploy'].includes(mode)) {
  throw Error('Usage: node src/batch-deploy.mjs check|deploy|publish|verify [--out DIR] [--confirm TOKEN] [--ack-all-domains yes]');
}
const opts = {};
const allowed = new Set(['out','confirm','ack-all-domains']);
for (let i = 0; i < rawOptions.length; i += 2) {
  const k = rawOptions[i]?.slice(2);
  if (!rawOptions[i]?.startsWith('--') || !allowed.has(k) || !rawOptions[i + 1] || opts[k]) {
    throw Error('Invalid option ' + rawOptions[i]);
  }
  opts[k] = rawOptions[i + 1];
}
const dataDir = resolve(root, opts.out ?? 'output/batch-padding');
const manifestFile = t => join(dataDir, t.slug, t.imageItemId, 'manifest.json');
const previewFile = t => join(dataDir, t.slug, t.imageItemId, 'preview.webp');
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
let shouldStop = false;
process.on('SIGINT', () => {
  shouldStop = true;
  console.log('\nInterrupt requested. Publishing stops after the current batch has been verified.');
});

async function readJson(file) { return JSON.parse(await readFile(file, 'utf8')); }
async function atomicJson(file, value) {
  await mkdir(dirname(file), { recursive: true });
  const temp = file + '.' + randomUUID() + '.tmp';
  await writeFile(temp, JSON.stringify(value, null, 2) + '\n');
  await rename(temp, file);
}
async function withGetRetry(path) {
  for (let tries = 0; ; tries++) {
    try { return await wf(path); }
    catch (error) {
      if (tries >= 6 || !/HTTP (429|500|502|503|504)\b/.test(String(error.message))) throw error;
      await new Promise(done => setTimeout(done, Math.min(30000, 1500 * 2 ** tries)));
    }
  }
}
async function readCmsStaged(t) {
  return withGetRetry('/collections/' + IMAGES_COLLECTION_ID + '/items/' + t.imageItemId);
}
async function readCmsLive(t) {
  return withGetRetry('/collections/' + IMAGES_COLLECTION_ID + '/items/' + t.imageItemId + '/live');
}
async function readProduct(t) {
  return withGetRetry('/collections/6ab0acfdb063e14a30f65e5c/items/' + t.productId);
}
async function assertProductIdentity(t) {
  const product = await readProduct(t);
  if (product.id !== t.productId || product.fieldData?.slug !== t.slug ||
      (t.isHero && product.fieldData?.['hero-image'] !== t.imageItemId)) {
    throw Error('Product/hero link changed for ' + t.slug + ' (' + t.imageItemId + ')');
  }
}

async function loadBatch(requireStaged = false) {
  const plan = await readJson(join(dataDir, 'plan.json'));
  const snapshots = await Promise.all(plan.targets.map(async t => ({
    target:t, ...(await readJson(manifestFile(t)))
  })));
  const { replacements, unchanged } = validateLocalBatch(plan, snapshots);
  for (const { target, state } of replacements) {
    if (sha256(await readFile(previewFile(target))) !== state.previewHash) {
      throw Error('Preview was changed after approval: ' + target.imageItemId);
    }
    const meta = await sharp(previewFile(target)).metadata();
    if (meta.format !== 'webp' || meta.width !== 1200 || meta.height !== 1600) {
      throw Error('Incorrect WebP dimensions for ' + target.imageItemId);
    }
    if (requireStaged && (state.status !== 'applied' || !state.uploaded?.fileId || !state.uploaded?.url)) {
      throw Error('All 106 images must be staged before publication: ' + target.imageItemId);
    }
  }
  return { plan, replacements, unchanged };
}

async function printSiteDomains() {
  const site = await withGetRetry('/sites/' + SITE_ID);
  if (site.id !== SITE_ID || site.locales?.primary?.cmsLocaleId !== PRIMARY_CMS_LOCALE) {
    throw Error('Wrong Webflow site or primary CMS locale');
  }
  console.log('Site: ' + site.displayName + ' (' + site.shortName + ')');
  console.log('Site last published: ' + (site.lastPublished ?? 'never'));
  const webflowPublished = Date.parse(site.lastPublished ?? '');
  let mismatch = false;
  for (const domain of site.customDomains ?? []) {
    console.log('Custom domain: ' + domain.url + ' (site last published: ' + (domain.lastPublished ?? 'never') + ')');
    const d = Date.parse(domain.lastPublished ?? '');
    if (Number.isFinite(webflowPublished) && Number.isFinite(d) &&
        Math.abs(webflowPublished - d) > 60_000) mismatch = true;
  }
  if (mismatch) {
    console.warn('WARNING: The Webflow site and custom domains have different publish times.');
    console.warn('Webflow may block individual CMS publication until domain publication states are synchronized.');
    console.warn('This tool NEVER performs a full-site publish, which could expose unrelated staged changes.');
  }
  if ((site.customDomains ?? []).length) {
    console.warn('IMPORTANT: CMS item publishing CANNOT be limited to the Webflow staging subdomain.');
    console.warn('Publishing can affect custom production domains:');
    for (const d of site.customDomains) console.warn('  ' + d.url);
  }
  return {site, mismatch};
}

async function verifyCurrent(checkpoints, mode) {
  const progress = createProgress(checkpoints.replacements.length);
  const needPublish = [], alreadyLive = [];
  console.log('Checking staged and live CMS images and product relationships (read-only)...');
  for (const {target:t,state:s} of checkpoints.replacements) {
    if (shouldStop) throw Error('Interrupted during pre-publication verification; no publishing started');
    const [staged, live] = await Promise.all([readCmsStaged(t), readCmsLive(t)]);
    if (mode === 'publish' || s.status === 'applied') {
      verifyStagedImage(s.source.image, staged, s.uploaded, t);
    }
    await assertProductIdentity(t);
    const status = classifyLiveImage(s.source.image, live, s.uploaded, t);
    if (status === 'already-live') alreadyLive.push({target:t,state:s});
    else needPublish.push({target:t,state:s});
    progress.step('Verified ' + t.slug.slice(0,24));
  }
  for (const {target:t,state:s} of checkpoints.unchanged) {
    const [staged, live] = await Promise.all([readCmsStaged(t), readCmsLive(t)]);
    if (staged.fieldData?.image?.fileId !== t.originalFileId ||
        live.fieldData?.image?.fileId !== t.originalFileId) {
      throw Error('One of the two belt images has changed: ' + t.imageItemId);
    }
    if (classifyLiveImage(s.source.image, live, null, t) !== 'not-yet-live') {
      throw Error('Retained belt unexpectedly changed in live CMS');
    }
    await assertProductIdentity(t);
    if (JSON.stringify({...staged.fieldData,image:undefined}) !==
        JSON.stringify({...s.source.image.fieldData,image:undefined})) {
      throw Error('Unrelated staged changes on retained belt ' + t.imageItemId);
    }
  }
  return { needPublish, alreadyLive };
}

async function verifyLiveAfterPublish(target, state) {
  for (let tries = 0; tries < 12; tries++) {
    const live = await readCmsLive(target);
    const status = classifyLiveImage(state.source.image, live, state.uploaded, target);
    if (status === 'already-live') return live;
    await new Promise(done => setTimeout(done, 2500));
  }
  throw Error('Item publish was accepted but live API did not show new asset: ' + target.imageItemId);
}

async function publishApproved(initial) {
  let completed = initial.alreadyLive.length;
  const progress = createProgress(REPLACEMENT_COUNT, completed);
  console.log('\nLive images already matching approved previews: ' + completed);
  console.log('Remaining items to publish: ' + initial.needPublish.length);
  for (let start = 0; start < initial.needPublish.length; start += 10) {
    if (shouldStop) break;
    const chunk = initial.needPublish.slice(start, start + 10);
    const toPublish = [];
    // Recheck immediately before publishing each group to avoid racing another editor.
    for (const item of chunk) {
      const {target:t,state:s} = item;
      const [staged, live] = await Promise.all([readCmsStaged(t), readCmsLive(t)]);
      verifyStagedImage(s.source.image, staged, s.uploaded, t);
      const liveStatus = classifyLiveImage(s.source.image, live, s.uploaded, t);
      if (liveStatus === 'not-yet-live') toPublish.push(item);
      else {
        completed++;
        progress.step('Already live ' + t.slug.slice(0,24));
      }
    }
    if (!toPublish.length) continue;
    const requested = toPublish.map(x => x.target.imageItemId);
    console.log('\nPublishing ' + requested.length + ' specifically selected Images CMS items...');
    // POST is never automatically retried. A lost response may mask a successful publish.
    const response = await wf('/collections/' + IMAGES_COLLECTION_ID + '/items/publish',
      'POST', {itemIds:requested});
    // HTTP 202 can include individual failures; treat incomplete results as errors.
    validatePublishedIds(requested, response);
    for (const {target:t,state:s} of toPublish) {
      await verifyLiveAfterPublish(t,s);
      s.publishAudit = {
        verifiedAt:new Date().toISOString(),
        fileId:s.uploaded.fileId,
        method:'selected-images-cms-item-publish'
      };
      await atomicJson(manifestFile(t),s);
      completed++;
      progress.step('Live ' + t.slug.slice(0,24));
    }
  }
  console.log('\nVerified live replacements: ' + completed + '/' + REPLACEMENT_COUNT);
  if (shouldStop) console.warn('Interrupted; rerun to verify and resume, without reuploading assets.');
  return completed;
}

async function startExistingStaging(batchDir) {
  const args = [join(root, 'src/batch.mjs'), 'apply', '--out', batchDir,
    '--reviewed','yes','--confirm','APPLY_REVIEWED_108_IMAGES'];
  console.log('Launching the existing checkpointed stage/apply workflow. This stage does not publish.');
  await new Promise((complete,reject) => {
    const proc = spawn(process.execPath,args,{cwd:root,env:process.env,stdio:'inherit'});
    proc.on('error',reject);
    proc.on('close',code => code === 0 ? complete() : reject(Error('Existing batch:apply exited '+code)));
  });
}

function confirmPublish() {
  if (opts.confirm !== 'PUBLISH_106_TOTAL_IMAGE_IMAGES_ALL_DOMAINS' ||
      opts['ack-all-domains'] !== 'yes') {
    throw Error('Publishing can affect the custom production domains. Required: --confirm PUBLISH_106_TOTAL_IMAGE_IMAGES_ALL_DOMAINS --ack-all-domains yes');
  }
}

async function main() {
  if (['publish','deploy'].includes(mode)) confirmPublish();
  let records = await loadBatch(false);
  console.log('Approved batch: 106 replacement WebPs, 2 original belts retained, 47 products.');
  await printSiteDomains();
  if (mode === 'check') {
    console.log('Local preflight passed: backups, WebP dimensions, checksums, CMS identities.');
    console.log('No CMS images were modified. Publication can affect all configured domains.');
    return;
  }
  if (mode === 'deploy') {
    await startExistingStaging(dataDir);
    records = await loadBatch(true); // abort if any of the 106 failed to stage
  } else {
    records = await loadBatch(true);
  }
  const initial = await verifyCurrent(records, mode);
  if (mode === 'verify') {
    console.log('Live verified: ' + initial.alreadyLive.length + '/' + REPLACEMENT_COUNT +
      ' replacements; ' + records.unchanged.length + ' original belts unchanged.');
    if (initial.needPublish.length) {
      console.warn('Still showing original asset on ' + initial.needPublish.length + ' live item(s).');
      process.exitCode = 2;
    }
    return;
  }
  await publishApproved(initial);
  if (!shouldStop) {
    console.log('CMS publication attempted. Verify all 106 live records with npm run batch:deploy:verify.');
  }
}

main().catch(error => {
  console.error('DEPLOYMENT STOPPED:',error.message);
  console.error('Safe recovery: inspect current Webflow CMS, then run npm run batch:deploy:verify before retrying publication.');
  process.exitCode = 1;
});
