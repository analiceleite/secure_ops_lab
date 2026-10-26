-- Revisão aditiva: permite identificar o prompt revisado sem reescrever relatórios v1.
\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(74004, 3);
DO $$
DECLARE definition text;
BEGIN
  IF current_database() <> 'incidents' OR
     NOT EXISTS (SELECT FROM incident.schema_version WHERE version=2) THEN
    RAISE EXCEPTION 'migration_002_required';
  END IF;
  IF EXISTS (SELECT FROM incident.schema_version WHERE version=3) THEN
    RAISE EXCEPTION 'migration_already_applied';
  END IF;
  definition:=pg_get_functiondef('incident.save_report(uuid,jsonb,text,integer)'::regprocedure);
  IF position('prompt_rev <> 1' IN definition)=0 THEN
    RAISE EXCEPTION 'unexpected_save_report_definition';
  END IF;
  -- Mantém validações de modelo/schema/lease e o template HTML original.
  EXECUTE replace(definition,'prompt_rev <> 1','prompt_rev NOT IN (1, 2)');
END $$;
SET LOCAL ROLE incident_owner;
ALTER TABLE incident.schema_version DROP CONSTRAINT schema_version_version_check;
ALTER TABLE incident.schema_version ADD CONSTRAINT schema_version_version_check CHECK (version IN (1,2,3));
INSERT INTO incident.schema_version(version) VALUES (3);
COMMIT;
