-- Hyfens P3E5-4A automatic-halt policy/principal foundation migration 007.
-- The executable copy is p3e5PostgresMigration007 in Dart and runs under the
-- existing advisory migration lock. This migration contains no halt
-- application or rollout mutation SQL.

CREATE TABLE IF NOT EXISTS control_plane_p3e5_auto_halt_policies (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  policy_id text NOT NULL,
  policy_digest text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, policy_id),
  UNIQUE (organization_id, application_id, environment_id, policy_digest)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e5_auto_halt_policy_scope_idx
  ON control_plane_p3e5_auto_halt_policies
    (organization_id, application_id, environment_id, policy_id);

CREATE TABLE IF NOT EXISTS control_plane_p3e5_auto_halt_states (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  state_id text NOT NULL,
  generation bigint NOT NULL CHECK (generation > 0),
  supersedes_state_id text,
  policy_id text NOT NULL,
  policy_digest text NOT NULL,
  policy_approved boolean NOT NULL DEFAULT false,
  production_enabled boolean NOT NULL DEFAULT false,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, state_id),
  UNIQUE (organization_id, application_id, environment_id, generation),
  FOREIGN KEY (organization_id, policy_id)
    REFERENCES control_plane_p3e5_auto_halt_policies
      (organization_id, policy_id)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e5_auto_halt_state_scope_idx
  ON control_plane_p3e5_auto_halt_states
    (organization_id, application_id, environment_id, generation DESC);
