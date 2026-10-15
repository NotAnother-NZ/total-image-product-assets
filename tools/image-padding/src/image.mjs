import sharp from 'sharp';
export const W = 1200, H = 1600;
export async function normalize(bytes) {
  return sharp(bytes).rotate().flatten({background:'#fff'}).toColourspace('srgb')
    .resize(W,H,{fit:'contain',background:'#fff'}).png().toBuffer();
}
export async function inspect(png) {
  const {data,info}=await sharp(png).removeAlpha().raw().toBuffer({resolveWithObject:true});
  if(info.width!==W||info.height!==H) throw Error('Unexpected dimensions');
  const px=(x,y)=>[...data.subarray((y*W+x)*3,(y*W+x)*3+3)];
  const diff=(a,b)=>Math.max(...a.map((n,i)=>Math.abs(n-b[i])));
  const outer=px(1,1);
  if([[W-2,1],[1,H-2],[W-2,H-2]].some(([x,y])=>diff(outer,px(x,y))>5))
    throw Error('Corners differ: padding cannot be detected safely');
  let l=W,t=H,r=-1,b=-1,n=0;
  for(let y=0;y<H;y++)for(let x=0;x<W;x++)if(diff(px(x,y),outer)>12) {
    l=Math.min(l,x);r=Math.max(r,x);t=Math.min(t,y);b=Math.max(b,y);n++;
  }
  const rect={left:l,top:t,width:r-l+1,height:b-t+1};
  if(l<16||t<16||r>W-17||b>H-17||rect.width<W*.3||rect.height<H*.3
    ||n/(rect.width*rect.height)<.97) throw Error('Unsafe interior detection');
  const sample=[[l+20,t+20],[r-20,t+20],[l+20,b-20],[r-20,b-20]].map(([x,y])=>px(x,y));
  const bg=[0,1,2].map(i=>sample.map(p=>p[i]).sort((a,b)=>a-b)[1]);
  const hex='#'+bg.map(n=>n.toString(16).padStart(2,'0')).join('');
  return {rect,bg,hex,uniform:sample.every(p=>diff(p,bg)<=8)};
}
export async function mask(rect) {
  const raw=Buffer.alloc(W*H*4,255);
  for(let y=0;y<H;y++)for(let x=0;x<W;x++)
    if(x<rect.left||x>=rect.left+rect.width||y<rect.top||y>=rect.top+rect.height)
      raw[(y*W+x)*4+3]=0;
  return sharp(raw,{raw:{width:W,height:H,channels:4}}).png().toBuffer();
}
export async function restore(original, backdrop, {rect}) {
  const m=await sharp(backdrop).metadata();
  if(m.width!==W||m.height!==H) throw Error('Model returned wrong dimensions');
  const protectedPng=await sharp(original).extract(rect).png().toBuffer();
  const png=await sharp(backdrop).flatten({background:'#fff'}).composite([
    {input:protectedPng,left:rect.left,top:rect.top}
  ]).png().toBuffer();
  const check=await sharp(png).extract(rect).removeAlpha().raw().toBuffer();
  const source=await sharp(original).extract(rect).removeAlpha().raw().toBuffer();
  if(!source.equals(check)) throw Error('Protected photo pixels changed');
  return png;
}
export async function solid(original, info) {
  if(!info.uniform) throw Error('Background is not uniform; use AI');
  const [r,g,b]=info.bg;
  const backdrop=await sharp({create:{width:W,height:H,channels:3,background:{r,g,b}}}).png().toBuffer();
  return restore(original,backdrop,info);
}
export async function encode(png) {
  const bytes=await sharp(png).webp({quality:88,effort:6}).toBuffer();
  if(bytes.length>4*1024*1024) throw Error('Image exceeds 4 MiB Webflow asset limit');
  return bytes;
}
