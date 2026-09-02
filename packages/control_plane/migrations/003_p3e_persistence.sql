-- Hyfens P3E-2 immutable aggregate/evaluation persistence migration 003.
-- The application applies this statement list under the existing advisory
-- migration lock and records schema version 3 before serving traffic.
CREATE TABLE IF NOT EXISTS control_plane_p3e_aggregates (
  organization_id text NOT NULL,
  aggregate_id text NOT NULL,
  revision_id text NOT NULL,
  aggregate_digest text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, aggregate_id)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e_aggregates_revision_idx
  ON control_plane_p3e_aggregates
    (organization_id, revision_id, aggregate_id);

CREATE TABLE IF NOT EXISTS control_plane_p3e_aggregate_revisions (
  organization_id text NOT NULL,
  aggregate_revision_id text NOT NULL,
  aggregate_id text NOT NULL,
  parent_aggregate_revision_id text,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, aggregate_revision_id),
  UNIQUE (organization_id, aggregate_id, aggregate_revision_id),
  FOREIGN KEY (organization_id, aggregate_id)
    REFERENCES control_plane_p3e_aggregates(organization_id, aggregate_id)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e_revisions_aggregate_idx
  ON control_plane_p3e_aggregate_revisions
    (organization_id, aggregate_id, created_at, aggregate_revision_id);

CREATE TABLE IF NOT EXISTS control_plane_p3e_evaluations (
  organization_id text NOT NULL,
  evaluation_id text NOT NULL,
  aggregate_revision_id text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, evaluation_id),
  FOREIGN KEY (organization_id, aggregate_revision_id)
    REFERENCES control_plane_p3e_aggregate_revisions
      (organization_id, aggregate_revision_id)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e_evaluations_revision_idx
  ON control_plane_p3e_evaluations
    (organization_id, aggregate_revision_id, created_at, evaluation_id);

CREATE TABLE IF NOT EXISTS control_plane_p3e_decisions (
  organization_id text NOT NULL,
  decision_id text NOT NULL,
  evaluation_id text NOT NULL,
  aggregate_revision_id text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, decision_id),
  FOREIGN KEY (organization_id, evaluation_id)
    REFERENCES control_plane_p3e_evaluations(organization_id, evaluation_id),
  FOREIGN KEY (organization_id, aggregate_revision_id)
    REFERENCES control_plane_p3e_aggregate_revisions
      (organization_id, aggregate_revision_id)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e_decisions_rollout_idx
  ON control_plane_p3e_decisions
    (organization_id, created_at, decision_id);

CREATE TABLE IF NOT EXISTS control_plane_p3e_cursors (
  organization_id text NOT NULL,
  cursor_id text NOT NULL,
  aggregate_id text NOT NULL,
  input_digest text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, cursor_id),
  FOREIGN KEY (organization_id, aggregate_id)
    REFERENCES control_plane_p3e_aggregates(organization_id, aggregate_id)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e_cursors_aggregate_idx
  ON control_plane_p3e_cursors
    (organization_id, aggregate_id, cursor_id);
