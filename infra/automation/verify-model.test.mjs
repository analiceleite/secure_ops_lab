import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {verifyModel} from './verify-model.mjs';
const hash=b=>createHash('sha256').update(b).digest('hex');
function fixture(t,wrapper){
 const dir=mkdtempSync(join(tmpdir(),'secureops-model-test-'));
 t.after(()=>rmSync(dir,{recursive:true})); // somente diretorio exclusivo desta fixture.
 mkdirSync(dir+'/models/blobs',{recursive:true});
 function blob(mediaType,text){const digest='sha256:'+hash(text);writeFileSync(dir+'/models/blobs/'+digest.replace(':','-'),text);return {mediaType,digest,size:Buffer.byteLength(text)};}
 const config=blob('application/vnd.docker.container.image.v1+json','{}');
 const model=blob('application/vnd.ollama.image.model','FICTITIOUS MODEL');
 const license=blob('application/vnd.ollama.image.license','FICTITIOUS LICENSE');
 const manifest={schemaVersion:2,mediaType:'application/vnd.docker.distribution.manifest.v2+json',config,layers:[model,license]};
 const bytes=JSON.stringify(manifest),sha=hash(bytes);
 const source=blob('application/vnd.docker.distribution.manifest.v2+json',bytes);
 const local=wrapper?{...manifest,layers:[...manifest.layers,source]}:manifest;
 writeFileSync(dir+'/manifest',JSON.stringify(local));
 return {dir,local,model,license,source,lock:{manifestPath:'manifest',manifestSha256:sha,modelBlobSha256:model.digest.slice(7),modelBytes:model.size}};
}
for(const wrapper of [false,true])test(`verifica todos os blobs, wrapper=${wrapper}`,async t=>{const f=fixture(t,wrapper);await verifyModel(f.dir,f.lock);});
test('rejeita peso corrompido do mesmo tamanho',async t=>{const f=fixture(t,true);writeFileSync(f.dir+'/models/blobs/'+f.model.digest.replace(':','-'),'X'.repeat(f.model.size));await assert.rejects(verifyModel(f.dir,f.lock));});
test('rejeita layer extra no wrapper',async t=>{const f=fixture(t,true);f.local.layers.push(f.model);writeFileSync(f.dir+'/manifest',JSON.stringify(f.local));await assert.rejects(verifyModel(f.dir,f.lock));});
test('rejeita manifesto original modificado',async t=>{const f=fixture(t,true);const path=f.dir+'/models/blobs/'+f.source.digest.replace(':','-');const bytes=readFileSync(path);bytes[0]=32;writeFileSync(path,bytes);await assert.rejects(verifyModel(f.dir,f.lock));});
test('rejeita licenca corrompida, nao so os pesos',async t=>{const f=fixture(t,true);writeFileSync(f.dir+'/models/blobs/'+f.license.digest.replace(':','-'),'invalid');await assert.rejects(verifyModel(f.dir,f.lock));});
