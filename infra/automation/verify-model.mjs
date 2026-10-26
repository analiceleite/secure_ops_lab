// Verifica bytes locais, nao confia somente no alias mutavel da biblioteca.
import { readFileSync, existsSync, createReadStream, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
export async function verifyModel(directory,lock){
    const path=directory+'/'+lock.manifestPath;
    const bytes=readFileSync(path);
    const manifest=JSON.parse(bytes);
    // Ollama 0.40 acrescenta ao manifesto local um layer com o manifesto original.
    // A ancora continua sendo o SHA fixado do registro, nunca o wrapper/alias local.
    const originalLayer=manifest.layers.find(l=>l.mediaType==='application/vnd.docker.distribution.manifest.v2+json');
    if(originalLayer){
      assert.equal(originalLayer.digest,'sha256:'+lock.manifestSha256);
      const originalBytes=readFileSync(directory+'/models/blobs/'+originalLayer.digest.replace(':','-'));
      assert.equal(originalBytes.length,originalLayer.size);
      assert.equal(createHash('sha256').update(originalBytes).digest('hex'),lock.manifestSha256);
      const original=JSON.parse(originalBytes);
      assert.deepEqual(manifest,{...original,layers:[...original.layers,originalLayer]});
    }else{
      assert.equal(createHash('sha256').update(bytes).digest('hex'),lock.manifestSha256);
    }
    const model=manifest.layers.find(l=>l.mediaType==='application/vnd.ollama.image.model');
    assert.equal(model.digest,'sha256:'+lock.modelBlobSha256);assert.equal(model.size,lock.modelBytes);
    for(const blob of [manifest.config,...manifest.layers]){
      assert.match(blob.digest,/^sha256:[a-f0-9]{64}$/);
      const file=directory+'/models/blobs/'+blob.digest.replace(':','-');assert.equal(statSync(file).size,blob.size);
      const hash=createHash('sha256');for await(const chunk of createReadStream(file))hash.update(chunk);
      assert.equal(hash.digest('hex'),blob.digest.slice(7));
    }
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const lock=JSON.parse(readFileSync(new URL('./model-lock.json',import.meta.url),'utf8'));
 if(!existsSync('/model/'+lock.manifestPath)){
   console.log(JSON.stringify({check:'model_integrity',state:'not_installed'}));process.exitCode=2;
 }else{
   try{
     await verifyModel('/model',lock);
     console.log(JSON.stringify({check:'model_integrity',result:'pass',model:lock.model,manifestSha256:lock.manifestSha256,modelBytes:lock.modelBytes,allBlobsVerified:true}));
   }catch{console.error('model_integrity_failed_preserve_volume');process.exitCode=1;}
 }
}
