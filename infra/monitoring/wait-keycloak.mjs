import {setTimeout as pause} from 'node:timers/promises';
const deadline=Date.now()+90000;
while(true){
  try{
    const r=await fetch('http://keycloak.localhost:8080/realms/secureops-lab/.well-known/openid-configuration',{redirect:'error',signal:AbortSignal.timeout(5000)});
    if(r.status===200&&(await r.json()).issuer==='http://keycloak.localhost:8080/realms/secureops-lab'){console.log('keycloak_discovery_ready');break;}
  }catch{}
  if(Date.now()>deadline){console.error('keycloak_readiness_timeout');process.exitCode=1;break;}
  await pause(2000);
}
