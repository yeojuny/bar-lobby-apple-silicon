import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
function inventory(app){
 const rows={};function visit(dir,prefix=''){for(const name of fs.readdirSync(dir).sort()){const relative=prefix?prefix+'/'+name:name,file=path.join(dir,name),st=fs.lstatSync(file),mode=st.mode&0o777;
 if(st.isDirectory()){rows[relative]={type:'directory',mode};visit(file,relative);}else if(st.isSymbolicLink())rows[relative]={type:'link',mode,target:fs.readlinkSync(file)};else if(st.isFile())rows[relative]={type:'file',mode,size:st.size,sha256:hash(file)};else throw Error('Special app input');}}visit(app);return rows;
}
console.log(crypto.createHash('sha256').update(JSON.stringify(inventory(process.argv[2]))).digest('hex'));
