import {readFile,writeFile,mkdir,access} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {config} from 'dotenv';
import sharp from 'sharp';
import {normalize,inspect,mask,restore,solid,encode,W,H} from './image.mjs';
import {target,getItems,edit,hash,upload,stageImage,wf} from './api.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
config({path:resolve(root,'.env'),quiet:true});
config({path:resolve(root,'../../.env'),quiet:true});
function args() {
  const [command,...a]=process.argv.slice(2), opts={};
  if(!['preview','apply','rollback'].includes(command))throw Error('Use preview, apply, or rollback');
  for(let i=0;i<a.length;i+=2){
    if(!a[i]?.startsWith('--')||!a[i+1])throw Error('Malformed option '+a[i]);
    opts[a[i].slice(2)]=a[i+1];
  }
  return {command,opts};
}
const {command,opts}=args();
const dir=resolve(root,opts.out||'output/mens-derby');
const path=(x)=>join(dir,x);
async function save(x,obj){await writeFile(path(x),JSON.stringify(obj,null,2)+'\n')}
async function manifest() {
  const m=JSON.parse(await readFile(path('manifest.json'),'utf8'));
  if(m.target?.item!==target.item||m.source?.image?.fieldData?.image?.fileId!==target.file)
    throw Error('Manifest not for verified original Men’s Derby image');
  if(opts.confirm!==target.item)throw Error('Required: --confirm '+target.item);
  return m;
}
function unchanged(current,original) {
  const fields=structuredClone(current.fieldData), expected=structuredClone(original.fieldData);
  delete fields.image;delete expected.image;
  if(JSON.stringify(fields)!==JSON.stringify(expected))throw Error('Unrelated Images CMS fields changed; refusing');
}
async function preview() {
  const engine=opts.engine||'ai';
  if(!['ai','solid'].includes(engine))throw Error('--engine must be ai or solid');
  if(await access(path('manifest.json')).then(()=>true,()=>false))
    throw Error('Preview directory already has a manifest. Supply --out for a fresh preview.');
  const {image,product}=await getItems();
  if(image.fieldData.image.fileId!==target.file)throw Error('Source asset was replaced; refusing');
  const u=new URL(image.fieldData.image.url);
  if(u.hostname!=='cdn.prod.website-files.com')throw Error('Unexpected image hostname');
  const r=await fetch(u,{signal:AbortSignal.timeout(60000)});
  if(!r.ok)throw Error('Failed source download: '+r.status);
  const bytes=Buffer.from(await r.arrayBuffer());
  if(bytes.length>50*1024*1024)throw Error('Source too large');
  const png=await normalize(bytes), info=await inspect(png), alphaMask=await mask(info.rect);
  console.log('Detected photograph',info.rect,'background',info.hex);
  const model=opts.model||process.env.OPENAI_IMAGE_MODEL||'gpt-image-2.5-sunburst';
  const ai=engine==='ai'?await edit(png,alphaMask,info,model):null;
  const restored=ai?await restore(png,ai,info):await solid(png,info);
  const webp=await encode(restored);
  const beforeAfter=await sharp({create:{width:W*2,height:H,channels:3,background:'#fff'}})
    .composite([{input:png,left:0,top:0},{input:restored,left:W,top:0}])
    .jpeg({quality:85}).toBuffer();
  await mkdir(dir,{recursive:true});
  for(const [name,value] of Object.entries({'original.webp':bytes,'normalized.png':png,
    'mask.png':alphaMask,'restored.png':restored,'preview.webp':webp,
    'before-after.jpg':beforeAfter,...(ai?{'ai-output.png':ai}:{})}))
    await writeFile(path(name),value);
  await save('manifest.json',{target,engine,model:engine==='ai'?model:null,info,
    source:{image,product},previewHash:hash(webp),applied:false});
  console.log('Preview ready:',path('preview.webp'),'\nComparison:',path('before-after.jpg'));
  console.log('No Webflow writes made. Review the image before using apply.');
}
async function apply() {
  const m=await manifest();
  if(m.applied)throw Error('This preview is already applied');
  const webp=await readFile(path('preview.webp'));
  if(hash(webp)!==m.previewHash)throw Error('Preview file has changed');
  const {image,product}=await getItems();
  if(image.fieldData.image.fileId!==target.file||
    image.lastUpdated!==m.source.image.lastUpdated||
    product.fieldData['hero-image']!==m.source.product.fieldData['hero-image'])
    throw Error('Source CMS has changed since preview');
  unchanged(image,m.source.image);
  if(!m.uploaded){
    m.uploaded=await upload(webp);
    await save('manifest.json',m); // resumable if PATCH fails
  }
  const verifyBefore=(await getItems()).image;
  if(verifyBefore.lastUpdated!==m.source.image.lastUpdated)throw Error('CMS changed during upload');
  const next={...m.uploaded,alt:m.source.image.fieldData.image.alt??null};
  await stageImage(next);
  const current=(await getItems()).image;
  if(current.fieldData.image.fileId!==next.fileId||current.fieldData.image.url!==next.url)
    throw Error('Staged image did not match uploaded asset');
  unchanged(current,m.source.image);
  m.applied=true;await save('manifest.json',m);
  console.log('Staged Images CMS image updated. No publishing performed.');
}
async function rollback() {
  const m=await manifest();
  if(!m.applied||m.rolledBack)throw Error('No active applied change to roll back');
  const {image}=await getItems();
  if(image.fieldData.image.fileId!==m.uploaded.fileId)throw Error('CMS no longer points to generated asset');
  unchanged(image,m.source.image);
  await stageImage(m.source.image.fieldData.image);
  const restored=(await getItems()).image;
  if(restored.fieldData.image.fileId!==target.file)throw Error('Rollback verification failed');
  m.rolledBack=true;await save('manifest.json',m);
  console.log('Original image field restored in staging; no publish performed.');
}
try {
  if(command==='preview')await preview();
  if(command==='apply')await apply();
  if(command==='rollback')await rollback();
}catch(e){console.error('ERROR:',e.message);process.exitCode=1}
