import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { createHash } from 'node:crypto';
import { validateCmsImageUrl, verifyStagedAssetBytes, preserveCanonicalAsset } from '../src/staged-asset.mjs';

const target = {
  slug:'allegra-750ml-bottle',
  productId:'6ac6313213a31b3b2ff91062',
  imageItemId:'6ac6952a500eb3a1e726487b',
  originalFileId:'6ac6952a500eb3a1e7264870'
};
const receipt = {
  fileId:'6ad0b1d5bdd5db44f7a5bd57',
  url:'https://cdn.prod.website-files.com/6a5cf9aea7826c08d8c44b43/6ad0b1d5bdd5db44f7a5bd57_allegra-750ml-bottle-6ac6952a500eb3a1e726487b-padding-restored.webp'
};
const canonical = {
  fileId:'6ad0b1d8bd3924a839cd6974',
  url:'https://cdn.prod.website-files.com/6a5cf9aea7826c08d8c44b43/6ad0b1d8bd3924a839cd6974_6ad0b1d5bdd5db44f7a5bd57_allegra-750ml-bottle-6ac6952a500eb3a1e726487b-padding-restored.webp',
  alt:null
};
async function sampleWebp(){
  return sharp({create:{width:1200,height:1600,channels:3,background:'#ececec'}})
    .webp({quality:88}).toBuffer();
}
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const mockFetch=bytes=>async () => ({
  ok:true,
  headers:{get:()=>String(bytes.length)},
  arrayBuffer:async()=>Uint8Array.from(bytes).buffer
});

test('accepts Webflow canonical CMS copy of uploaded asset, even when IDs and URLs changed',async()=>{
  const webp=await sampleWebp();
  assert.notEqual(canonical.fileId,receipt.fileId);
  assert.notEqual(canonical.url,receipt.url);
  assert.equal(validateCmsImageUrl(target,canonical),canonical.url);
  const actual=await verifyStagedAssetBytes(target,canonical,sha(webp),mockFetch(webp));
  assert.deepEqual(actual,canonical);
  const state={uploaded:{...receipt},status:'ready'};
  preserveCanonicalAsset(state,actual);
  assert.deepEqual(state.assetUpload,receipt);
  assert.deepEqual(state.uploaded,canonical);
  assert.equal(state.status,'applied');
});

test('rejects same filename with different content; no false success',async()=>{
  const approved=await sampleWebp();
  const other=await sharp({create:{width:1200,height:1600,channels:3,background:'#ffffff'}}).webp().toBuffer();
  await assert.rejects(verifyStagedAssetBytes(target,canonical,sha(approved),mockFetch(other)),/do not match/);
});

test('rejects a staged URL for a different product, even if bytes match',async()=>{
  const approved=await sampleWebp();
  const wrong={...canonical,url:canonical.url.replace('allegra-750ml-bottle','wrong-product')};
  await assert.rejects(verifyStagedAssetBytes(target,wrong,sha(approved),mockFetch(approved)),/filename does not match/);
});

test('rejects original image file ID, wrong URL origin, and wrong image dimensions',async()=>{
  const approved=await sampleWebp();
  await assert.rejects(verifyStagedAssetBytes(target,{...canonical,fileId:target.originalFileId},sha(approved),mockFetch(approved)),/still points at the original/);
  assert.throws(()=>validateCmsImageUrl(target,{...canonical,url:canonical.url.replace('cdn.prod.website-files.com','fake.example')}),/expected Total Image asset CDN/);
  const other=await sharp({create:{width:600,height:800,channels:3,background:'#ececec'}}).webp().toBuffer();
  await assert.rejects(verifyStagedAssetBytes(target,canonical,sha(other),mockFetch(other)),/wrong dimensions/);
});
