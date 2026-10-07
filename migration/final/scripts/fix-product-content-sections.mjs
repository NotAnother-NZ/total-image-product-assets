import fs from 'node:fs';

function parseCsv(text) {
  const rows=[]; let row=[],field='',i=0,quoted=false;
  while(i<text.length){
    const ch=text[i];
    if(quoted){
      if(ch==='"'){ if(text[i+1]==='"'){field+='"';i+=2;continue;} quoted=false;i++;continue; }
      field+=ch;i++;continue;
    }
    if(ch==='"'){quoted=true;i++;continue;}
    if(ch===','){row.push(field);field='';i++;continue;}
    if(ch==='\r'){i++;continue;}
    if(ch==='\n'){row.push(field);rows.push(row);row=[];field='';i++;continue;}
    field+=ch;i++;
  }
  if(field.length||row.length){row.push(field);rows.push(row);}
  const headers=rows.shift()||[];
  return {headers, rows:rows.filter(r=>r.some(v=>v!=='')).map(r=>Object.fromEntries(headers.map((h,j)=>[h,r[j]??''])))};
}
function esc(v){const s=String(v??'');return /[",\r\n]/.test(s)?'"'+s.replace(/"/g,'""')+'"':s;}
function stringifyCsv(rows,headers){return [headers.map(esc).join(','),...rows.map(r=>headers.map(h=>esc(r[h])).join(','))].join('\r\n')+'\r\n';}
function htmlEscape(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
function clean(s){return String(s??'').replace(/\s+/g,' ').trim();}
function listHtml(items){return items.length?'<ul>'+items.map(x=>'<li>'+htmlEscape(clean(x))+'</li>').join('')+'</ul>':'';}
function parseSections(text){
  const m=String(text??'').trim().match(/Key Highlights\s*([\s\S]*?)\s*Description\s*([\s\S]*?)\s*Fabric\s*&\s*Features\s*([\s\S]*)$/i);
  if(!m)return null;
  const split=s=>s.split(/\s*•\s*/).map(clean).filter(Boolean);
  return {highlights:split(m[1]),description:clean(m[2]),features:split(m[3])};
}

const input=process.argv[2], output=process.argv[3]||input?.replace(/\.csv$/i,'-fixed.csv');
if(!input) throw new Error('Usage: node fix-product-content-sections.mjs <04-products.csv> [output.csv]');
const {headers,rows}=parseCsv(fs.readFileSync(input,'utf8').replace(/^\uFEFF/,''));
let fixed=0;
for(const row of rows){
  const p=parseSections(row['Description']);
  if(!p) continue;
  row['Key Highlights']=listHtml(p.highlights);
  row['Description']=p.description;
  const fabric=(row['Fabric & Features']||'').trim();
  const features=listHtml(p.features);
  row['Fabric & Features']=fabric+features;
  fixed++;
}
fs.writeFileSync(output,stringifyCsv(rows,headers),'utf8');
console.log(JSON.stringify({input,output,rows:rows.length,fixed,unmodified:rows.length-fixed},null,2));
