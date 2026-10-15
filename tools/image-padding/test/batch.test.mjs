import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { createTargetPlan, EXPECTED_IMAGES, assertOtherFieldsUnchanged } from '../src/batch-cms.mjs';
import { AFFECTED_PRODUCT_SLUGS } from '../src/batch-targets.mjs';
import { aggregateUsage } from '../src/batch-report.mjs';
import { normalize, inspect, solid, encode, W, H } from '../src/image.mjs';

function id(n) { return n.toString(16).padStart(24, '0'); }
function sampleCms() {
  const products = AFFECTED_PRODUCT_SLUGS.map((slug, index) => ({
    id: id(index + 1), fieldData: { slug, name: slug, 'hero-image': id(1000 + index + 1) }
  }));
  const images = products.flatMap((p, i) => {
    const count = i < 14 ? 3 : 2;
    return Array.from({length: count}, (_, j) => ({
      id: j ? id(2000 + i * 4 + j) : p.fieldData['hero-image'],
      isDraft: false, isArchived: false,
      fieldData: {
        product: p.id,
        image: { fileId: id(4000 + i * 4 + j), url: 'https://cdn.prod.website-files.com/example.webp' },
        name: 'Image ' + i, 'sort-order': j + 1
      }
    }));
  });
  return { products, images };
}

test('47 distinct audited product slugs', () => {
  assert.equal(AFFECTED_PRODUCT_SLUGS.length, 47);
  assert.equal(new Set(AFFECTED_PRODUCT_SLUGS).size, 47);
});
test('builds exactly 108 targets including 47 heroes and 61 other images', () => {
  const { products, images } = sampleCms();
  const plan = createTargetPlan(products, images);
  assert.equal(plan.expectedProducts, 47);
  assert.equal(plan.targets.length, EXPECTED_IMAGES);
  assert.equal(new Set(plan.targets.map(x => x.imageItemId)).size, 108);
  assert.equal(plan.targets.filter(x => x.isHero).length, 47);
  assert.deepEqual(plan.targets.slice(0,3).map(x => x.isHero), [true, false, false]);
});
test('fails closed on count drift, missing hero, duplicate images or empty asset', () => {
  const { products, images } = sampleCms();
  assert.throws(() => createTargetPlan(products, images.slice(1)), /Expected 108|Hero image is not linked/);
  assert.throws(() => createTargetPlan(products.slice(1), images), /Product missing/);
  assert.throws(() => createTargetPlan(products, images.concat(images[0])), /Duplicated Images CMS item/);
  assert.throws(() => createTargetPlan(products, images.map(i => ({ ...i, fieldData: { ...i.fieldData, image: null } }))), /Missing image asset/);
});
test('unrelated CMS fields cannot be overwritten', () => {
  const original = {fieldData:{name:'X',product:id(1),color:id(9),'sort-order':1,image:{fileId:'a'}}};
  assert.doesNotThrow(() => assertOtherFieldsUnchanged(original,{fieldData:{...original.fieldData,image:{fileId:'b'}}}));
  assert.throws(() => assertOtherFieldsUnchanged(original,{fieldData:{...original.fieldData,color:id(10)}}),/changed/);
});
test('aggregate cost sums token categories and marks missing prices as incomplete', () => {
  const r = {source:'openai-images-edits',tokens:{input:120,textInput:20,imageInput:100,imageOutput:200,total:320},
    costsUsd:{textInput:.0001,imageInput:.0008,imageOutput:.006},estimatedTotalUsd:.0069};
  const known=aggregateUsage([r,r]);
  assert.equal(known.apiCalls,2);
  assert.equal(known.tokens.total,640);
  assert.ok(Math.abs(known.cost.pricedTotal-.0138)<1e-12);
  assert.equal(known.completeCost,true);
  const unknown=aggregateUsage([r,{...r,estimatedTotalUsd:null,costsUsd:null}]);
  assert.equal(unknown.unpricedCalls,1);
  assert.equal(unknown.completeCost,false);
  assert.ok(Math.abs(unknown.cost.pricedTotal-.0069)<1e-12);
});
test('3:4 restoration preserves the complete protected rectangle', async () => {
  const inset=await sharp({create:{width:744,height:992,channels:3,background:'#ececec'}}).png().toBuffer();
  const original=await sharp({create:{width:W,height:H,channels:3,background:'#fff'}})
    .composite([{input:inset,left:228,top:304}]).png().toBuffer();
  const normalized=await normalize(original);
  const info=await inspect(normalized);
  assert.equal(info.hex,'#ececec');
  assert.equal(info.uniform,true);
  const restored=await solid(normalized,info);
  const before=await sharp(normalized).extract(info.rect).removeAlpha().raw().toBuffer();
  const after=await sharp(restored).extract(info.rect).removeAlpha().raw().toBuffer();
  assert.ok(after.equals(before));
  const meta=await sharp(await encode(restored)).metadata();
  assert.equal(meta.width,W);
  assert.equal(meta.height,H);
  assert.equal(meta.format,'webp');
});
