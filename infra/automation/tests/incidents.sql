\set ON_ERROR_STOP on
-- Fixture efêmera: nunca executar no banco ativo do laboratório.
CREATE TEMP TABLE test_results(name text PRIMARY KEY);
CREATE TEMP TABLE test_clock AS SELECT extract(epoch FROM now())::bigint - 300 AS epoch;
CREATE FUNCTION pg_temp.state() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'mapping',(SELECT jsonb_agg(to_jsonb(t) ORDER BY source_instance, trigger_id) FROM incident.allowed_conditions t),
    'deliveries',(SELECT jsonb_agg(to_jsonb(t) ORDER BY source_instance, event_id) FROM incident.deliveries t),
    'cycles',(SELECT jsonb_agg(to_jsonb(t) ORDER BY source_instance, problem_event_id) FROM incident.cycles t),
    'incidents',(SELECT jsonb_agg(to_jsonb(t) ORDER BY incident_id) FROM incident.incidents t),
    'jobs',(SELECT jsonb_agg(to_jsonb(t) ORDER BY incident_id, report_version) FROM incident.report_jobs t))
$$;
CREATE FUNCTION pg_temp.ok(name text, value boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'assertion_failed:%', name; END IF;
  INSERT INTO test_results VALUES (name);
END $$;
CREATE FUNCTION pg_temp.event(eid text, pid text, tid text DEFAULT '1', delta integer DEFAULT 0)
RETURNS text LANGUAGE sql AS $$
  SELECT jsonb_build_object('contract_version',1,'source','zabbix','source_instance','fixture',
    'event_type',CASE WHEN eid = pid THEN 'problem' ELSE 'recovery' END,
    'event_id',eid,'problem_event_id',pid,'trigger_id',tid,'host','secureops-api','service','secureops-api',
    'condition',CASE tid WHEN '1' THEN 'api-http' WHEN '2' THEN 'api-http-nodata'
      WHEN '3' THEN 'auth-threshold' ELSE 'auth-collection' END,
    'category',CASE tid WHEN '1' THEN 'availability' WHEN '3' THEN 'authentication' ELSE 'collection' END,
    'occurred_at',(epoch + delta)::text)::text FROM test_clock
$$;
CREATE FUNCTION pg_temp.run(name text, body text, expected text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE before_state jsonb; answer jsonb;
BEGIN
  before_state := pg_temp.state();
  answer := incident.ingest(body);
  PERFORM pg_temp.ok(name, answer = jsonb_build_object('result',expected));
  IF expected IN ('invalid','conflict','duplicate') THEN
    IF before_state IS DISTINCT FROM pg_temp.state() THEN RAISE EXCEPTION 'rejected_or_duplicate_changed_state:%',name; END IF;
  END IF;
END $$;
INSERT INTO incident.allowed_conditions VALUES
  ('fixture','1','api-http','availability'),('fixture','2','api-http-nodata','collection'),
  ('fixture','3','auth-threshold','authentication'),('fixture','4','auth-collection','collection'),
  ('concurrency','1','api-http','availability'),('first-race','1','api-http','availability'),
  ('lock-timeout','1','api-http','availability');

SELECT pg_temp.run('null',NULL,'invalid');
SELECT pg_temp.run('malformed','{','invalid');
SELECT pg_temp.run('array','[]','invalid');
SELECT pg_temp.run('json_null','null','invalid');
SELECT pg_temp.run('too_large',repeat(' ',4097),'invalid');
SELECT pg_temp.run('missing',(pg_temp.event('100','100')::jsonb - 'host')::text,'invalid');
SELECT pg_temp.run('extra',(pg_temp.event('100','100')::jsonb || '{"extra":"x"}')::text,'invalid');
SELECT pg_temp.run('duplicate_key',replace(pg_temp.event('100','100'),'{','{"host":"secureops-api",'),'invalid');
SELECT pg_temp.run('escaped_duplicate_key',replace(pg_temp.event('100','100'),'{','{"ho\u0073t":"secureops-api",'),'invalid');
SELECT pg_temp.run('null_field',(pg_temp.event('100','100')::jsonb || '{"host":null}')::text,'invalid');
SELECT pg_temp.run('numeric_id',(pg_temp.event('100','100')::jsonb || '{"event_id":100}')::text,'invalid');
SELECT pg_temp.run('decimal_version',replace(pg_temp.event('100','100'),'"contract_version": 1','"contract_version": 1.0'),'invalid');
SELECT pg_temp.run('string_version',(pg_temp.event('100','100')::jsonb || '{"contract_version":"1"}')::text,'invalid');
SELECT pg_temp.run('bad_version',(pg_temp.event('100','100')::jsonb || '{"contract_version":2}')::text,'invalid');
SELECT pg_temp.run('leading_zero',pg_temp.event('0100','0100'),'invalid');
SELECT pg_temp.run('zero',pg_temp.event('0','0'),'invalid');
SELECT pg_temp.run('id_too_long',pg_temp.event(repeat('1',21),repeat('1',21)),'invalid');
SELECT pg_temp.run('unresolved_macro',pg_temp.event('{EVENT.ID}','{EVENT.ID}'),'invalid');
SELECT pg_temp.run('unknown_trigger',pg_temp.event('100','100','999'),'invalid');
SELECT pg_temp.run('wrong_condition',(pg_temp.event('100','100')::jsonb || '{"condition":"auth-collection"}')::text,'invalid');
SELECT pg_temp.run('wrong_category',(pg_temp.event('100','100')::jsonb || '{"category":"collection"}')::text,'invalid');
SELECT pg_temp.run('wrong_source',(pg_temp.event('100','100')::jsonb || '{"source":"other"}')::text,'invalid');
SELECT pg_temp.run('unknown_instance',(pg_temp.event('100','100')::jsonb || '{"source_instance":"unknown"}')::text,'invalid');
SELECT pg_temp.run('wrong_host',(pg_temp.event('100','100')::jsonb || '{"host":"other"}')::text,'invalid');
SELECT pg_temp.run('wrong_service',(pg_temp.event('100','100')::jsonb || '{"service":"other"}')::text,'invalid');
SELECT pg_temp.run('wrong_type',(pg_temp.event('100','100')::jsonb || '{"event_type":"update"}')::text,'invalid');
SELECT pg_temp.run('problem_id_mismatch',(pg_temp.event('101','100')::jsonb || '{"event_type":"problem"}')::text,'invalid');
SELECT pg_temp.run('recovery_id_equal',(pg_temp.event('100','100')::jsonb || '{"event_type":"recovery"}')::text,'invalid');
SELECT pg_temp.run('future',pg_temp.event('100','100','1',400),'invalid');
SELECT pg_temp.run('older_than_seven_days',pg_temp.event('100','100','1',-604800),'invalid');
SELECT pg_temp.run('bad_epoch',(pg_temp.event('100','100')::jsonb || '{"occurred_at":"1e9"}')::text,'invalid');
SELECT pg_temp.run('sql_injection',pg_temp.event('1''; DROP SCHEMA incident CASCADE;--','100'),'invalid');
SELECT pg_temp.run('unicode_null',replace(pg_temp.event('100','100'),'secureops-api','\u0000'),'invalid');

SELECT pg_temp.run('open',pg_temp.event('100','100'),'applied');
SELECT pg_temp.ok('one_open', (SELECT count(*) = 1 FROM incident.incident_summary WHERE state='open'));
SELECT pg_temp.ok('no_job_while_open', NOT EXISTS (SELECT FROM incident.report_jobs));
SELECT pg_temp.run('duplicate_problem',pg_temp.event('100','100'),'duplicate');
SELECT pg_temp.run('exact_4096_bytes',repeat(' ',4096-octet_length(pg_temp.event('100','100'))) || pg_temp.event('100','100'),'duplicate');
SELECT pg_temp.run('valid_json_over_4096',repeat(' ',4097-octet_length(pg_temp.event('100','100'))) || pg_temp.event('100','100'),'invalid');
SELECT pg_temp.run('changed_content',pg_temp.event('100','100','1',1),'conflict');
SELECT pg_temp.run('same_id_other_trigger',pg_temp.event('100','100','2'),'conflict');
SELECT pg_temp.run('other_cycle_blocked',pg_temp.event('200','200'),'conflict');
SELECT pg_temp.run('negative_duration',pg_temp.event('101','100','1',-1),'conflict');
SELECT pg_temp.run('close',pg_temp.event('101','100','1',60),'applied');
SELECT pg_temp.ok('duration_60', (SELECT duration_seconds=60 AND state='closed' FROM incident.incident_summary WHERE problem_event_id='100'));
SELECT pg_temp.ok('one_close_job', (SELECT count(*)=1 FROM incident.report_jobs));
CREATE TEMP TABLE saved_job AS SELECT * FROM incident.report_jobs;
SELECT pg_temp.run('duplicate_recovery',pg_temp.event('101','100','1',60),'duplicate');
SELECT pg_temp.run('different_recovery',pg_temp.event('102','100','1',61),'conflict');
SELECT pg_temp.run('old_problem_never_reopens',pg_temp.event('100','100'),'duplicate');
SELECT pg_temp.run('retry_previously_blocked_cycle',pg_temp.event('200','200','1',70),'applied');
SELECT pg_temp.run('old_recovery_new_open',pg_temp.event('101','100','1',60),'duplicate');
SELECT pg_temp.ok('new_cycle_still_open',(SELECT state='open' FROM incident.incident_summary WHERE problem_event_id='200'));
SELECT pg_temp.run('close_second',pg_temp.event('201','200','1',90),'applied');
SELECT pg_temp.ok('snapshot_unchanged',(SELECT snapshot FROM incident.report_jobs WHERE incident_id=1) = (SELECT snapshot FROM saved_job));
SELECT pg_temp.ok('history_count',(SELECT (j.snapshot->>'previous_closed_count')::integer=1 FROM incident.report_jobs j JOIN incident.incidents i USING(incident_id) WHERE i.problem_event_id='200'));

SELECT pg_temp.run('orphan',pg_temp.event('301','300','1',120),'pending');
SELECT pg_temp.ok('orphan_no_incident',NOT EXISTS (SELECT FROM incident.incident_summary WHERE problem_event_id='300'));
SELECT pg_temp.ok('pending_visible',EXISTS (SELECT FROM incident.pending_recoveries WHERE problem_event_id='300'));
SELECT pg_temp.run('orphan_duplicate',pg_temp.event('301','300','1',120),'duplicate');
SELECT pg_temp.run('orphan_second_recovery',pg_temp.event('302','300','1',120),'conflict');
SELECT pg_temp.run('orphan_wrong_trigger',pg_temp.event('300','300','2',100),'conflict');
SELECT pg_temp.run('orphan_invalid_order',pg_temp.event('300','300','1',121),'conflict');
SELECT pg_temp.run('delayed_problem',pg_temp.event('300','300','1',100),'applied');
SELECT pg_temp.ok('closed_out_of_order',(SELECT state='closed' AND out_of_order AND duration_seconds=20 FROM incident.incident_summary WHERE problem_event_id='300'));
SELECT pg_temp.ok('pending_removed',NOT EXISTS (SELECT FROM incident.pending_recoveries WHERE problem_event_id='300'));
SELECT pg_temp.ok('out_of_order_job',EXISTS (SELECT FROM incident.report_jobs j JOIN incident.incidents i USING(incident_id) WHERE i.problem_event_id='300'));

SELECT pg_temp.run('collection_one',pg_temp.event('400','400','2'),'applied');
SELECT pg_temp.run('collection_two',pg_temp.event('500','500','4'),'applied');
SELECT pg_temp.ok('two_collection_open',(SELECT count(*)=2 FROM incident.incident_summary WHERE category='collection' AND state='open'));
SELECT pg_temp.run('collection_one_close',pg_temp.event('401','400','2',5),'applied');
SELECT pg_temp.ok('collection_two_unaffected',(SELECT state='open' FROM incident.incident_summary WHERE problem_event_id='500'));
SELECT pg_temp.run('auth_open',pg_temp.event('600','600','3'),'applied');
SELECT pg_temp.run('collection_two_close',pg_temp.event('501','500','4',5),'applied');
SELECT pg_temp.ok('auth_unaffected',(SELECT state='open' FROM incident.incident_summary WHERE problem_event_id='600'));
-- Ciclo novo aberto não impede completar um ciclo antigo já recuperado.
SELECT pg_temp.run('new_cycle_open',pg_temp.event('700','700','1',200),'applied');
SELECT pg_temp.run('older_orphan',pg_temp.event('651','650','1',160),'pending');
SELECT pg_temp.run('older_delayed_problem',pg_temp.event('650','650','1',150),'applied');
SELECT pg_temp.ok('older_completion_preserves_open',(SELECT state='open' FROM incident.incident_summary WHERE problem_event_id='700'));
-- IDs acima de Number.MAX_SAFE_INTEGER preservados como texto.
SELECT pg_temp.run('twenty_digit_id',pg_temp.event('99999999999999999999','99999999999999999999','2'),'applied');
SELECT pg_temp.ok('id_not_rounded',EXISTS (SELECT FROM incident.delivery_summary WHERE event_id='99999999999999999999'));

-- Permissões efetivas, não apenas inspeção de GRANT.
SET ROLE incident_ingest;
DO $$ BEGIN
  IF incident.ingest('{}')->>'result' <> 'invalid' THEN RAISE EXCEPTION 'ingest_execute_failed'; END IF;
  BEGIN PERFORM * FROM incident.deliveries; RAISE EXCEPTION 'direct_select_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN DELETE FROM incident.cycles; RAISE EXCEPTION 'direct_delete_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE incident.allowed_conditions SET trigger_id='9'; RAISE EXCEPTION 'mapping_update_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN CREATE TABLE incident.forbidden(id int); RAISE EXCEPTION 'ddl_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.ok('ingest_privileges',true);
SET ROLE incident_reader;
DO $$ BEGIN
  PERFORM * FROM incident.incident_summary;
  PERFORM * FROM incident.pending_recoveries;
  BEGIN PERFORM incident.ingest('{}'); RAISE EXCEPTION 'reader_ingest_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO incident.deliveries VALUES ('x','1','{}',now(),'applied'); RAISE EXCEPTION 'reader_write_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.ok('reader_privileges',true);
SET ROLE incident_report;
DO $$ BEGIN
  BEGIN UPDATE incident.cycles SET problem_at=now(); RAISE EXCEPTION 'report_incident_write_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM incident.ingest('{}'); RAISE EXCEPTION 'report_ingest_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.ok('report_cannot_change_incidents',true);
SELECT pg_temp.ok('public_cannot_execute',NOT has_function_privilege('n8n_meta','incident.ingest(text)','EXECUTE'));
-- Simula erro depois de trabalho SQL: transação revertida não deixa ledger/ciclo/job.
CREATE TEMP TABLE before_rollback AS SELECT pg_temp.state() AS state;
DO $$ BEGIN
  BEGIN
    IF incident.ingest(pg_temp.event('800','99999999999999999999','2',250))->>'result' <> 'applied' THEN
      RAISE EXCEPTION 'rollback_fixture_did_not_apply';
    END IF;
    IF NOT EXISTS (SELECT FROM incident.report_jobs j JOIN incident.incidents i USING (incident_id)
        WHERE i.problem_event_id='99999999999999999999') THEN RAISE EXCEPTION 'rollback_fixture_no_job'; END IF;
    RAISE SQLSTATE 'P1234' USING MESSAGE = 'forced_failure_after_close_and_job';
  EXCEPTION WHEN SQLSTATE 'P1234' THEN NULL;
  END;
END $$;
SELECT pg_temp.ok('rollback_complete',(SELECT state FROM before_rollback) = pg_temp.state());
DO $$ BEGIN
  BEGIN
    INSERT INTO incident.cycles(source_instance,problem_event_id,trigger_id,problem_at,problem_received_at)
      VALUES ('fixture','801','2',now(),now());
    RAISE EXCEPTION 'partial_unique_index_failed';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;
SELECT pg_temp.ok('partial_unique_index_defense',(SELECT state FROM before_rollback) = pg_temp.state());
SELECT json_build_object('check','incident_sql_transitions_contract_privileges','result','pass','checks',count(*)) FROM test_results;
