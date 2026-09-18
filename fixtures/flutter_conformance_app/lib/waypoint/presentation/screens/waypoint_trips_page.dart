import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/waypoint_providers.dart';
import '../../domain/waypoint_home_data.dart';
import '../../domain/waypoint_itinerary_item.dart';
import '../../domain/waypoint_trip.dart';
import '../widgets/waypoint_planning_sheet.dart';
import '../widgets/waypoint_section_header.dart';
import '../widgets/waypoint_surface.dart';
import '../widgets/waypoint_trip_card.dart';

final class WaypointTripsPage extends ConsumerWidget {
  const WaypointTripsPage({super.key, required this.data});

  final WaypointHomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.trips.isEmpty) {
      return _EmptyTrips(onPlan: () => showWaypointPlanningSheet(context));
    }
    final trip = data.trips.first;
    final additionalTrips = data.trips.skip(1);
    return SingleChildScrollView(
      key: const ValueKey<String>('waypoint-trips-page'),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              WaypointSectionHeader(
                title: 'Trips with room to wander.',
                description: 'Keep the essentials together, then leave space for the good surprises.',
                action: FilledButton.icon(
                  key: const ValueKey<String>('waypoint-plan-cta'),
                  onPressed: () => showWaypointPlanningSheet(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Plan a trip'),
                ),
              ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final primary = SizedBox(
                    height: 368,
                    child: WaypointTripCard(
                      trip: trip,
                      onTap: () => _showTrip(context, trip),
                    ),
                  );
                  final pulse = _PlanPulse(trip: trip);
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(flex: 6, child: primary),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: pulse),
                          ],
                        )
                      : Column(
                          children: <Widget>[
                            primary,
                            const SizedBox(height: 16),
                            pulse,
                          ],
                        );
                },
              ),
              const SizedBox(height: 28),
              Text(
                'Your next stops',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              WaypointSurface(
                child: Column(
                  children: <Widget>[
                    for (var index = 0; index < trip.itinerary.length; index++)
                      _ItineraryRow(
                        item: trip.itinerary[index],
                        isLast: index == trip.itinerary.length - 1,
                      ),
                  ],
                ),
              ),
              if (additionalTrips.isNotEmpty) ...<Widget>[
                const SizedBox(height: 28),
                Text(
                  'More trips',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth >= 760
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: <Widget>[
                        for (final additionalTrip in additionalTrips)
                          SizedBox(
                            width: cardWidth,
                            height: 368,
                            child: WaypointTripCard(
                              trip: additionalTrip,
                              onTap: () => _showTrip(context, additionalTrip),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (ref.watch(waypointUiProvider).planSubmitted) ...<Widget>[
                const SizedBox(height: 16),
                const WaypointSurface(
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.check_circle_outline_rounded),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your new planning brief is ready for the next step.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTrip(BuildContext context, WaypointTrip trip) {
    final checklistDone = <bool>[
      for (final item in trip.checklist) item.isComplete,
    ];
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    trip.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trip.destination,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  for (var index = 0; index < trip.itinerary.length; index++)
                    ListTile(
                      key: ValueKey<String>(
                        'waypoint-trip-itinerary-${trip.id}-$index',
                      ),
                      contentPadding: EdgeInsets.zero,
                      leading: Text(trip.itinerary[index].timeLabel),
                      title: Text(trip.itinerary[index].title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(trip.itinerary[index].detail),
                          const SizedBox(height: 4),
                          Chip(
                            key: ValueKey<String>(
                              'waypoint-trip-itinerary-category-${trip.id}-$index',
                            ),
                            label: Text(trip.itinerary[index].category),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      trailing: Semantics(
                        container: true,
                        label: trip.itinerary[index].isComplete
                            ? 'Complete'
                            : 'Incomplete',
                        child: Icon(
                          trip.itinerary[index].isComplete
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          key: ValueKey<String>(
                            'waypoint-trip-itinerary-status-${trip.id}-$index',
                          ),
                          color: trip.itinerary[index].isComplete
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  if (trip.checklist.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 18),
                    WaypointSurface(
                      key: ValueKey<String>(
                        'waypoint-trip-checklist-${trip.id}',
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Before you go',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          for (
                            var index = 0;
                            index < trip.checklist.length;
                            index++
                          )
                            CheckboxListTile(
                              key: ValueKey<String>(
                                'waypoint-trip-checklist-item-${trip.id}-$index',
                              ),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: checklistDone[index],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() => checklistDone[index] = value);
                              },
                              title: Text(trip.checklist[index].title),
                              subtitle: trip.checklist[index].detail == null
                                  ? null
                                  : Text(trip.checklist[index].detail!),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (trip.documents.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 18),
                    WaypointSurface(
                      key: ValueKey<String>(
                        'waypoint-trip-documents-${trip.id}',
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Documents',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          for (final document in trip.documents)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(_documentIcon(document.icon)),
                              title: Text(document.name),
                              subtitle: Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: <Widget>[
                                  Text(document.kind),
                                  const Text('•'),
                                  Text(document.sizeLabel),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey<String>('waypoint-trip-plan'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        showWaypointPlanningSheet(
                          context,
                          initialDestination: trip.destination,
                        );
                      },
                      child: const Text('Adjust this plan'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _documentIcon(String? icon) => switch (icon) {
  'route' => Icons.route_outlined,
  'note' => Icons.note_outlined,
  _ => Icons.description_outlined,
};

final class _PlanPulse extends StatelessWidget {
  const _PlanPulse({required this.trip});

  final WaypointTrip trip;

  @override
  Widget build(BuildContext context) => WaypointSurface(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.auto_awesome_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'The big decisions are done.',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 7),
        Text(
          'Your ${trip.destination} plan is taking shape. Keep one afternoon open.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 22),
        LinearProgressIndicator(
          value: trip.progress,
          minHeight: 9,
          borderRadius: BorderRadius.circular(9),
        ),
        const SizedBox(height: 9),
        Text(
          '${(trip.progress * 100).round()}% ready',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            _Metric(value: '${trip.completedItems}', label: 'ready'),
            const Spacer(),
            _Metric(value: '${trip.itinerary.length}', label: 'stops'),
            const Spacer(),
            _Metric(value: '${trip.checklist.length}', label: 'details'),
          ],
        ),
      ],
    ),
  );
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(value, style: Theme.of(context).textTheme.titleLarge),
      Text(label, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

final class _ItineraryRow extends StatelessWidget {
  const _ItineraryRow({required this.item, required this.isLast});

  final WaypointItineraryItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 54,
          child: Text(
            item.timeLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Container(
          width: 11,
          height: 11,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            color: item.isComplete
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(item.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(item.detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips({required this.onPlan});

  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: WaypointSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.luggage_outlined, size: 34),
            const SizedBox(height: 12),
            Text(
              'Your next trip starts here.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Create a planning brief to give the idea a shape.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey<String>('waypoint-trips-empty-plan'),
              onPressed: onPlan,
              child: const Text('Plan a trip'),
            ),
          ],
        ),
      ),
    ),
  );
}
