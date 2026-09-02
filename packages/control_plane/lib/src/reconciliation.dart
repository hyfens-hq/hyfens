final class ArtifactReconciliationItem {
  const ArtifactReconciliationItem({
    required this.status,
    required this.artifactId,
    required this.digest,
    this.detail,
  });

  final String status;
  final String? artifactId;
  final String? digest;
  final String? detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    if (artifactId != null) 'artifactId': artifactId,
    if (digest != null) 'digest': digest,
    if (detail != null) 'detail': detail,
  };
}

final class ArtifactReconciliationReport {
  const ArtifactReconciliationReport({
    required this.items,
    required this.inventoryAvailable,
    required this.quarantinedCount,
  });

  final List<ArtifactReconciliationItem> items;
  final bool inventoryAvailable;
  final int quarantinedCount;

  bool get deliverable => items.every(
    (item) => item.status == 'verified' || item.status == 'non_ready',
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'inventoryAvailable': inventoryAvailable,
    'quarantinedCount': quarantinedCount,
    'deliverable': deliverable,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };
}
