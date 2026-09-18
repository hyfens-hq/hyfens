-- Hyfens control-plane observations migration 002.
-- Observation records are append-only, tenant scoped, and separate from
-- rollout, audit, artifact, and runtime-trust records.
CREATE TABLE IF NOT EXISTS control_plane_observations (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  event_id text NOT NULL,
  event_type text NOT NULL,
  release_id text NOT NULL,
  patch_id text,
  sequence bigint,
  rollout_id text,
  rollout_revision bigint,
  received_at timestamptz NOT NULL,
  body jsonb NOT NULL,
  PRIMARY KEY (organization_id, application_id, environment_id, event_id)
);

CREATE INDEX IF NOT EXISTS control_plane_observations_scope_idx
  ON control_plane_observations
    (organization_id, application_id, environment_id, received_at);

CREATE INDEX IF NOT EXISTS control_plane_observations_event_type_idx
  ON control_plane_observations
    (organization_id, application_id, environment_id, event_type, received_at);
