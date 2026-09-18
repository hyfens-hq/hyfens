CREATE TABLE IF NOT EXISTS control_plane_p3e_halt_applications (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  decision_id text NOT NULL,
  evaluation_id text NOT NULL,
  aggregate_revision_id text NOT NULL,
  rollout_id text NOT NULL,
  expected_rollout_revision bigint NOT NULL CHECK (expected_rollout_revision > 0),
  result text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, application_id),
  FOREIGN KEY (organization_id, decision_id)
    REFERENCES control_plane_p3e_decisions(organization_id, decision_id),
  FOREIGN KEY (organization_id, evaluation_id)
    REFERENCES control_plane_p3e_evaluations(organization_id, evaluation_id),
  FOREIGN KEY (organization_id, aggregate_revision_id)
    REFERENCES control_plane_p3e_aggregate_revisions
      (organization_id, aggregate_revision_id)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e_halt_applications_decision_idx
  ON control_plane_p3e_halt_applications
    (organization_id, decision_id, created_at, application_id);
