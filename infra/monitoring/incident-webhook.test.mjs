import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source=readFileSync(new URL('./incident-webhook.js',import.meta.url),'utf8');
const key='a'.repeat(64);
function invoke(params,{status=200,response='{"result":"applied"}'}={}){
  const calls=[];
  class HttpRequest {
    addHeader(v){calls.push(['header',v]);}
    post(url,body){calls.push(['post',url,JSON.parse(body)]);return response;}
    getStatus(){return status;}
  }
  const context={value:JSON.stringify(params),HttpRequest,JSON};
  const output=vm.runInNewContext('(function(){'+source+'})()',context);
  return {output,calls};
}
const base={event_type:'problem',event_id:'101',problem_event_id:'101',trigger_id:'25231',host:'secureops-api',occurred_at:'1793038942',webhook_key:key};

test('constrói envelope mínimo e mapeia os quatro triggers',()=>{
  for(const [trigger_id,condition,category] of [
    ['25229','api-http','availability'],['25230','api-http-nodata','collection'],
    ['25231','auth-threshold','authentication'],['25232','auth-collection','collection']]){
    const {output,calls}=invoke({...base,trigger_id});
    assert.equal(output,'OK');
    const body=calls.find(c=>c[0]==='post')[2];
    assert.deepEqual(Object.keys(body).sort(),['category','condition','contract_version','event_id','event_type','host','occurred_at','problem_event_id','service','source','source_instance','trigger_id'].sort());
    assert.equal(body.condition,condition);assert.equal(body.category,category);
    assert.equal(calls.find(c=>c[0]==='post')[1],'http://incident-receiver:3000/v1/events');
  }
});

test('correlaciona recuperação com o evento problema original',()=>{
  const {calls}=invoke({...base,event_type:'recovery',event_id:'102',problem_event_id:'101'});
  const body=calls.find(c=>c[0]==='post')[2];
  assert.equal(body.event_id,'102');assert.equal(body.problem_event_id,'101');assert.equal(body.event_type,'recovery');
});

test('rejeita macros não resolvidas, trigger desconhecido e IDs inconsistentes antes do POST',()=>{
  for(const params of [
    {...base,event_id:'{EVENT.ID}'},{...base,trigger_id:'99999'},
    {...base,event_type:'recovery',event_id:'101'}, {...base,host:'other-host'},
    {...base,occurred_at:'{{EVENT.TIME}.fmttime(%s)}'}
  ]){
    const calls=[];
    class HttpRequest{addHeader(){}post(){calls.push('post');return '{}';}getStatus(){return 200;}}
    assert.throws(()=>vm.runInNewContext('(function(){'+source+'})()', {value:JSON.stringify(params),HttpRequest,JSON}));
    assert.equal(calls.length,0);
  }
});

test('somente status e resultados positivos reconhecidos são aceitos',()=>{
  assert.throws(()=>invoke(base,{status:503}));
  assert.throws(()=>invoke(base,{response:'{"result":"invalid"}'}));
  assert.throws(()=>invoke(base,{response:'not-json'}));
});
