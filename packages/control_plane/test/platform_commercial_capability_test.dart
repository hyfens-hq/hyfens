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
      ]),
    );

    expect(
      managedPlatformStaffRoleCapabilities['admin'],
      containsAll(<String>[
        platformCommercialReadCapability,
        platformPlansLegalReviewCapability,
      ]),
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
