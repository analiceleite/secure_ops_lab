import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {localApi} from './zabbix-api.mjs';
import {KEYS,masterItem,dependentItems} from './security-config.mjs';
try{
 const api=localApi(),ids=JSON.parse(readFileSync('/state/security-zabbix-created.json','utf8'));
 assert.equal(await api('apiinfo.version'),'7.0.32');
 const items=await api('item.get',{itemids:ids.itemids,selectPreprocessing:'extend',output:['itemid','key_','type','value_type','status','delay','history','trends','master_itemid','url','timeout','follow_redirects','status_codes','headers','state','lastclock','lastvalue']});assert.equal(items.length,3);
 const raw=items.find(i=>i.key_===KEYS.raw),count=items.find(i=>i.key_===KEYS.count),quality=items.find(i=>i.key_===KEYS.quality);
 const expected=masterItem(ids.hostid);const deps=dependentItems(ids.hostid,raw.itemid);
 for(const field of ['url','timeout','delay','history','status_codes'])assert.equal(raw[field],expected[field]);
 assert.equal(raw.type,'19');assert.equal(raw.value_type,'4');assert.equal(raw.follow_redirects,'0');assert.deepEqual(raw.headers,expected.headers);
 assert.equal(raw.preprocessing[0].params,expected.preprocessing[0].params);
 assert.equal(count.type,'18');assert.equal(quality.type,'18');assert.equal(count.master_itemid,raw.itemid);assert.equal(quality.master_itemid,raw.itemid);
 assert.equal(count.preprocessing[0].params,deps[0].preprocessing[0].params);assert.equal(quality.preprocessing[0].params,'$.collection_ok');
 assert.ok(items.every(i=>i.status==='0'&&i.state==='0'&&Number(i.lastclock)>Date.now()/1000-60));
 assert.equal(quality.lastvalue,'1');assert.equal(count.lastvalue,'0');
 const macros=await api('usermacro.get',{hostids:[ids.hostid],filter:{macro:'{$SECUREOPS_METRICS_KEY}'},output:['macro','type']});assert.equal(macros.length,1);assert.equal(macros[0].type,'1');
 const triggers=await api('trigger.get',{triggerids:ids.triggerids,output:['status','value','state','type','manual_close','recovery_mode']});assert.equal(triggers.length,2);assert.ok(triggers.every(t=>t.status==='0'&&t.value==='0'&&t.state==='0'&&t.type==='0'&&t.manual_close==='0'));
 const dashboard=await api('dashboard.get',{filter:{name:['SecureOps Lab']},output:['dashboardid','private'],selectPages:'extend',selectUsers:'extend',selectUserGroups:'extend'});assert.equal(dashboard.length,1);assert.equal(dashboard[0].private,'1');assert.equal(dashboard[0].users.length,0);assert.equal(dashboard[0].userGroups.length,0);
 const widgets=dashboard[0].pages.flatMap(p=>p.widgets);assert.equal(widgets.length,4);
 for(const id of [count.itemid,quality.itemid])assert.ok(widgets.some(w=>w.type==='item'&&w.fields.some(f=>f.name==='itemid.0'&&f.value===id)));
 const cycles=['1','2'].map(n=>JSON.parse(readFileSync(`/state/security-cycle-${n}.json`,'utf8')));
 assert.ok(cycles.every(c=>c.isolatedErrorNoAlert&&c.threeSamplesOneProblem&&c.recoveryEvent&&c.noEventsDeleted));
 const eventids=cycles.flatMap(c=>[c.problemEvent,c.recoveryEvent]);const events=await api('event.get',{eventids,output:['eventid','value','clock']});assert.equal(events.length,4);
 console.log(JSON.stringify({result:'pass',version:'7.0.32',securityItems:3,validCount:0,validQuality:1,secretMacroType:1,singleTriggersNormal:2,dashboardPrivate:true,dashboardShares:0,dashboardWidgets:4,bothSecurityCyclesPreserved:true,problemRecoveryEvents:eventids,headersContainOnlyMacroReference:true}));
}catch(error){console.error(error instanceof Error&&/^zabbix_[a-z._0-9-]+$/.test(error.message)?error.message:'final_monitoring_check_failed_values_omitted');process.exitCode=1;}
