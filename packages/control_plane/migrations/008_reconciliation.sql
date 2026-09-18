CREATE TABLE IF NOT EXISTS control_plane_reconciliation_findings (
  organization_id text NOT NULL,
  application_id text,
  environment_id text,
  finding_id text NOT NULL,
  body jsonb NOT NULL,
  body_digest text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, finding_id),
  CHECK (jsonb_typeof(body) = 'object')
);

CREATE INDEX IF NOT EXISTS control_plane_reconciliation_findings_scope_idx
  ON control_plane_reconciliation_findings
    (organization_id, application_id, environment_id, finding_id);

CREATE TABLE IF NOT EXISTS control_plane_reconciliation_repairs (
  organization_id text NOT NULL,
  application_id text,
  environment_id text,
  repair_id text NOT NULL,
  finding_id text NOT NULL,
  body jsonb NOT NULL,
  body_digest text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, repair_id),
  CHECK (jsonb_typeof(body) = 'object')
);

CREATE INDEX IF NOT EXISTS control_plane_reconciliation_repairs_scope_idx
  ON control_plane_reconciliation_repairs
    (organization_id, application_id, environment_id, repair_id);

CREATE TABLE IF NOT EXISTS control_plane_reconciliation_lifecycle (
  organization_id text NOT NULL,
  application_id text,
  environment_id text,
  finding_id text NOT NULL,
  version bigint NOT NULL CHECK (version >= 0),
  body jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, finding_id),
  CHECK (jsonb_typeof(body) = 'object')
);

CREATE INDEX IF NOT EXISTS control_plane_reconciliation_lifecycle_scope_idx
  ON control_plane_reconciliation_lifecycle
    (organization_id, application_id, environment_id, finding_id);

CREATE TABLE IF NOT EXISTS control_plane_reconciliation_cursors (
  organization_id text NOT NULL,
  application_id text,
  environment_id text,
  scope_digest text NOT NULL,
  version bigint NOT NULL CHECK (version >= 0),
  body jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, scope_digest),
  CHECK (jsonb_typeof(body) = 'object')
);

CREATE INDEX IF NOT EXISTS control_plane_reconciliation_cursors_scope_idx
  ON control_plane_reconciliation_cursors
    (organization_id, application_id, environment_id, scope_digest);
