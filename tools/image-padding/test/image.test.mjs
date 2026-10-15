import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import {normalize,inspect,mask,solid,restore,encode,W,H} from '../src/image.mjs';
import {target} from '../src/api.mjs';
const rect={left:200,top:250,width:800,height:1100};
async function sample(){
 const inner=await sharp({create:{width:rect.width,height:rect.height,channels:3,background:'#ececec'}}).png().toBuffer();
 return sharp({create:{width:W,height:H,channels:3,background:'#ffffff'}})
  .composite([{input:inner,left:rect.left,top:rect.top}]).png().toBuffer();
}
test('detect uniform grey rectangular centre and white padding',async()=>{
 const info=await inspect(await sample());
 assert.deepEqual(info.rect,rect);
 assert.equal(info.hex,'#ececec');
 assert.equal(info.uniform,true);
});
test('mask allows only external editing',async()=>{
 const a=await mask(rect);
 const raw=await sharp(a).ensureAlpha().raw().toBuffer();
 assert.equal(raw[3],0);
 assert.equal(raw[(500*W+500)*4+3],255);
});
test('solid fill preserves rectangle and produces 1200x1600 WebP',async()=>{
 const source=await sample(),i=await inspect(source),o=await solid(source,i);
 const a=await sharp(source).extract(rect).raw().toBuffer();
 const b=await sharp(o).extract(rect).raw().toBuffer();
 assert.ok(a.equals(b));
 const m=await sharp(await encode(o)).metadata();
 assert.equal(m.width,W);assert.equal(m.height,H);assert.equal(m.format,'webp');
});
test('AI compositing discards modifications to protected photograph',async()=>{
 const source=await sample(),info=await inspect(source);
 const magenta=await sharp({create:{width:W,height:H,channels:3,background:'#ff00ff'}}).png().toBuffer();
 const result=await restore(source,magenta,info);
 const a=await sharp(source).extract(rect).raw().toBuffer();
 const b=await sharp(result).extract(rect).raw().toBuffer();
 assert.ok(a.equals(b));
});
test('tool targets only verified Derby image',()=>{
 assert.equal(target.item,'6ac69399d70193b11f7af706');
 assert.equal(target.file,'6ac69399d70193b11f7af702');
});
