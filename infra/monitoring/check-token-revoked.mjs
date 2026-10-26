import {localApi} from './zabbix-api.mjs';
try{
  await localApi()('host.get',{filter:{host:['secureops-api']},output:['hostid']});
  console.error('temporary_token_still_authorized');process.exitCode=1;
}catch(error){
  if(error instanceof Error&&error.message==='zabbix_auth_not_authorized')console.log(JSON.stringify({check:'temporary_token_revocation',result:'pass',requestRejected:true}));
  else{console.error('token_revocation_not_confirmed_values_omitted');process.exitCode=1;}
}
