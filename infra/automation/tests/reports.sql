\set ON_ERROR_STOP on
CREATE TEMP TABLE report_test_ok(name text PRIMARY KEY);
CREATE FUNCTION pg_temp.assert_report(name text, condition boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'report_assertion_failed:%',name; END IF;
  INSERT INTO report_test_ok VALUES(name);
END $$;

-- Isola um evento fictício para testar job/lease/HTML sem depender de macros reais.
UPDATE incident.report_jobs SET state='failed',last_error='fixture_isolation'
  WHERE state IN ('pending','generating');
INSERT INTO incident.allowed_conditions VALUES('reportfixture','1','api-http','availability');
DO $$ DECLARE t bigint:=extract(epoch FROM clock_timestamp())::bigint-30; BEGIN
  PERFORM incident.ingest(jsonb_build_object('contract_version',1,'source','zabbix','source_instance','reportfixture',
    'event_type','problem','event_id','990','problem_event_id','990','trigger_id','1','host','secureops-api',
    'service','secureops-api','condition','api-http','category','availability','occurred_at',t::text)::text);
  PERFORM incident.ingest(jsonb_build_object('contract_version',1,'source','zabbix','source_instance','reportfixture',
    'event_type','recovery','event_id','991','problem_event_id','990','trigger_id','1','host','secureops-api',
    'service','secureops-api','condition','api-http','category','availability','occurred_at',(t+12)::text)::text);
END $$;

CREATE TEMP TABLE claimed AS SELECT incident.claim_report_job(30) AS claim;
SELECT pg_temp.assert_report('claimed_one_job',(SELECT claim->>'incident_id' IS NOT NULL FROM claimed));
SELECT pg_temp.assert_report('claim_has_lease',(SELECT claim->>'lease_token' ~ '^[0-9a-f-]{36}$' FROM claimed));
SELECT pg_temp.assert_report('claim_attempt_one',(SELECT claim->>'attempt'='1' FROM claimed));
SELECT pg_temp.assert_report('same_job_not_claimed_twice',incident.claim_report_job(30) IS NULL);

DO $$ DECLARE token uuid:=(SELECT (claim->>'lease_token')::uuid FROM claimed); answer jsonb; BEGIN
  BEGIN
    PERFORM incident.save_report(token,'{"summary":"","hypotheses":[],"recommendations":[]}'::jsonb);
    RAISE EXCEPTION 'invalid_model_output_accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='invalid_model_output_accepted' THEN RAISE; END IF;
  END;
  answer:=incident.save_report(token,
    '{"summary":"API recuperou após interrupção observada; causa não comprovada.","hypotheses":["Falha temporária de disponibilidade"],"recommendations":["Revisar métricas e logs locais do período"]}'::jsonb);
  IF answer->>'result'<>'ready' THEN RAISE EXCEPTION 'report_not_ready'; END IF;
  IF answer->>'html' LIKE '%<script%' OR answer->>'html' NOT LIKE '%Análise gerada por IA local%' THEN
    RAISE EXCEPTION 'html_security_or_template_failed';
  END IF;
  PERFORM pg_temp.assert_report('html_xss_escaped',incident.html_escape('<script>&"''')='&lt;script&gt;&amp;&quot;&#39;');
  PERFORM pg_temp.assert_report('outbox_created_once',(SELECT count(*)=1 FROM incident.report_outbox WHERE incident_id=(answer->>'incident_id')::bigint));
END $$;
SELECT pg_temp.assert_report('report_state_ready',(SELECT state='ready' AND html_body IS NOT NULL AND text_body IS NOT NULL
  FROM incident.report_jobs WHERE incident_id=(SELECT (claim->>'incident_id')::bigint FROM claimed)));

CREATE TEMP TABLE delivery AS
SELECT incident.claim_report_outbox(30) AS delivery;
SELECT pg_temp.assert_report('delivery_claimed',(SELECT delivery->>'outbox_id' IS NOT NULL FROM delivery));
SELECT pg_temp.assert_report('delivery_not_claimed_twice',(
  SELECT incident.claim_report_outbox(30) IS NULL FROM delivery));
SELECT pg_temp.assert_report('delivery_accepted',(
  SELECT incident.finish_report_delivery((delivery->>'outbox_id')::bigint,'accepted')='accepted' FROM delivery));
SELECT pg_temp.assert_report('accepted_not_resendable',(
  SELECT incident.begin_report_delivery((delivery->>'outbox_id')::bigint,30) IS NULL FROM delivery));

-- Mensagem cujo envio ficou ambíguo nunca retorna a pending automaticamente.
CREATE TEMP TABLE ambiguous AS
SELECT outbox_id FROM incident.report_outbox WHERE incident_id=(SELECT (claim->>'incident_id')::bigint FROM claimed);
UPDATE incident.report_outbox SET state='sending',lease_until=clock_timestamp()-interval '1 second'
  WHERE outbox_id=(SELECT outbox_id FROM ambiguous);
SELECT pg_temp.assert_report('ambiguous_lease_not_resent',
  incident.begin_report_delivery((SELECT outbox_id FROM ambiguous),30) IS NULL);
SELECT pg_temp.assert_report('ambiguous_becomes_unknown',
  (SELECT state='delivery_unknown' FROM incident.report_outbox WHERE outbox_id=(SELECT outbox_id FROM ambiguous)));

SET ROLE incident_report;
DO $$ BEGIN
  BEGIN UPDATE incident.report_jobs SET state='failed'; RAISE EXCEPTION 'direct_dml_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN SELECT incident.ingest('{}'); RAISE EXCEPTION 'ingest_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.assert_report('report_role_no_table_write',true);
SET ROLE incident_reader;
SELECT count(*) FROM incident.report_job_summary;
SELECT count(*) FROM incident.report_outbox_summary;
RESET ROLE;
SELECT pg_temp.assert_report('reader_views_available',true);
SELECT json_build_object('check','incident_report_jobs_outbox','result','pass','checks',count(*)) FROM report_test_ok;
