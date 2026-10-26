import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import {localApi,waitFor} from './zabbix-api.mjs';
const mode=process.argv[2];assert.ok(['availability','full'].includes(mode));
try{
  const api=localApi();const ids=JSON.parse(readFileSync('/state/security-zabbix-created.json','utf8'));
  if(mode==='availability'){
    const triggers=await api('trigger.get',{triggerids:ids.triggerids,output:['value','status']});
    assert.equal(triggers.length,2);assert.ok(triggers.every(t=>t.value==='0'),'active_problem_do_not_hide');
    await api('trigger.update',ids.triggerids.map(triggerid=>({triggerid,status:1})));
    await api('item.update',ids.itemids.map(itemid=>({itemid,status:1})));
  }else{
    await api('item.update',ids.itemids.map(itemid=>({itemid,status:0})));
    await api('trigger.update',ids.triggerids.map(triggerid=>({triggerid,status:0})));
    const since=Math.floor(Date.now()/1000);
    await waitFor(()=>api('history.get',{history:3,itemids:[ids.itemids[2]],time_from:since,output:['clock','value']}),samples=>samples.filter(s=>s.value==='1').length>=2,150,'mode_full_fresh_quality');
  }
  const items=await api('item.get',{itemids:ids.itemids,output:['status','key_']});
  const triggers=await api('trigger.get',{triggerids:ids.triggerids,output:['status','description']});
  const expected=mode==='availability'?'1':'0';assert.ok(items.length===3&&items.every(i=>i.status===expected));assert.ok(triggers.length===2&&triggers.every(t=>t.status===expected));
  const scenarios=await api('httptest.get',{hostids:[ids.hostid],output:['name','status']});assert.ok(scenarios.some(s=>s.name==='api-health'&&s.status==='0'));
  console.log(JSON.stringify({mode,result:'pass',securityItems:3,securityTriggers:2,availabilityUnchanged:true,noHistoryDeleted:true}));
}catch(error){console.error(error instanceof Error&&/^(timeout_[a-z0-9_]+|zabbix_[a-z._0-9-]+)$/.test(error.message)?error.message:'security_mode_failed_preserve_state');process.exitCode=1;}
