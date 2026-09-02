import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/waypoint_providers.dart';
import '../../application/waypoint_ui_state.dart';
import '../../data/waypoint_asset_paths.dart';
import '../../domain/waypoint_home_data.dart';
import '../../domain/waypoint_permission_action.dart';
import '../../domain/waypoint_test_action.dart';
import '../../platform/waypoint_permission.dart';
import '../widgets/waypoint_note_sheet.dart';
import '../widgets/waypoint_permission_row.dart';
import '../widgets/waypoint_planning_sheet.dart';
import '../widgets/waypoint_section_header.dart';
import '../widgets/waypoint_surface.dart';
import '../widgets/waypoint_video_preview.dart';

final class WaypointSettingsPage extends ConsumerStatefulWidget {
  const WaypointSettingsPage({super.key, required this.data});

  final WaypointHomeData data;

  @override
  ConsumerState<WaypointSettingsPage> createState() =>
      _WaypointSettingsPageState();
}

final class _WaypointSettingsPageState
    extends ConsumerState<WaypointSettingsPage> {
  bool _showMediaPreview = false;
  bool _noteSaved = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(waypointPermissionProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(waypointUiProvider);
    final permissions = ref.watch(waypointPermissionProvider);
    final repository = ref.watch(waypointRepositoryProvider);
    final shareTripNoteAction = _shareTripNoteAction;
    return SingleChildScrollView(
      key: const ValueKey<String>('waypoint-settings-page'),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const WaypointSectionHeader(
                title: 'Settings for the test run.',
                description: 'Keep the main journey calm. Put device and transport checks here.',
              ),
              const SizedBox(height: 22),
              WaypointSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<WaypointThemeChoice>(
                      key: const ValueKey<String>('waypoint-theme-choice'),
                      segments: const <ButtonSegment<WaypointThemeChoice>>[
                        ButtonSegment(
                          value: WaypointThemeChoice.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_outlined),
                        ),
                        ButtonSegment(
                          value: WaypointThemeChoice.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: WaypointThemeChoice.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_outlined),
                        ),
                      ],
                      selected: <WaypointThemeChoice>{ui.themeChoice},
                      onSelectionChanged: (selection) => ref
                          .read(waypointUiProvider.notifier)
                          .setThemeChoice(selection.first),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              WaypointSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Device permissions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Each action requests one permission and displays the platform result. A denial is a valid observation.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    for (final permission in WaypointPermission.values)
                      WaypointPermissionRow(
                        permission: permission,
                        permissionAction: _permissionActionFor(permission),
                        result: permissions.forPermission(permission),
                        onRequest: () async {
                          final result = permissions.forPermission(permission);
                          if (result?.status ==
                              WaypointPermissionStatus.permanentlyDenied) {
                            await ref
                                .read(waypointPermissionProvider.notifier)
                                .openAppSettings();
                          } else {
                            await ref
                                .read(waypointPermissionProvider.notifier)
                                .request(permission);
                          }
                        },
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey<String>(
                        'waypoint-permission-refresh',
                      ),
                      onPressed: () => ref
                          .read(waypointPermissionProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh permission status'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              WaypointSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Test actions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'These controls are intentionally kept out of the primary journey.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        FilledButton.tonalIcon(
                          key: const ValueKey<String>(
                            'waypoint-settings-reload',
                          ),
                          onPressed: () =>
                              ref.read(waypointHomeProvider.notifier).reload(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reload demo data'),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey<String>('waypoint-settings-plan'),
                          onPressed: () => showWaypointPlanningSheet(context),
                          icon: const Icon(Icons.event_note_outlined),
                          label: const Text('Open planning form'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey<String>(
                            'waypoint-settings-show-offer',
                          ),
                          onPressed: () => ref
                              .read(waypointUiProvider.notifier)
                              .restoreOffer(),
                          icon: const Icon(Icons.campaign_outlined),
                          label: const Text('Show banner'),
                        ),
                      ],
                    ),
                    if (shareTripNoteAction != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        shareTripNoteAction.title,
                        key: const ValueKey<String>(
                          'waypoint-settings-share-trip-note-title',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        shareTripNoteAction.subtitle,
                        key: const ValueKey<String>(
                          'waypoint-settings-share-trip-note-subtitle',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const ValueKey<String>(
                          'waypoint-settings-share-trip-note',
                        ),
                        onPressed: () => showWaypointNoteSheet(
                          context,
                          action: shareTripNoteAction,
                          onSaved: () {
                            if (mounted) {
                              setState(() => _noteSaved = true);
                            }
                          },
                        ),
                        icon: const Icon(Icons.edit_note_outlined),
                        label: Text(shareTripNoteAction.title),
                      ),
                      if (_noteSaved) ...<Widget>[
                        const SizedBox(height: 8),
                        const Text(
                          'Note saved for this session.',
                          key: ValueKey<String>('waypoint-note-saved'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Data mode: ${repository.modeLabel}  |  Transport: ${repository.transportLabel}',
                      key: const ValueKey<String>('waypoint-data-mode'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Local mode reads ${WaypointAssetPaths.homeJson}. Network mode is explicit and uses AlphaX native transport.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              WaypointSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Asset checks',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'The visible sample below exercises the bundled font family and the local video asset.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Waypoint Sans sample',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey<String>('waypoint-settings-media'),
                      onPressed: () => setState(
                        () => _showMediaPreview = !_showMediaPreview,
                      ),
                      icon: Icon(
                        _showMediaPreview
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      label: Text(
                        _showMediaPreview
                            ? 'Hide video preview'
                            : 'Test video asset',
                      ),
                    ),
                    if (_showMediaPreview) ...<Widget>[
                      const SizedBox(height: 14),
                      const WaypointVideoPreview(),
                    ],
                  ],
                ),
              ),
              if (widget.data.offer != null &&
                  ui.dismissedOfferId != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'The offer is currently dismissed. Use Show banner to test it again.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  WaypointTestAction? get _shareTripNoteAction {
    for (final action in widget.data.actions) {
      if (action.id == 'share_trip_note' && action.noteField != null) {
        return action;
      }
    }
    return null;
  }

  WaypointPermissionAction? _permissionActionFor(
    WaypointPermission permission,
  ) {
    for (final action in widget.data.permissionActions) {
      if (action.id == permission.name) {
        return action;
      }
    }
    return null;
  }
}
