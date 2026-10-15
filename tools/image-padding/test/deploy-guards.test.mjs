import test from 'node:test';
import assert from 'node:assert/strict';
import {
  BELT_IDS, REPLACEMENT_COUNT, PRIMARY_CMS_LOCALE, SITE_ID, IMAGES_COLLECTION_ID,
  validateLocalBatch, classifyLiveImage, verifyStagedImage, validatePublishedIds
} from '../src/deploy-guards.mjs';

const oid=n=>n.toString(16).padStart(24,'0');
function fixture(){
  const products=Array.from({length:47},(_,i)=>({
    id:oid(100+i),slug:'sample-'+i,hero:null
  }));
  const images=[];
  for(let i=0;i<108;i++){
    const p=products[i%47], id=i===0?BELT_IDS[0]:i===1?BELT_IDS[1]:oid(2000+i);
    images.push({
      imageItemId:id,productId:p.id,slug:p.slug,originalFileId:oid(4000+i),isHero:i<47
    });
  }
  for(let i=0;i<47;i++) products[i].hero=images[i].imageItemId;
  const plan={
    version:1,siteId:SITE_ID,collections:{images:IMAGES_COLLECTION_ID},
    expectedProducts:47,expectedImages:108,targets:images
  };
  const snapshots=images.map(t=>{
    const p=products.find(x=>x.id===t.productId);
    const image={
      id:t.imageItemId,fieldData:{
        image:{fileId:t.originalFileId,url:'https://old.webp',alt:null},
        product:t.productId,color:null,'sort-order':1,name:'Old '+t.imageItemId,
        slug:'old-'+t.imageItemId
      },
      cmsLocaleId:PRIMARY_CMS_LOCALE,isArchived:false,isDraft:false,
      lastPublished:'2026-10-07T00:00:00.000Z'
    };
    return {
      target:{...t},status:BELT_IDS.includes(t.imageItemId)?'unchanged':'ready',
      previewHash:'a'.repeat(64),
      source:{image,product:{id:p.id,fieldData:{slug:p.slug,'hero-image':p.hero}}}
    };
  });
  return {plan,snapshots};
}

test('deployment plan requires 106 approved images and the two intentionally unchanged belts',()=>{
  const {plan,snapshots}=fixture();
  const result=validateLocalBatch(plan,snapshots);
  assert.equal(result.replacements.length,REPLACEMENT_COUNT);
  assert.equal(result.unchanged.length,2);
});

test('blocks missing/duplicate checkpoints, failed images, and attempts to replace belts',()=>{
  const {plan,snapshots}=fixture();
  assert.throws(()=>validateLocalBatch(plan,snapshots.slice(0,-1)),/does not match/);
  assert.throws(()=>validateLocalBatch(plan,[...snapshots.slice(0,-1),snapshots[0]]),/Duplicate checkpoint/);
  snapshots[2].status='failed';
  assert.throws(()=>validateLocalBatch(plan,snapshots),/Unapproved or missing preview/);
  snapshots[2].status='ready'; snapshots[0].status='ready';
  assert.throws(()=>validateLocalBatch(plan,snapshots),/belt must remain unchanged/);
});

test('staged image validator preserves all unrelated CMS fields and relationships',()=>{
  const {plan,snapshots}=fixture();
  const t=plan.targets[2],original=snapshots[2].source.image;
  const uploaded={fileId:oid(9000),url:'https://new.webp',alt:null};
  const staged=structuredClone(original);staged.fieldData.image=structuredClone(uploaded);
  assert.doesNotThrow(()=>verifyStagedImage(original,staged,uploaded,t));
  staged.fieldData.color=oid(50);
  assert.throws(()=>verifyStagedImage(original,staged,uploaded,t),/Unrelated staged/);
});

test('live validator accepts only the old image or the exact uploaded asset',()=>{
  const {plan,snapshots}=fixture();
  const t=plan.targets[2],original=snapshots[2].source.image;
  const uploaded={fileId:oid(9000),url:'https://new.webp',alt:null};
  assert.equal(classifyLiveImage(original,original,uploaded,t),'not-yet-live');
  const live=structuredClone(original);live.fieldData.image=structuredClone(uploaded);
  assert.equal(classifyLiveImage(original,live,uploaded,t),'already-live');
  live.fieldData.image.fileId=oid(9001);
  assert.throws(()=>classifyLiveImage(original,live,uploaded,t),/outside this migration/);
  live.fieldData.image.fileId=uploaded.fileId;
  live.fieldData.name='Externally modified';
  assert.throws(()=>classifyLiveImage(original,live,uploaded,t),/unrelated changes/);
});

test('publish response rejects partial successes even when HTTP 202 is returned',()=>{
  assert.doesNotThrow(()=>validatePublishedIds(['a','b'],{publishedItemIds:['b','a'],errors:[]}));
  assert.throws(()=>validatePublishedIds(['a','b'],{publishedItemIds:['a'],errors:['b failed']}),/partial publish/);
  assert.throws(()=>validatePublishedIds(['a','b'],{}),/Unexpected Webflow publish/);
});
