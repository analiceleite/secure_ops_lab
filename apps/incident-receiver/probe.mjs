// Liveness apenas: não afirma que migração/allowlist/integração foram instaladas.
try{
 const r=await fetch('http://127.0.0.1:3000/health',{signal:AbortSignal.timeout(2000)});
 process.exit(r.status===200&&(await r.json()).result==='alive'?0:1);
}catch{process.exit(1);}
