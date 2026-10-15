import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { inspect, solid, encode, W, H } from '../src/image.mjs';
import { inspectPaddedPhoto } from '../src/padding-fallback.mjs';
import {
  GREY_INSET_IMAGES, LEAVE_ORIGINAL_IMAGES, OAKLEIGH_FAILED_IMAGE, retryOakleigh
} from '../src/batch-resolve.mjs';

async function subjectOnGray() {
  const object = await sharp({create:{width:150,height:420,channels:3,background:'#ffffff'}}).png().toBuffer();
  const inner=await sharp({create:{width:744,height:992,channels:3,background:'#ececec'}})
    .composite([{input:object,left:280,top:280}]).png().toBuffer();
  return sharp({create:{width:W,height:H,channels:3,background:'#ffffff'}})
    .composite([{input:inner,left:228,top:304}]).png().toBuffer();
}
async function subjectOnWhite() {
  const object=await sharp({create:{width:380,height:300,channels:3,background:'#111111'}}).png().toBuffer();
  return sharp({create:{width:W,height:H,channels:3,background:'#ffffff'}})
    .composite([{input:object,left:410,top:650}]).png().toBuffer();
}

test('review only affects the four correct grey photos and two belt images', () => {
  assert.equal(GREY_INSET_IMAGES.length,4);
  assert.equal(LEAVE_ORIGINAL_IMAGES.length,2);
  assert.equal(new Set([...GREY_INSET_IMAGES,...LEAVE_ORIGINAL_IMAGES,OAKLEIGH_FAILED_IMAGE]).size,7);
});

test('strict detector rejects white product on grey despite a valid rectangular inset', async () => {
  await assert.rejects(inspect(await subjectOnGray()), /Unsafe interior detection/);
});

test('uniform-edge fallback detects grey photo and restores margins without changing central pixels', async () => {
  const original=await subjectOnGray(),info=await inspectPaddedPhoto(original);
  assert.equal(info.detector,'uniform-edge-fallback');
  assert.equal(info.hex,'#ececec');
  assert.deepEqual(info.rect,{left:228,top:304,width:744,height:992});
  const restored=await solid(original,info);
  const before=await sharp(original).extract(info.rect).raw().toBuffer();
  const after=await sharp(restored).extract(info.rect).raw().toBuffer();
  assert.ok(before.equals(after));
  const raw=await sharp(restored).raw().toBuffer();
  assert.deepEqual([...raw.subarray(0,3)],[236,236,236]);
  const meta=await sharp(await encode(restored)).metadata();
  assert.equal(meta.width,1200); assert.equal(meta.height,1600); assert.equal(meta.format,'webp');
});

test('fallback rejects white seamless image with dark belt product', async () => {
  await assert.rejects(inspectPaddedPhoto(await subjectOnWhite()), /Fallback refused/);
});

test('fallback rejects blank white canvas', async () => {
  const white=await sharp({create:{width:W,height:H,channels:3,background:'#fff'}}).png().toBuffer();
  await assert.rejects(inspectPaddedPhoto(white), /Fallback refused/);
});

test('fallback refuses edges that are not uniformly the authentic grey background', async () => {
  const source=await subjectOnGray();
  const edge=await sharp({create:{width:744,height:40,channels:3,background:'#c40001'}}).png().toBuffer();
  const altered=await sharp(source).composite([{input:edge,left:228,top:304}]).png().toBuffer();
  await assert.rejects(inspectPaddedPhoto(altered), /Fallback refused/);
});

test('Oakleigh retry cannot issue an API call without exact consent and a supported model', async () => {
  await assert.rejects(retryOakleigh('/does-not-exist', undefined, 'gpt-image-2.5-sunburst'),
    /Explicit approval required/);
  await assert.rejects(retryOakleigh('/does-not-exist','RETRY_OAKLEIGH_MAY_INCUR_COST','unsupported-model'),
    /Unsupported OpenAI image model/);
});
