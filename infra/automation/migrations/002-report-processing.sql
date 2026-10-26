-- Relatorios/outbox. Executar uma vez, administrativamente, somente em incidents.
-- Nao altera incidentes nem toca no banco Zabbix.
\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(74004, 2);
DO $$ BEGIN
  IF current_database() <> 'incidents' THEN RAISE EXCEPTION 'wrong_database'; END IF;
  IF to_regclass('incident.schema_version') IS NULL OR
     NOT EXISTS (SELECT FROM incident.schema_version WHERE version=1) THEN
    RAISE EXCEPTION 'migration_001_required';
  END IF;
  IF EXISTS (SELECT FROM incident.schema_version WHERE version=2) THEN
    RAISE EXCEPTION 'migration_already_applied';
  END IF;
END $$;
SET LOCAL ROLE incident_owner;

ALTER TABLE incident.report_jobs DROP CONSTRAINT report_jobs_state_check;
ALTER TABLE incident.report_jobs ADD CONSTRAINT report_jobs_state_check
  CHECK (state IN ('pending','generating','ready','failed'));
ALTER TABLE incident.report_jobs
  ADD COLUMN lease_token uuid,
  ADD COLUMN lease_until timestamptz,
  ADD COLUMN attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 2),
  ADD COLUMN analysis jsonb,
  ADD COLUMN html_body text,
  ADD COLUMN text_body text,
  ADD COLUMN model_id text,
  ADD COLUMN prompt_version integer,
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ADD COLUMN last_error text,
  ADD CONSTRAINT report_job_lease_pair CHECK ((lease_token IS NULL) = (lease_until IS NULL)),
  ADD CONSTRAINT report_job_output_pair CHECK ((html_body IS NULL) = (text_body IS NULL));
CREATE INDEX report_jobs_claim_idx ON incident.report_jobs(created_at,incident_id)
  WHERE state='pending';

CREATE TABLE incident.report_outbox (
  outbox_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  incident_id bigint NOT NULL,
  report_version integer NOT NULL,
  message_id text NOT NULL UNIQUE,
  state text NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending','sending','accepted','failed','delivery_unknown')),
  attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
  lease_until timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (incident_id,report_version),
  FOREIGN KEY (incident_id,report_version)
    REFERENCES incident.report_jobs(incident_id,report_version),
  CHECK ((state='sending') = (lease_until IS NOT NULL))
);
CREATE VIEW incident.report_outbox_summary AS
  SELECT outbox_id,incident_id,report_version,state,attempts,created_at,updated_at,last_error
  FROM incident.report_outbox;

CREATE FUNCTION incident.claim_report_job(lease_seconds integer DEFAULT 180)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,incident,pg_temp SET statement_timeout='5s' AS $$
DECLARE job incident.report_jobs%ROWTYPE; token uuid;
BEGIN
  IF lease_seconds < 30 OR lease_seconds > 600 THEN RAISE EXCEPTION 'invalid_lease'; END IF;
  -- Lease expirada pode ser retomada apenas antes de exceder as duas tentativas.
  UPDATE incident.report_jobs SET state='pending',lease_token=NULL,lease_until=NULL,
    updated_at=clock_timestamp(),last_error='lease_expired'
    WHERE state='generating' AND lease_until < clock_timestamp() AND attempts < 2;
  UPDATE incident.report_jobs SET state='failed',lease_token=NULL,lease_until=NULL,
    updated_at=clock_timestamp(),last_error='lease_expired'
    WHERE state='generating' AND lease_until < clock_timestamp() AND attempts >= 2;
  SELECT * INTO job FROM incident.report_jobs
    WHERE state='pending' AND attempts < 2
    ORDER BY created_at,incident_id FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  token:=gen_random_uuid();
  UPDATE incident.report_jobs SET state='generating',lease_token=token,
    lease_until=clock_timestamp()+make_interval(secs=>lease_seconds),attempts=attempts+1,
    updated_at=clock_timestamp(),last_error=NULL
    WHERE incident_id=job.incident_id AND report_version=job.report_version
    RETURNING * INTO job;
  RETURN jsonb_build_object('incident_id',job.incident_id,'report_version',job.report_version,
    'lease_token',token,'attempt',job.attempts,'snapshot',job.snapshot);
END $$;

CREATE FUNCTION incident.fail_report_job(token uuid, category text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,incident,pg_temp AS $$
DECLARE result text;
BEGIN
  IF category NOT IN ('model_unavailable','model_timeout','invalid_model_output','lease_expired')
    THEN RAISE EXCEPTION 'invalid_failure_category'; END IF;
  UPDATE incident.report_jobs SET
    state=CASE WHEN attempts < 2 THEN 'pending' ELSE 'failed' END,
    lease_token=NULL,lease_until=NULL,last_error=category,updated_at=clock_timestamp()
    WHERE lease_token=token AND state='generating' AND lease_until>clock_timestamp()
    RETURNING state INTO result;
  RETURN coalesce(result,'stale');
END $$;

CREATE FUNCTION incident.html_escape(value text) RETURNS text
LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
  SELECT replace(replace(replace(replace(replace(value,'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;')
$$;

CREATE FUNCTION incident.save_report(token uuid, model_output jsonb,
  model_name text DEFAULT 'qwen2.5:1.5b-instruct-q4_K_M', prompt_rev integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,incident,pg_temp SET statement_timeout='5s' AS $$
DECLARE j incident.report_jobs%ROWTYPE; facts jsonb; summary text; hypotheses jsonb; recommendations jsonb;
  html text; plain text; outbox bigint; keys text[];
BEGIN
  SELECT * INTO j FROM incident.report_jobs WHERE lease_token=token AND state='generating'
    AND lease_until>clock_timestamp() FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('result','stale'); END IF;
  IF model_name <> 'qwen2.5:1.5b-instruct-q4_K_M' OR prompt_rev <> 1 OR
     jsonb_typeof(model_output) <> 'object' THEN RAISE EXCEPTION 'invalid_model_output'; END IF;
  keys:=ARRAY(SELECT key FROM jsonb_object_keys(model_output) AS key ORDER BY key);
  IF keys <> ARRAY['hypotheses','recommendations','summary']::text[] OR
     jsonb_typeof(model_output->'summary') <> 'string' OR
     length(model_output->>'summary') NOT BETWEEN 1 AND 800 OR
     jsonb_typeof(model_output->'hypotheses') <> 'array' OR
     jsonb_array_length(model_output->'hypotheses') NOT BETWEEN 1 AND 4 OR
     jsonb_typeof(model_output->'recommendations') <> 'array' OR
     jsonb_array_length(model_output->'recommendations') NOT BETWEEN 1 AND 4 OR
     EXISTS (SELECT FROM jsonb_array_elements(model_output->'hypotheses') x WHERE jsonb_typeof(x)<>'string' OR length(x#>>'{}') NOT BETWEEN 1 AND 400) OR
     EXISTS (SELECT FROM jsonb_array_elements(model_output->'recommendations') x WHERE jsonb_typeof(x)<>'string' OR length(x#>>'{}') NOT BETWEEN 1 AND 400) THEN
    RAISE EXCEPTION 'invalid_model_output';
  END IF;
  facts:=j.snapshot->'facts'; summary:=model_output->>'summary';
  hypotheses:=model_output->'hypotheses'; recommendations:=model_output->'recommendations';
  html:='<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Relatório SecureOps</title>'||
    '<style>body{font:16px system-ui,sans-serif;max-width:760px;margin:2rem auto;padding:0 1rem;color:#172033}table{border-collapse:collapse}th,td{text-align:left;padding:.4rem;border-bottom:1px solid #ccd}aside{background:#fff8d8;padding:1rem}</style></head><body>'||
    '<h1>Relatório de incidente #'||j.incident_id||'</h1><p>Serviço: '||incident.html_escape(coalesce(facts->>'service','não informado'))||
    ' · Condição: '||incident.html_escape(coalesce(facts->>'condition','não informada'))||'</p><h2>Fatos observados</h2><table>'||
    '<tr><th>Categoria</th><td>'||incident.html_escape(coalesce(facts->>'category','não informada'))||'</td></tr>'||
    '<tr><th>Abertura observada (UTC)</th><td>'||incident.html_escape(coalesce(facts->>'opened_at','não informada'))||'</td></tr>'||
    '<tr><th>Encerramento observado (UTC)</th><td>'||incident.html_escape(coalesce(facts->>'closed_at','não informado'))||'</td></tr>'||
    '<tr><th>Duração observada</th><td>'||incident.html_escape(coalesce(facts->>'duration_seconds','não informada'))||' s</td></tr>'||
    '<tr><th>Incidentes anteriores na janela</th><td>'||incident.html_escape(coalesce(j.snapshot->>'previous_closed_count','0'))||
    ' / '||incident.html_escape(coalesce(j.snapshot->>'history_window_seconds','604800'))||' s</td></tr></table>'||
    '<h2>Análise gerada por IA local</h2><p>'||incident.html_escape(summary)||'</p><h3>Hipóteses (não confirmadas)</h3><ul>'||
    (SELECT string_agg('<li>'||incident.html_escape(value#>>'{}')||'</li>','' ORDER BY ord) FROM jsonb_array_elements(hypotheses) WITH ORDINALITY a(value,ord))||
    '</ul><h3>Recomendações preventivas para revisão humana</h3><ul>'||
    (SELECT string_agg('<li>'||incident.html_escape(value#>>'{}')||'</li>','' ORDER BY ord) FROM jsonb_array_elements(recommendations) WITH ORDINALITY a(value,ord))||
    '</ul><aside>Texto de IA pode conter erros; hipóteses não comprovam causa raiz. Duração é o intervalo observado entre eventos do monitor. Cobertura histórica pode ser incompleta.</aside>'||
    '<p>Modelo: '||incident.html_escape(model_name)||' · Prompt: v'||prompt_rev||' · Relatório: '||j.incident_id||'/v'||j.report_version||'</p></body></html>';
  plain:='Relatório SecureOps #'||j.incident_id||E'\nFatos observados:\n'||
    'Serviço: '||coalesce(facts->>'service','não informado')||E'\nCondição: '||coalesce(facts->>'condition','não informada')||E'\n'||
    'Abertura UTC: '||coalesce(facts->>'opened_at','não informada')||E'\nEncerramento UTC: '||coalesce(facts->>'closed_at','não informado')||E'\n'||
    'Duração observada: '||coalesce(facts->>'duration_seconds','não informada')||' s'||E'\n\nAnálise IA local:\n'||summary||
    E'\n\nHipóteses (não confirmadas):\n'||(SELECT string_agg('- '||(value#>>'{}'),E'\n') FROM jsonb_array_elements(hypotheses))||
    E'\n\nRecomendações para revisão humana:\n'||(SELECT string_agg('- '||(value#>>'{}'),E'\n') FROM jsonb_array_elements(recommendations))||
    E'\n\nIA pode conter erros; duração é intervalo observado e histórico pode ser incompleto.';
  UPDATE incident.report_jobs SET state='ready',analysis=model_output,html_body=html,text_body=plain,
    model_id=model_name,prompt_version=prompt_rev,lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp()
    WHERE incident_id=j.incident_id AND report_version=j.report_version;
  INSERT INTO incident.report_outbox(incident_id,report_version,message_id)
    VALUES(j.incident_id,j.report_version,'<secureops-'||j.incident_id||'-v'||j.report_version||'@lab.invalid>')
    ON CONFLICT (incident_id,report_version) DO NOTHING RETURNING outbox_id INTO outbox;
  IF outbox IS NULL THEN SELECT outbox_id INTO outbox FROM incident.report_outbox WHERE incident_id=j.incident_id AND report_version=j.report_version; END IF;
  RETURN jsonb_build_object('result','ready','incident_id',j.incident_id,'report_version',j.report_version,
    'outbox_id',outbox,'subject','SecureOps | Relatório #'||j.incident_id||' v'||j.report_version,
    'html',html,'text',plain);
END $$;

CREATE FUNCTION incident.begin_report_delivery(id bigint, lease_seconds integer DEFAULT 90)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,incident,pg_temp AS $$
DECLARE o incident.report_outbox%ROWTYPE; j incident.report_jobs%ROWTYPE;
BEGIN
  IF lease_seconds < 30 OR lease_seconds > 300 THEN RAISE EXCEPTION 'invalid_lease'; END IF;
  UPDATE incident.report_outbox SET state='delivery_unknown',lease_until=NULL,
    last_error='previous_send_lease_expired',updated_at=clock_timestamp()
    WHERE outbox_id=id AND state='sending' AND lease_until<clock_timestamp();
  UPDATE incident.report_outbox SET state='sending',attempts=attempts+1,
    lease_until=clock_timestamp()+make_interval(secs=>lease_seconds),updated_at=clock_timestamp()
    WHERE outbox_id=id AND state='pending' AND attempts<3 RETURNING * INTO o;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO j FROM incident.report_jobs WHERE incident_id=o.incident_id AND report_version=o.report_version;
  RETURN jsonb_build_object('outbox_id',o.outbox_id,'incident_id',o.incident_id,
    'report_version',o.report_version,'message_id',o.message_id,'subject','SecureOps | Relatório #'||o.incident_id||' v'||o.report_version,
    'html',j.html_body,'text',j.text_body);
END $$;

CREATE FUNCTION incident.claim_report_outbox(lease_seconds integer DEFAULT 90)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,incident,pg_temp SET statement_timeout='5s' AS $$
DECLARE o incident.report_outbox%ROWTYPE; j incident.report_jobs%ROWTYPE;
BEGIN
  IF lease_seconds < 30 OR lease_seconds > 300 THEN RAISE EXCEPTION 'invalid_lease'; END IF;
  -- SMTP pode ter aceito antes do crash. Expirar lease vira desconhecido, nunca reenvio automático.
  UPDATE incident.report_outbox SET state='delivery_unknown',lease_until=NULL,
    last_error='previous_send_lease_expired',updated_at=clock_timestamp()
    WHERE state='sending' AND lease_until<clock_timestamp();
  SELECT * INTO o FROM incident.report_outbox WHERE state='pending' AND attempts<3
    ORDER BY created_at,outbox_id FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE incident.report_outbox SET state='sending',attempts=attempts+1,
    lease_until=clock_timestamp()+make_interval(secs=>lease_seconds),updated_at=clock_timestamp()
    WHERE outbox_id=o.outbox_id RETURNING * INTO o;
  SELECT * INTO j FROM incident.report_jobs WHERE incident_id=o.incident_id AND report_version=o.report_version;
  RETURN jsonb_build_object('outbox_id',o.outbox_id,'incident_id',o.incident_id,
    'report_version',o.report_version,'message_id',o.message_id,
    'subject','SecureOps | Relatório #'||o.incident_id||' v'||o.report_version,
    'html',j.html_body,'text',j.text_body);
END $$;

CREATE FUNCTION incident.finish_report_delivery(id bigint, outcome text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,incident,pg_temp AS $$
DECLARE result text;
BEGIN
  IF outcome NOT IN ('accepted','failed','delivery_unknown') THEN RAISE EXCEPTION 'invalid_delivery_outcome'; END IF;
  UPDATE incident.report_outbox SET state=outcome,lease_until=NULL,updated_at=clock_timestamp(),
    last_error=CASE WHEN outcome='accepted' THEN NULL ELSE outcome END
    WHERE outbox_id=id AND state='sending' AND lease_until>clock_timestamp() RETURNING state INTO result;
  RETURN coalesce(result,'stale');
END $$;

CREATE OR REPLACE VIEW incident.report_job_summary AS
  SELECT incident_id,report_version,created_at,state,attempts,updated_at,last_error FROM incident.report_jobs;
REVOKE ALL ON ALL TABLES IN SCHEMA incident FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA incident FROM PUBLIC;
GRANT SELECT ON incident.report_job_summary,incident.report_outbox_summary TO incident_reader;
GRANT EXECUTE ON FUNCTION incident.claim_report_job(integer),incident.fail_report_job(uuid,text),
  incident.save_report(uuid,jsonb,text,integer),incident.begin_report_delivery(bigint,integer),
  incident.claim_report_outbox(integer),incident.finish_report_delivery(bigint,text) TO incident_report;
ALTER TABLE incident.schema_version DROP CONSTRAINT schema_version_version_check;
ALTER TABLE incident.schema_version ADD CONSTRAINT schema_version_version_check CHECK (version IN (1,2));
INSERT INTO incident.schema_version(version) VALUES (2);
COMMIT;
