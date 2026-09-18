-- Hyfens P3E5-2 bounded cooperative-claim migration 006.
-- The executable copy is p3e5PostgresMigration006 in Dart and runs under the
-- existing control-plane advisory migration lock.

ALTER TABLE control_plane_p3e5_work
  ADD COLUMN IF NOT EXISTS not_before timestamptz;

ALTER TABLE control_plane_p3e5_work
  ADD COLUMN IF NOT EXISTS lease_expires_at timestamptz;

UPDATE control_plane_p3e5_work
  SET not_before = (body->>'notBefore')::timestamptz
  WHERE not_before IS NULL;

UPDATE control_plane_p3e5_work
  SET lease_expires_at = (body->>'leaseExpiresAt')::timestamptz
  WHERE lease_expires_at IS NULL AND body->>'leaseExpiresAt' IS NOT NULL;

ALTER TABLE control_plane_p3e5_work
  ALTER COLUMN not_before SET NOT NULL;

CREATE INDEX IF NOT EXISTS control_plane_p3e5_work_claim_idx
  ON control_plane_p3e5_work
    (organization_id, application_id, environment_id, status,
     not_before, lease_expires_at, created_at, work_id);
