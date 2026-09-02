import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/waypoint_providers.dart';
import '../../application/waypoint_ui_state.dart';
import '../widgets/waypoint_logo.dart';

final class WaypointShellHeader extends ConsumerWidget {
  const WaypointShellHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
    child: Row(
      children: <Widget>[
        const WaypointLogo(compact: true),
        const Spacer(),
        IconButton(
          key: const ValueKey<String>('waypoint-header-settings'),
          tooltip: 'Open settings',
          onPressed: () => ref
              .read(waypointUiProvider.notifier)
              .selectSection(WaypointSection.settings),
          icon: const Icon(Icons.tune_rounded),
        ),
        const SizedBox(width: 4),
        CircleAvatar(
          radius: 19,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Text('AR', style: Theme.of(context).textTheme.labelLarge),
        ),
      ],
    ),
  );
}
