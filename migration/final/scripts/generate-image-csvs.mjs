import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FINAL_DIR = path.resolve(HERE, '..');
const ROOT = path.resolve(FINAL_DIR, '../..');
const SOURCE = path.join(FINAL_DIR, 'source', 'final-image-products.json');
const OUTPUT = path.join(FINAL_DIR, 'output');
const ASSET_BASE_URL = 'https://notanother-nz.github.io/total-image-product-assets';

const OVERRIDES = {
  "2151": "2151_SILVERTECH_POLO_LADIES",
  "2151CC": "2151_EZYLIN_TUNIC",
  "BRIGHT-YARN": "BRIGHT_YARN_A_BRIGHT_FUTURE_ESSENCE_POLO_SHIRT",
  "BRIGHT-YARN-UNISEX": "BRIGHT_YARN_UNISEX_A_BRIGHT_FUTURE_ESSENCE_POLO_SHIRT",
  "FAMILY-YARN-UNISEX": "FAMILY_YARN_UNISEX_FAMILY_BLACK_BAMBOO_(SIMPSON)_POLO_SHIRT",
  "FUTURE-YARN-UNISEX": "FUTURE_YARN_UNISEX_FUTURE_DREAMING_ESSENCE_POLO_SHIRT",
  "GUIDING-YARN-UNISEX": "GUIDING_YARN_UNISEX_GUIDING_LIGHT_BLACK_BAMBOO_(SIMPSON)_POLO_SHIRT",
  "KNOWLEDGE-YARN-UNISEX": "KNOWLEDGE_YARN_UNISEX_KNOWLEDGE_HOLDERS_BLACK_BAMBOO_(SIMPSON)_POLO_SHIRT",
  "LEGACY-YARN-UNISEX": "LEGACY_YARN_UNISEX_LEGACY_POLO_SHIRT",
  "MOUNTAINS-YARN-UNISEX": "MOUNTAINS_YARN_UNISEX_MOUNTAINS_WHITE_BAMBOO_(SIMPSON)_POLO_SHIRT",
  "P105LS": "P105MS_LADIES_CITY_POLO",
  "P105MS": "P105MS_MENS_CITY_POLO"
};

const clean = v => String(v ?? '').replace(/\s+/g, ' ').trim();
const slugify = v => clean(v).toLowerCase().replace(/&/g, ' and ').replace(/[’']/g, '')
  .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').replace(/-+/g, '-').slice(0, 240);
const normSku = v => clean(v).toUpperCase().replace(/[^A-Z0-9]/g, '');
const normColour = v => clean(v).toUpperCase().replace(/COLOU?RED/g, 'COLORED').replace(/[^A-Z0-9]/g, '');
const csvEscape = v => /[",\r\n]/.test(String(v ?? '')) ? '"' + String(v ?? '').replace(/"/g, '""') + '"' : String(v ?? '');
const csv = (rows, headers) => [headers.join(','), ...rows.map(r => headers.map(h => csvEscape(r[h])).join(','))].join('\r\n') + '\r\n';

function walk(dir) {
  const out=[]; const stack=[dir];
  while(stack.length){
    const d=stack.pop();
    for(const ent of fs.readdirSync(d,{withFileTypes:true})){
      const p=path.join(d,ent.name);
      if(ent.isDirectory()) stack.push(p); else out.push(p);
    }
  }
  return out;
}
function viewPriority(filename) {
  const n=filename.toUpperCase();
  if(/HERO[_ -]?FRONT|FRONT[_ -]?HERO/.test(n)) return 1;
  if(/HERO[_ -]?BACK|BACK[_ -]?HERO/.test(n)) return 2;
  if(/HERO[_ -]?(CLOSEUP|CLOSE_UP)|CLOSEUP[_ -]?HERO/.test(n)) return 3;
  if(/HERO[_ -]?SIDE|SIDE[_ -]?HERO/.test(n)) return 4;
  if(/(^|[^A-Z])FRONT([^A-Z]|$)/.test(n)) return 6;
  if(/(^|[^A-Z])BACK([^A-Z]|$)/.test(n)) return 7;
  if(/(^|[^A-Z])SIDE([^A-Z]|$)/.test(n)) return 8;
  return 9;
}
function findColour(filename, colours) {
  const nf=normColour(filename);
  const candidates=colours.map(c=>({name:c,n:normColour(c)})).filter(x=>x.n&&nf.includes(x.n)).sort((a,b)=>b.n.length-a.n.length);
  if(candidates.length) return {colour:candidates[0].name,reason:'filename'};
  if(colours.length===1) return {colour:colours[0],reason:'single-product-colour'};
  return {colour:'',reason:'unmatched'};
}

const products=JSON.parse(fs.readFileSync(SOURCE,'utf8'));
const assetsDir=path.join(ROOT,'assets');
if(!fs.existsSync(assetsDir)) throw new Error('Run from a checkout containing the approved assets/ directory.');
const folders=fs.readdirSync(assetsDir,{withFileTypes:true}).filter(x=>x.isDirectory()).map(x=>x.name);
if(folders.length!==422) throw new Error(`Expected 422 asset folders, got ${folders.length}`);

const prefixMap=new Map();
for(const f of folders){ const k=normSku(f.split('_')[0]); if(!prefixMap.has(k)) prefixMap.set(k,[]); prefixMap.get(k).push(f); }
const folderBySku=new Map();
const folderErrors=[];
for(const p of products){
  const matches=prefixMap.get(normSku(p.sku))||[];
  const folder=OVERRIDES[p.sku] || (matches.length===1?matches[0]:null);
  if(!folder || !folders.includes(folder)) folderErrors.push({sku:p.sku,matches,override:OVERRIDES[p.sku]||''});
  else folderBySku.set(p.sku,folder);
}
if(folderErrors.length) throw new Error(JSON.stringify(folderErrors,null,2));

const rows=[]; const manifest=[]; const heroMap={};
for(const p of products){
  const folder=folderBySku.get(p.sku);
  const files=walk(path.join(assetsDir,folder,'webp')).filter(f=>f.toLowerCase().endsWith('.webp')).map(f=>{
    const rel=path.relative(ROOT,f).split(path.sep).join('/');
    const kind=rel.includes('/webp/model/')?'model':'product';
    const filename=path.basename(f);
    const colourMatch=findColour(filename,p.website_colours||[]);
    return {rel,kind,filename,colourMatch,priority:(kind==='model'?0:100)+viewPriority(filename)};
  }).sort((a,b)=>a.priority-b.priority||a.filename.localeCompare(b.filename));

  let order=1; const per=[];
  for(const e of files){
    const colour=e.colourMatch.colour;
    const imageSlug=slugify(`${p.sku}-${e.filename.replace(/\.webp$/i,'')}`);
    const url=`${ASSET_BASE_URL}/${e.rel.split('/').map(encodeURIComponent).join('/')}`;
    rows.push({'Image Name':`${p.name} — ${e.filename}`.slice(0,256),'Slug':imageSlug,'Image':url,'Product':p.slug,'Color':colour?slugify(colour):'','Sort Order':order});
    const m={sku:p.sku,product_slug:p.slug,folder,path:e.rel,filename:e.filename,kind:e.kind,colour,colour_match:e.colourMatch.reason,sort_order:order,image_slug:imageSlug,url,hero_candidate:e.kind==='model'&&e.priority===1};
    manifest.push(m); per.push(m); order++;
  }
  const candidates=per.filter(x=>x.hero_candidate).sort((a,b)=>a.sort_order-b.sort_order||a.filename.localeCompare(b.filename));
  const chosen=candidates[0]||per[0];
  heroMap[p.sku]={product_slug:p.slug,image_slug:chosen.image_slug,path:chosen.path,selection:candidates.length?'hero-front':'first-image-fallback'};
}
if(rows.length!==4464) throw new Error(`Expected 4464 images, got ${rows.length}`);
fs.mkdirSync(OUTPUT,{recursive:true});
const headers=['Image Name','Slug','Image','Product','Color','Sort Order'];
for(let i=0;i<rows.length;i+=800){
  const n=String(i/800+1).padStart(3,'0');
  fs.writeFileSync(path.join(OUTPUT,`05-images-${n}.csv`),csv(rows.slice(i,i+800),headers));
}
fs.writeFileSync(path.join(OUTPUT,'image-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
fs.writeFileSync(path.join(OUTPUT,'hero-image-map.json'),JSON.stringify(heroMap,null,2)+'\n');
fs.writeFileSync(path.join(OUTPUT,'image-validation-report.json'),JSON.stringify({
  products:products.length,asset_folders:folders.length,images:rows.length,
  model_images:manifest.filter(x=>x.kind==='model').length,
  product_images:manifest.filter(x=>x.kind==='product').length,
  images_without_colour_reference:manifest.filter(x=>!x.colour).length,
  hero_images:Object.keys(heroMap).length,status:'ready'
},null,2)+'\n');
console.log('Generated',rows.length,'image rows for',products.length,'products.');
