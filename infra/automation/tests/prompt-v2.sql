\set ON_ERROR_STOP on
-- Somente fixture isolada. Nenhuma linha do banco ativo é alterada por este teste.
DO $$
DECLARE token uuid; answer jsonb; original_html text; iid bigint; invalid jsonb;
BEGIN
  SELECT html_body INTO original_html FROM incident.report_jobs WHERE state='ready' LIMIT 1;
  INSERT INTO incident.allowed_conditions VALUES ('promptv2fixture','1','api-http','availability');
  PERFORM incident.ingest('{"contract_version":1,"source":"zabbix","source_instance":"promptv2fixture","event_type":"problem","event_id":"1","problem_event_id":"1","trigger_id":"1","host":"secureops-api","service":"secureops-api","condition":"api-http","category":"availability","occurred_at":"1793047000"}');
  PERFORM incident.ingest('{"contract_version":1,"source":"zabbix","source_instance":"promptv2fixture","event_type":"recovery","event_id":"2","problem_event_id":"1","trigger_id":"1","host":"secureops-api","service":"secureops-api","condition":"api-http","category":"availability","occurred_at":"1793047040"}');
  SELECT incident_id INTO iid FROM incident.incidents WHERE source_instance='promptv2fixture';
  SELECT (incident.claim_report_job(30)->>'lease_token')::uuid INTO token;
  IF token IS NULL THEN RAISE EXCEPTION 'missing_v2_lease'; END IF;
  BEGIN
    PERFORM incident.save_report(token,'{"summary":"teste","hypotheses":["limitação"],"recommendations":["revisão"]}', 'qwen2.5:1.5b-instruct-q4_K_M',99);
    RAISE EXCEPTION 'unknown_prompt_accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'invalid_model_output' THEN RAISE; END IF;
  END;
  FOREACH invalid IN ARRAY ARRAY[
    'null'::jsonb, '[]'::jsonb,
    '{"summary":"teste","hypotheses":["x"],"recommendations":["y"],"extra":"injection"}'::jsonb,
    jsonb_build_object('summary',repeat('x',801),'hypotheses',jsonb_build_array('x'),'recommendations',jsonb_build_array('y')),
    '{"summary":"teste","hypotheses":["1","2","3","4","5"],"recommendations":["y"]}'::jsonb,
    '{"summary":"teste","hypotheses":[7],"recommendations":["y"]}'::jsonb,
    '{"summary":"teste","hypotheses":["x"],"recommendations":[]}'::jsonb,
    jsonb_build_object('summary','teste','hypotheses',jsonb_build_array('x'),'recommendations',jsonb_build_array(repeat('x',401)))
  ] LOOP
    BEGIN
      PERFORM incident.save_report(token,invalid,'qwen2.5:1.5b-instruct-q4_K_M',2);
      RAISE EXCEPTION 'unsafe_model_output_accepted';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'invalid_model_output' THEN RAISE; END IF;
    END;
  END LOOP;
  BEGIN
    PERFORM incident.save_report(token,'{"summary":"","hypotheses":[],"recommendations":[]}', 'qwen2.5:1.5b-instruct-q4_K_M',2);
    RAISE EXCEPTION 'invalid_v2_accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'invalid_model_output' THEN RAISE; END IF;
  END;
  answer:=incident.save_report(token,'{"summary":"Causa indeterminada; cobertura limitada. <script>alert(1)</script>","hypotheses":["Sem evidência causal"],"recommendations":["Revisão humana"]}', 'qwen2.5:1.5b-instruct-q4_K_M',2);
  IF answer->>'result'<>'ready' OR NOT EXISTS (SELECT FROM incident.report_jobs WHERE incident_id=iid AND prompt_version=2 AND html_body LIKE '%&lt;script&gt;%' AND html_body NOT LIKE '%<script>%') THEN
    RAISE EXCEPTION 'v2_template_or_version_failed';
  END IF;
  IF original_html IS NULL OR NOT EXISTS (SELECT FROM incident.report_jobs WHERE html_body=original_html AND prompt_version=1) THEN
    RAISE EXCEPTION 'v1_not_preserved';
  END IF;
END $$;
SELECT '{"check":"prompt_v2_version_schema_xss_v1_preserved","result":"pass","checks":12}';
