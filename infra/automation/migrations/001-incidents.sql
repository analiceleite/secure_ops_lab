-- Executar administrativamente SOMENTE no banco incidents. Sem IDs reais embutidos.
-- Migração atômica, deliberadamente não destrutiva e não reaplicável por cima.
\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(74004, 1);
DO $$ BEGIN
  IF current_database() <> 'incidents' THEN RAISE EXCEPTION 'wrong_database'; END IF;
END $$;
SET LOCAL ROLE incident_owner;
CREATE SCHEMA incident AUTHORIZATION incident_owner;
REVOKE ALL ON SCHEMA incident FROM PUBLIC;
CREATE TABLE incident.schema_version (
  version integer PRIMARY KEY CHECK (version = 1),
  installed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO incident.schema_version(version) VALUES (1);

-- Provisionamento administrativo explícito após conferir os IDs reais.
-- A linha pré-provisionada também é o mutex da condição, antes do primeiro evento.
CREATE TABLE incident.allowed_conditions (
  source_instance text NOT NULL CHECK (source_instance ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  trigger_id text NOT NULL CHECK (trigger_id ~ '^[1-9][0-9]{0,19}$'),
  condition text NOT NULL CHECK (condition IN ('api-http','api-http-nodata','auth-threshold','auth-collection')),
  category text NOT NULL,
  PRIMARY KEY (source_instance, trigger_id),
  UNIQUE (source_instance, condition),
  CHECK (category = CASE condition WHEN 'api-http' THEN 'availability'
    WHEN 'auth-threshold' THEN 'authentication' ELSE 'collection' END)
);
CREATE TABLE incident.deliveries (
  source_instance text NOT NULL,
  event_id text NOT NULL CHECK (event_id ~ '^[1-9][0-9]{0,19}$'),
  envelope jsonb NOT NULL,
  received_at timestamptz NOT NULL,
  result text NOT NULL CHECK (result IN ('applied','pending')),
  PRIMARY KEY (source_instance, event_id)
);
CREATE TABLE incident.cycles (
  source_instance text NOT NULL,
  problem_event_id text NOT NULL CHECK (problem_event_id ~ '^[1-9][0-9]{0,19}$'),
  trigger_id text NOT NULL,
  problem_at timestamptz,
  problem_received_at timestamptz,
  recovery_event_id text,
  recovery_at timestamptz,
  recovery_received_at timestamptz,
  out_of_order boolean NOT NULL DEFAULT false,
  PRIMARY KEY (source_instance, problem_event_id),
  FOREIGN KEY (source_instance, trigger_id) REFERENCES incident.allowed_conditions,
  CHECK ((problem_at IS NULL) = (problem_received_at IS NULL)),
  CHECK ((recovery_event_id IS NULL) = (recovery_at IS NULL)),
  CHECK ((recovery_at IS NULL) = (recovery_received_at IS NULL)),
  CHECK (problem_at IS NOT NULL OR recovery_at IS NOT NULL),
  CHECK (recovery_event_id IS NULL OR (recovery_event_id ~ '^[1-9][0-9]{0,19}$' AND recovery_event_id <> problem_event_id)),
  CHECK (recovery_at IS NULL OR problem_at IS NULL OR recovery_at >= problem_at)
);
CREATE UNIQUE INDEX one_open_per_condition ON incident.cycles(source_instance, trigger_id)
  WHERE problem_at IS NOT NULL AND recovery_at IS NULL;
CREATE TABLE incident.incidents (
  incident_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_instance text NOT NULL,
  problem_event_id text NOT NULL,
  UNIQUE (source_instance, problem_event_id),
  FOREIGN KEY (source_instance, problem_event_id) REFERENCES incident.cycles
);
-- Reserva durável do trabalho de relatório; lease/geração/outbox serão a migração seguinte.
CREATE TABLE incident.report_jobs (
  incident_id bigint NOT NULL REFERENCES incident.incidents,
  report_version integer NOT NULL CHECK (report_version = 1),
  snapshot jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  state text NOT NULL DEFAULT 'pending' CHECK (state = 'pending'),
  PRIMARY KEY (incident_id, report_version)
);

CREATE VIEW incident.incident_summary AS
SELECT i.incident_id, c.source_instance, c.problem_event_id, c.trigger_id,
  'secureops-api'::text AS service, a.condition, a.category,
  CASE WHEN c.recovery_at IS NULL THEN 'open' ELSE 'closed' END AS state,
  c.problem_at AS opened_at, c.recovery_event_id, c.recovery_at AS closed_at,
  extract(epoch FROM c.recovery_at - c.problem_at)::bigint AS duration_seconds,
  c.problem_received_at, c.recovery_received_at, c.out_of_order
FROM incident.incidents i JOIN incident.cycles c USING (source_instance, problem_event_id)
JOIN incident.allowed_conditions a USING (source_instance, trigger_id);
CREATE VIEW incident.pending_recoveries AS
SELECT c.source_instance, c.problem_event_id, c.trigger_id, a.condition, a.category,
  c.recovery_event_id, c.recovery_at, c.recovery_received_at
FROM incident.cycles c JOIN incident.allowed_conditions a USING (source_instance, trigger_id)
WHERE c.problem_at IS NULL;
CREATE VIEW incident.delivery_summary AS
SELECT source_instance, event_id, received_at, result FROM incident.deliveries;
CREATE VIEW incident.report_job_summary AS
SELECT incident_id, report_version, created_at, state FROM incident.report_jobs;

-- Raw TEXT preserva chaves duplicadas antes da conversão para JSONB.
-- Uma chamada parametrizada/autocommit por evento; nunca SQL concatenado pelo workflow.
CREATE FUNCTION incident.ingest(raw_body text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp SET lock_timeout = '4s' AS $$
DECLARE
  raw json; e jsonb; mapping incident.allowed_conditions%ROWTYPE;
  prior incident.deliveries%ROWTYPE; cycle incident.cycles%ROWTYPE;
  received timestamptz := clock_timestamp(); occurred timestamptz;
  sid text; eid text; pid text; tid text; kind text;
  result text := 'applied'; iid bigint;
  fields constant text[] := ARRAY['contract_version','source','source_instance','event_type',
    'event_id','problem_event_id','trigger_id','host','service','condition','category','occurred_at'];
BEGIN
  IF raw_body IS NULL OR octet_length(raw_body) > 4096 THEN
    RETURN jsonb_build_object('result','invalid');
  END IF;
  BEGIN
    raw := raw_body::json;
    IF json_typeof(raw) IS DISTINCT FROM 'object' THEN RETURN jsonb_build_object('result','invalid'); END IF;
    IF (SELECT count(*) <> cardinality(fields) OR count(DISTINCT key) <> cardinality(fields)
        OR bool_or(NOT (key = ANY(fields))) FROM json_each(raw)) THEN
      RETURN jsonb_build_object('result','invalid');
    END IF;
    IF EXISTS (SELECT FROM json_each(raw) WHERE
      json_typeof(value) IS DISTINCT FROM CASE WHEN key = 'contract_version' THEN 'number' ELSE 'string' END) THEN
      RETURN jsonb_build_object('result','invalid');
    END IF;
    e := raw::jsonb;
    IF raw->>'contract_version' <> '1' OR e->>'source' <> 'zabbix'
      OR e->>'host' <> 'secureops-api' OR e->>'service' <> 'secureops-api'
      OR e->>'event_type' NOT IN ('problem','recovery')
      OR e->>'source_instance' !~ '^[a-z0-9][a-z0-9-]{0,63}$'
      OR e->>'event_id' !~ '^[1-9][0-9]{0,19}$'
      OR e->>'problem_event_id' !~ '^[1-9][0-9]{0,19}$'
      OR e->>'trigger_id' !~ '^[1-9][0-9]{0,19}$'
      OR e->>'occurred_at' !~ '^[1-9][0-9]{0,10}$' THEN
      RETURN jsonb_build_object('result','invalid');
    END IF;
    IF (e->>'occurred_at')::numeric > extract(epoch FROM received) + 60
      OR (e->>'occurred_at')::numeric < extract(epoch FROM received) - 604800 THEN
      RETURN jsonb_build_object('result','invalid');
    END IF;
    occurred := to_timestamp((e->>'occurred_at')::double precision);
  EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value OR numeric_value_out_of_range
    OR character_not_in_repertoire OR untranslatable_character THEN
    RETURN jsonb_build_object('result','invalid');
  END;
  sid := e->>'source_instance'; eid := e->>'event_id'; pid := e->>'problem_event_id';
  tid := e->>'trigger_id'; kind := e->>'event_type';
  IF (kind = 'problem' AND eid <> pid) OR (kind = 'recovery' AND eid = pid) THEN
    RETURN jsonb_build_object('result','invalid');
  END IF;
  SELECT * INTO mapping FROM incident.allowed_conditions
    WHERE source_instance = sid AND trigger_id = tid FOR UPDATE;
  IF NOT FOUND OR mapping.condition <> e->>'condition' OR mapping.category <> e->>'category' THEN
    RETURN jsonb_build_object('result','invalid');
  END IF;
  -- Serialize IDs partilhados mesmo se envelopes conflitantes apontarem para triggers distintas.
  PERFORM pg_advisory_xact_lock(74005, hashtext(sid || ':' || pid));
  PERFORM pg_advisory_xact_lock(74006, hashtext(sid || ':' || eid));
  SELECT * INTO prior FROM incident.deliveries WHERE source_instance = sid AND event_id = eid;
  IF FOUND THEN
    IF prior.envelope = e THEN RETURN jsonb_build_object('result','duplicate'); END IF;
    RETURN jsonb_build_object('result','conflict');
  END IF;
  SELECT * INTO cycle FROM incident.cycles WHERE source_instance = sid AND problem_event_id = pid;
  IF FOUND AND cycle.trigger_id <> tid THEN RETURN jsonb_build_object('result','conflict'); END IF;
  IF kind = 'problem' THEN
    IF cycle.problem_at IS NOT NULL OR (cycle.recovery_at IS NOT NULL AND cycle.recovery_at < occurred) THEN
      RETURN jsonb_build_object('result','conflict');
    END IF;
    IF cycle.recovery_at IS NULL AND EXISTS (SELECT FROM incident.cycles WHERE source_instance = sid
        AND trigger_id = tid AND problem_at IS NOT NULL AND recovery_at IS NULL) THEN
      RETURN jsonb_build_object('result','conflict');
    END IF;
    INSERT INTO incident.cycles(source_instance, problem_event_id, trigger_id, problem_at, problem_received_at)
      VALUES (sid, pid, tid, occurred, received)
      ON CONFLICT (source_instance, problem_event_id) DO UPDATE
        SET problem_at = occurred, problem_received_at = received, out_of_order = true;
    INSERT INTO incident.incidents(source_instance, problem_event_id) VALUES (sid, pid) RETURNING incident_id INTO iid;
  ELSE
    IF cycle.recovery_event_id IS NOT NULL OR (cycle.problem_at IS NOT NULL AND occurred < cycle.problem_at) THEN
      RETURN jsonb_build_object('result','conflict');
    END IF;
    INSERT INTO incident.cycles(source_instance, problem_event_id, trigger_id,
      recovery_event_id, recovery_at, recovery_received_at)
      VALUES (sid, pid, tid, eid, occurred, received)
      ON CONFLICT (source_instance, problem_event_id) DO UPDATE
        SET recovery_event_id = eid, recovery_at = occurred, recovery_received_at = received;
    IF cycle.problem_at IS NULL THEN result := 'pending'; END IF;
    SELECT incident_id INTO iid FROM incident.incidents WHERE source_instance = sid AND problem_event_id = pid;
  END IF;
  INSERT INTO incident.deliveries VALUES (sid, eid, e, received, result);
  -- Fechamento e trabalho durável no MESMO commit, sem IA/SMTP nesta função.
  INSERT INTO incident.report_jobs(incident_id, report_version, snapshot, created_at)
  SELECT s.incident_id, 1, jsonb_build_object(
    'snapshot_version',1,'facts',to_jsonb(s),
    'history_window_seconds',604800,
    'previous_closed_count',(SELECT count(*) FROM incident.incident_summary h
      WHERE h.source_instance = s.source_instance AND h.trigger_id = s.trigger_id
        AND h.incident_id <> s.incident_id AND h.state = 'closed'
        AND h.closed_at >= s.closed_at - interval '7 days' AND h.closed_at <= s.closed_at),
    'limitations',jsonb_build_array('Somente incidentes recebidos; cobertura historica incompleta possivel.',
      'Duracao observada pelo monitor, nao tempo exato da falha.')),
    received FROM incident.incident_summary s WHERE s.incident_id = iid AND s.state = 'closed'
    ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('result',result);
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA incident FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA incident FROM PUBLIC;
GRANT USAGE ON SCHEMA incident TO incident_ingest, incident_reader, incident_report;
GRANT EXECUTE ON FUNCTION incident.ingest(text) TO incident_ingest;
GRANT SELECT ON incident.incident_summary, incident.pending_recoveries,
  incident.delivery_summary, incident.report_job_summary TO incident_reader;
-- Role de relatório ainda sem rotinas de lease/saída; nenhum DML de incidentes.
COMMIT;
