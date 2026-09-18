import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/waypoint_planner_notifier.dart';
import '../../application/waypoint_planner_state.dart';
import '../../application/waypoint_providers.dart';
import '../../domain/waypoint_planner_field.dart';
import '../../domain/waypoint_test_action.dart';

const _defaultTravelers = 2;
const _minimumTravelers = 1;

Future<void> showWaypointPlanningSheet(
  BuildContext context, {
  String initialDestination = '',
  WaypointTestAction? action,
}) {
  if (initialDestination.isEmpty) {
    final travelerField = _plannerField(
      action,
      id: 'travellers',
      type: 'stepper',
    );
    final travelerConfiguration = _travelerConfiguration(travelerField);
    ProviderScope.containerOf(context, listen: false)
        .read(waypointPlannerProvider.notifier)
        .resetForNewEntry(
          initialTravelers: travelerConfiguration.initialTravelers,
        );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => WaypointPlanningSheet(
      initialDestination: initialDestination,
      action: action,
    ),
  );
}

final class WaypointPlanningSheet extends ConsumerStatefulWidget {
  const WaypointPlanningSheet({
    super.key,
    this.initialDestination = '',
    this.action,
  });

  final String initialDestination;
  final WaypointTestAction? action;

  @override
  ConsumerState<WaypointPlanningSheet> createState() =>
      _WaypointPlanningSheetState();
}

final class _WaypointPlanningSheetState
    extends ConsumerState<WaypointPlanningSheet> {
  late final TextEditingController _destinationController;

  @override
  void initState() {
    super.initState();
    _destinationController = TextEditingController(
      text: widget.initialDestination,
    );
    if (widget.initialDestination.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref
            .read(waypointPlannerProvider.notifier)
            .setDestination(widget.initialDestination);
      });
    }
  }

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(waypointPlannerProvider);
    final notifier = ref.read(waypointPlannerProvider.notifier);
    final action = widget.action;
    final destinationField = _plannerField(
      action,
      id: 'destination',
      type: 'text',
    );
    final dateField = _plannerField(action, id: 'dates', type: 'date_range');
    final travelerField = _plannerField(
      action,
      id: 'travellers',
      type: 'stepper',
    );
    final travelerConfiguration = _travelerConfiguration(travelerField);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                action?.title ?? 'Shape a small escape',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                action?.subtitle ?? 'Start with a place and a pace. This local brief stays on the device.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 22),
              Text(
                destinationField?.label ?? 'Destination',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 7),
              TextField(
                key: const ValueKey<String>('waypoint-plan-destination'),
                controller: _destinationController,
                onChanged: notifier.setDestination,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText:
                      destinationField?.placeholder ??
                      'Kyoto, Lisbon, or somewhere new',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                dateField?.label ?? 'Dates',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 7),
              _DateRangeButton(state: state, onChanged: notifier),
              const SizedBox(height: 16),
              _TravelerField(
                state: state,
                notifier: notifier,
                label: travelerField?.label ?? 'Travelers',
                minimumTravelers: travelerConfiguration.minimumTravelers,
                maximumTravelers: travelerConfiguration.maximumTravelers,
              ),
              const SizedBox(height: 16),
              Text(
                'Travel style',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 7),
              DropdownButtonFormField<String>(
                key: const ValueKey<String>('waypoint-plan-style'),
                initialValue: state.travelStyle,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.tune_rounded),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'Unhurried',
                    child: Text('Unhurried'),
                  ),
                  DropdownMenuItem(
                    value: 'Curious',
                    child: Text('Curious and local'),
                  ),
                  DropdownMenuItem(
                    value: 'Outdoors',
                    child: Text('Outdoors first'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    notifier.setTravelStyle(value);
                  }
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey<String>('waypoint-plan-submit'),
                  onPressed: state.isValid
                      ? () {
                          notifier.submit();
                          Navigator.of(context).pop();
                        }
                      : null,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(action?.submitLabel ?? 'Create planning brief'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({required this.state, required this.onChanged});

  final WaypointPlannerState state;
  final WaypointPlannerNotifier onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      key: const ValueKey<String>('waypoint-plan-dates'),
      onPressed: () async {
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 730)),
          initialDateRange: DateTimeRange(
            start: state.startDate,
            end: state.endDate,
          ),
        );
        if (range != null) {
          onChanged.setStartDate(range.start);
          onChanged.setEndDate(range.end);
        }
      },
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text(
        '${_date(context, state.startDate)}  to  ${_date(context, state.endDate)}',
      ),
    ),
  );

  String _date(BuildContext context, DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value);
}

final class _TravelerField extends StatelessWidget {
  const _TravelerField({
    required this.state,
    required this.notifier,
    required this.label,
    required this.minimumTravelers,
    this.maximumTravelers,
  });

  final WaypointPlannerState state;
  final WaypointPlannerNotifier notifier;
  final String label;
  final int minimumTravelers;
  final int? maximumTravelers;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
      IconButton.outlined(
        key: const ValueKey<String>('waypoint-plan-travelers-decrease'),
        onPressed: state.travelers > minimumTravelers
            ? () => notifier.decrementTravelers(
                minimumTravelers: minimumTravelers,
              )
            : null,
        icon: const Icon(Icons.remove_rounded),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          '${state.travelers}',
          key: const ValueKey<String>('waypoint-plan-travelers'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      IconButton.outlined(
        key: const ValueKey<String>('waypoint-plan-travelers-increase'),
        onPressed:
            maximumTravelers == null || state.travelers < maximumTravelers!
            ? () => notifier.incrementTravelers(maxTravelers: maximumTravelers)
            : null,
        icon: const Icon(Icons.add_rounded),
      ),
    ],
  );
}

WaypointPlannerField? _plannerField(
  WaypointTestAction? action, {
  required String id,
  required String type,
}) {
  if (!_isValidatedPlannerAction(action)) {
    return null;
  }
  for (final field in action!.plannerFields) {
    if (field.id == id && field.type == type && field.label.trim().isNotEmpty) {
      return field;
    }
  }
  return null;
}

bool _isValidatedPlannerAction(WaypointTestAction? action) =>
    action != null &&
    action.id == 'open_planner' &&
    action.type == 'bottom_sheet' &&
    action.title.trim().isNotEmpty &&
    action.subtitle.trim().isNotEmpty &&
    action.submitLabel.trim().isNotEmpty;

({int initialTravelers, int minimumTravelers, int? maximumTravelers})
_travelerConfiguration(WaypointPlannerField? field) {
  final initialValue = field?.initialValue;
  final minimumTravelers = field?.min;
  final maximumTravelers = field?.max;
  if (initialValue == null ||
      minimumTravelers == null ||
      maximumTravelers == null ||
      minimumTravelers < _minimumTravelers ||
      maximumTravelers < minimumTravelers ||
      initialValue < minimumTravelers ||
      initialValue > maximumTravelers) {
    return (
      initialTravelers: _defaultTravelers,
      minimumTravelers: _minimumTravelers,
      maximumTravelers: null,
    );
  }
  return (
    initialTravelers: initialValue,
    minimumTravelers: minimumTravelers,
    maximumTravelers: maximumTravelers,
  );
}
