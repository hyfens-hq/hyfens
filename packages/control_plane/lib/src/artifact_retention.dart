import 'domain.dart';

const String artifactReadyState = 'READY';
const String artifactQuarantinedState = 'QUARANTINED';
const String artifactPurgedState = 'PURGED';

/// The lifecycle decision used by storage accounting, delivery, and cleanup.
///
/// READY artifacts have no automatic time-based expiry in the current product:
/// the existing release and rollback model does not yet provide a complete
/// deployment-history retention policy. QUARANTINED bytes are unavailable and
/// may become purgeable immediately, subject to pending bundle-import
/// protection. PURGED keeps the metadata record and historical evidence while
/// removing only the content-addressed bytes.
final class ArtifactRetentionDecision {
  const ArtifactRetentionDecision({
    required this.countsTowardLogicalStorage,
    required this.availableForDelivery,
    required this.availableForDeployment,
    required this.purgeEligible,
    required this.reason,
  });

  final bool countsTowardLogicalStorage;
  final bool availableForDelivery;
  final bool availableForDeployment;
  final bool purgeEligible;
  final String reason;
}

final class ArtifactRetentionPolicy {
  const ArtifactRetentionPolicy();

  ArtifactRetentionDecision evaluate(
    ArtifactRecord artifact, {
    required DateTime now,
    bool protectedByPendingBundleImport = false,
  }) {
    final normalizedNow = now.toUtc();
    final eligibleAt = artifact.purgeEligibleAt;
    final purgeEligible =
        artifact.state == artifactQuarantinedState &&
        !protectedByPendingBundleImport &&
        eligibleAt != null &&
        !eligibleAt.isAfter(normalizedNow);

    return switch (artifact.state) {
      artifactReadyState => const ArtifactRetentionDecision(
        countsTowardLogicalStorage: true,
        availableForDelivery: true,
        availableForDeployment: true,
        purgeEligible: false,
        reason: 'ready_without_time_based_expiry',
      ),
      artifactQuarantinedState => ArtifactRetentionDecision(
        countsTowardLogicalStorage: false,
        availableForDelivery: false,
        availableForDeployment: false,
        purgeEligible: purgeEligible,
        reason: protectedByPendingBundleImport
            ? 'pending_bundle_import'
            : purgeEligible
            ? 'quarantined_bytes_are_purgeable'
            : 'quarantined_bytes_awaiting_purge_eligibility',
      ),
      artifactPurgedState => const ArtifactRetentionDecision(
        countsTowardLogicalStorage: false,
        availableForDelivery: false,
        availableForDeployment: false,
        purgeEligible: false,
        reason: 'purged_bytes_metadata_retained',
      ),
      _ => const ArtifactRetentionDecision(
        countsTowardLogicalStorage: false,
        availableForDelivery: false,
        availableForDeployment: false,
        purgeEligible: false,
        reason: 'non_ready_artifact',
      ),
    };
  }
}

final class ArtifactRetentionCleanupItem {
  const ArtifactRetentionCleanupItem({
    required this.status,
    required this.artifactId,
    required this.digest,
    this.detail,
  });

  final String status;
  final String artifactId;
  final String digest;
  final String? detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'artifact_id': artifactId,
    'digest': digest,
    if (detail != null) 'detail': detail,
  };
}

final class ArtifactRetentionCleanupReport {
  const ArtifactRetentionCleanupReport({
    required this.managed,
    required this.deletionSupported,
    required this.consideredCount,
    required this.purgedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.items,
  });

  final bool managed;
  final bool deletionSupported;
  final int consideredCount;
  final int purgedCount;
  final int skippedCount;
  final int failedCount;
  final List<ArtifactRetentionCleanupItem> items;

  Map<String, Object?> toJson() => <String, Object?>{
    'managed': managed,
    'deletion_supported': deletionSupported,
    'considered_count': consideredCount,
    'purged_count': purgedCount,
    'skipped_count': skippedCount,
    'failed_count': failedCount,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };
}
