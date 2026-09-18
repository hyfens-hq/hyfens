import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  test('commercial catalog capabilities are explicit and role-scoped', () {
    expect(
      platformCapabilities,
      containsAll(<String>[
        platformCommercialReadCapability,
        platformPlansPublishCapability,
        platformPlansLegalReviewCapability,
        platformManagedBackupReadCapability,
        platformManagedBackupOperateCapability,
        platformManagedBackupConfigureCapability,
        platformManagedBackupRotateCapability,
        platformManagedBackupRestoreCheckCapability,
      ]),
    );

    expect(
      managedPlatformStaffRoleCapabilities['admin'],
      containsAll(<String>[
        platformCommercialReadCapability,
        platformPlansLegalReviewCapability,
        platformManagedBackupReadCapability,
        platformManagedBackupOperateCapability,
        platformManagedBackupConfigureCapability,
      ]),
    );
    expect(
      managedPlatformStaffRoleCapabilities['admin'],
      isNot(contains(platformManagedBackupRotateCapability)),
    );
    expect(
      managedPlatformStaffRoleCapabilities['admin'],
      isNot(contains(platformManagedBackupRestoreCheckCapability)),
    );
    expect(
      managedPlatformStaffRoleCapabilities['commercial'],
      contains(platformCommercialReadCapability),
    );
    expect(
      managedPlatformStaffRoleCapabilities['commercial'],
      isNot(contains(platformPlansLegalReviewCapability)),
    );
  });
}
