import {createHash} from 'node:crypto';
import {imageEditUsageReport,printUsageReport} from './usage.mjs';
export const target={site:'6a4b7d4c587f58adf63bad93',products:'6ab0acfdb063e14a30f65e5c',
  images:'6ab2df3d42b6657bfaed2936',product:'6ac6311bb017dc1d03839b7f',
  item:'6ac69399d70193b11f7af706',file:'6ac69399d70193b11f7af702'};
async function response(r) {
  const text=await r.text();
  if(!r.ok)throw Error('HTTP '+r.status+': '+text.slice(0,500));
  return JSON.parse(text);
}
export async function wf(path,method='GET',body) {
  if(!process.env.WEBFLOW_API_TOKEN)throw Error('Missing WEBFLOW_API_TOKEN');
  return response(await fetch('https://api.webflow.com/v2'+path,{
    method,headers:{Authorization:'Bearer '+process.env.WEBFLOW_API_TOKEN,'Content-Type':'application/json'},
    ...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(60000)}));
}
export async function getItems() {
  const [image,product]=await Promise.all([
    wf('/collections/'+target.images+'/items/'+target.item),
    wf('/collections/'+target.products+'/items/'+target.product)
  ]);
  if(image.id!==target.item||product.id!==target.product||
    image.fieldData?.product!==target.product||product.fieldData?.slug!=='mens-derby'||
    product.fieldData?.['hero-image']!==target.item)
    throw Error('CMS product/hero relationship mismatch');
  return {image,product};
}
export async function edit(photo,alphaMask,info,model) {
  if(!process.env.OPENAI_API_KEY)throw Error('Missing OPENAI_API_KEY');
  if(!['gpt-image-2.5-sunburst','gpt-image-2.5-flare'].includes(model))
    throw Error('Unsupported model');
  const f=new FormData();
  f.append('model',model);f.append('size','1200x1600');f.append('quality','high');
  f.append('output_format','png');f.append('background','opaque');
  f.append('prompt','STRICT background extension only. Do not redraw or change the original product or central photograph. Edit only the transparent mask area. Extend the existing '+info.hex+' background naturally and continuously to every outer edge. Preserve size, perspective, shadows, and product pixels. No border, text, additions, or cropping.');
  f.append('image',new Blob([photo],{type:'image/png'}),'input.png');
  f.append('mask',new Blob([alphaMask],{type:'image/png'}),'mask.png');
  const json=await response(await fetch('https://api.openai.com/v1/images/edits',{
    method:'POST',headers:{Authorization:'Bearer '+process.env.OPENAI_API_KEY},body:f,
    signal:AbortSignal.timeout(300000)}));
  // Report API-provided usage immediately: processing may fail after this request is billed.
  const usage=imageEditUsageReport(json.usage,model);
  printUsageReport(usage);
  if(!json.data?.[0]?.b64_json)throw Error('OpenAI returned no image');
  return {image:Buffer.from(json.data[0].b64_json,'base64'),usage};
}
export function hash(bytes){return createHash('sha256').update(bytes).digest('hex')}
export async function upload(bytes) {
  const filename='mens-derby-padding-restored.webp';
  const m=await wf('/sites/'+target.site+'/assets','POST',{
    fileName:filename,fileHash:createHash('md5').update(bytes).digest('hex')});
  if(!m.id||!m.uploadUrl||!m.uploadDetails||!m.hostedUrl)throw Error('Incomplete asset upload response');
  const f=new FormData();
  for(const [k,v]of Object.entries(m.uploadDetails))f.append(k,String(v));
  f.append('file',new Blob([bytes],{type:'image/webp'}),filename);
  const r=await fetch(m.uploadUrl,{method:'POST',body:f,signal:AbortSignal.timeout(180000)});
  if(!r.ok)throw Error('S3 upload failed: '+r.status);
  return {fileId:m.id,url:m.hostedUrl};
}
export async function stageImage(imageField) {
  return wf('/collections/'+target.images+'/items','PATCH',{
    items:[{id:target.item,fieldData:{image:imageField}}]});
}
