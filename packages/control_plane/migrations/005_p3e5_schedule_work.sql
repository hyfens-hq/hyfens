-- Hyfens P3E5-1 schedule/work persistence migration 005.
-- The executable copy is p3e5PostgresMigration005 in Dart and runs under the
-- existing control-plane advisory migration lock.

CREATE TABLE IF NOT EXISTS control_plane_p3e5_schedules (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  rollout_id text NOT NULL,
  schedule_id text NOT NULL,
  current_schedule_revision_id text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, schedule_id)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e5_schedules_scope_idx
  ON control_plane_p3e5_schedules
    (organization_id, application_id, environment_id, rollout_id, schedule_id);

CREATE TABLE IF NOT EXISTS control_plane_p3e5_schedule_revisions (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  rollout_id text NOT NULL,
  schedule_id text NOT NULL,
  schedule_revision_id text NOT NULL,
  schedule_generation bigint NOT NULL CHECK (schedule_generation > 0),
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, schedule_revision_id),
  UNIQUE (organization_id, schedule_id, schedule_generation),
  FOREIGN KEY (organization_id, schedule_id)
    REFERENCES control_plane_p3e5_schedules(organization_id, schedule_id)
    DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX IF NOT EXISTS control_plane_p3e5_revisions_schedule_idx
  ON control_plane_p3e5_schedule_revisions
    (organization_id, schedule_id, schedule_generation);

CREATE TABLE IF NOT EXISTS control_plane_p3e5_work (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  rollout_id text NOT NULL,
  schedule_id text NOT NULL,
  schedule_revision_id text NOT NULL,
  work_id text NOT NULL,
  logical_key_digest text NOT NULL,
  status text NOT NULL,
  work_version bigint NOT NULL CHECK (work_version >= 0),
  attempt_count bigint NOT NULL CHECK (attempt_count >= 0),
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, work_id),
  UNIQUE (organization_id, logical_key_digest),
  FOREIGN KEY (organization_id, schedule_revision_id)
    REFERENCES control_plane_p3e5_schedule_revisions
      (organization_id, schedule_revision_id)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e5_work_scope_idx
  ON control_plane_p3e5_work
    (organization_id, application_id, environment_id, rollout_id, work_id);

CREATE TABLE IF NOT EXISTS control_plane_p3e5_attempts (
  organization_id text NOT NULL,
  work_id text NOT NULL,
  attempt_id text NOT NULL,
  attempt_number bigint NOT NULL CHECK (attempt_number > 0),
  body jsonb NOT NULL,
  started_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, attempt_id),
  UNIQUE (organization_id, work_id, attempt_number),
  FOREIGN KEY (organization_id, work_id)
    REFERENCES control_plane_p3e5_work(organization_id, work_id)
);

CREATE INDEX IF NOT EXISTS control_plane_p3e5_attempts_work_idx
  ON control_plane_p3e5_attempts
    (organization_id, work_id, attempt_number);
