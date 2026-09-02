/// Boundaries at which a PostgreSQL integration test may close its pool.
///
/// This is a test-only seam. Production constructors leave the injector null,
/// so normal transaction, CAS, and reconnect behavior are unchanged. A fault
/// is one-shot by convention in tests; recovery is explicit store recreation,
/// not an internal retry loop.
enum PostgresDisconnectPoint {
  findingCommitBefore,
  findingCommitAfter,
  repairAttemptCommitBefore,
  repairAttemptCommitAfter,
  lifecycleCommitBefore,
  lifecycleCommitAfter,
  cursorCommitBefore,
  cursorCommitAfter,
  projectionCommitBefore,
  projectionCommitAfter,
  postconditionReadBefore,
  auditReadBefore,
  auditCommitBefore,
  auditCommitAfter,
}

/// Returns true when the store should close its actual PostgreSQL pool at the
/// requested boundary and surface a bounded connection-loss failure.
typedef PostgresDisconnectInjector = bool Function(
  PostgresDisconnectPoint point,
);
