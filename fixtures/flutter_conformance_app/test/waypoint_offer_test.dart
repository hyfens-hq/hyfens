import 'package:conformance/waypoint/domain/waypoint_offer.dart';
import 'package:test/test.dart';

void main() {
  group('WaypointOffer.isActive', () {
    final expiresAt = DateTime.utc(2027, 5, 10, 12);
    final offer = _offer(expiresAt);

    test('returns true before expiry', () {
      expect(
        offer.isActive(expiresAt.subtract(const Duration(microseconds: 1))),
        isTrue,
      );
    });

    test('returns false at the exact expiry time', () {
      expect(offer.isActive(expiresAt), isFalse);
    });

    test('returns false after expiry', () {
      expect(
        offer.isActive(expiresAt.add(const Duration(microseconds: 1))),
        isFalse,
      );
    });
  });
}

WaypointOffer _offer(DateTime expiresAt) => WaypointOffer(
  id: 'test-offer',
  title: 'Test offer',
  message: 'Test message',
  actionLabel: 'Test action',
  expiresAt: expiresAt,
  accentColor: '#B9DED2',
);
