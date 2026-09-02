-- Hyfens control-plane metadata migration 001.
-- The application applies this statement list transactionally and records the
-- version in control_plane_schema_migrations before serving traffic.
CREATE TABLE IF NOT EXISTS control_plane_schema_migrations (
  version integer PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS control_plane_records (
  collection text NOT NULL,
  record_id text NOT NULL,
  organization_id text,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (collection, record_id)
);

CREATE INDEX IF NOT EXISTS control_plane_records_tenant_idx
  ON control_plane_records (organization_id, collection, record_id);

CREATE TABLE IF NOT EXISTS control_plane_artifacts (
  digest text PRIMARY KEY,
  artifact_bytes bytea NOT NULL,
  size_bytes bigint NOT NULL CHECK (size_bytes >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS control_plane_audit_chain (
  sequence bigserial PRIMARY KEY,
  audit_id text NOT NULL UNIQUE,
  organization_id text,
  previous_digest text,
  record_digest text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
