import 'package:conformance/waypoint/application/waypoint_providers.dart';
import 'package:conformance/waypoint/domain/waypoint_plan_request.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test/test.dart';

void main() {
  group('WaypointPlanRequest validity', () {
    test('rejects a whitespace-only destination', () {
      final request = _request(destination: ' \t\n ');

      expect(request.isValid, isFalse);
    });

    test('rejects an end date before the start date', () {
      final request = _request(
        startDate: DateTime(2027, 5, 10),
        endDate: DateTime(2027, 5, 9),
      );

      expect(request.isValid, isFalse);
    });

    test('requires at least one traveler', () {
      expect(_request(travelers: 0).isValid, isFalse);
      expect(_request(travelers: 1).isValid, isTrue);
    });

    test('accepts a destination with ordered dates and travelers', () {
      final request = _request(
        destination: 'Kyoto',
        startDate: DateTime(2027, 5, 10),
        endDate: DateTime(2027, 5, 14),
        travelers: 2,
      );

      expect(request.isValid, isTrue);
    });
  });

  group('WaypointPlannerNotifier state rules', () {
    test('moves the end date after a later start date', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(waypointPlannerProvider.notifier);
      final nextStart = container
          .read(waypointPlannerProvider)
          .endDate
          .add(const Duration(days: 2));

      notifier.setStartDate(nextStart);

      final state = container.read(waypointPlannerProvider);
      expect(state.startDate, nextStart);
      expect(state.endDate, nextStart.add(const Duration(days: 1)));
    });

    test('does not decrement travelers below one and can increment again', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(waypointPlannerProvider.notifier);

      notifier.decrementTravelers();
      expect(container.read(waypointPlannerProvider).travelers, 1);

      notifier.decrementTravelers();
      expect(container.read(waypointPlannerProvider).travelers, 1);

      notifier.incrementTravelers();
      expect(container.read(waypointPlannerProvider).travelers, 2);
    });

    test('updates the selected travel style', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(waypointPlannerProvider.notifier);

      notifier.setTravelStyle('Curious');

      expect(container.read(waypointPlannerProvider).travelStyle, 'Curious');
    });
  });
}

WaypointPlanRequest _request({
  String destination = 'Lisbon',
  DateTime? startDate,
  DateTime? endDate,
  int travelers = 2,
}) => WaypointPlanRequest(
  destination: destination,
  startDate: startDate ?? DateTime(2027, 5, 10),
  endDate: endDate ?? DateTime(2027, 5, 14),
  travelers: travelers,
  travelStyle: 'Unhurried',
);
