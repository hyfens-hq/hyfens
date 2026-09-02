import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/waypoint_providers.dart';
import '../application/waypoint_ui_state.dart';
import '../domain/waypoint_home_data.dart';
import 'navigation/waypoint_bottom_navigation.dart';
import 'navigation/waypoint_navigation_rail.dart';
import 'navigation/waypoint_shell_header.dart';
import 'screens/waypoint_activity_page.dart';
import 'screens/waypoint_discover_page.dart';
import 'screens/waypoint_saved_page.dart';
import 'screens/waypoint_settings_page.dart';
import 'screens/waypoint_trips_page.dart';
import 'waypoint_theme.dart';
import 'widgets/waypoint_logo.dart';
import 'widgets/waypoint_skeleton.dart';

const _wideLayoutBreakpoint = 900.0;

final class WaypointApp extends ConsumerWidget {
  const WaypointApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeChoice = ref.watch(waypointUiProvider).themeChoice;
    return MaterialApp(
      title: 'Waypoint',
      debugShowCheckedModeBanner: false,
      theme: waypointTheme(Brightness.light),
      darkTheme: waypointTheme(Brightness.dark),
      themeMode: waypointThemeMode(themeChoice),
      home: const WaypointShell(),
    );
  }
}

final class WaypointShell extends ConsumerWidget {
  const WaypointShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(waypointUiProvider);
    final home = ref.watch(waypointHomeProvider);
    final mediaQuery = MediaQuery.of(context);
    final availableWidth =
        mediaQuery.size.width - mediaQuery.padding.horizontal;
    final wide = availableWidth >= _wideLayoutBreakpoint;
    final content = Column(
      children: <Widget>[
        if (!wide) const WaypointShellHeader(),
        if (ui.lastAction != null) _ActionMessage(message: ui.lastAction!),
        Expanded(
          child: home.when(
            loading: () => const WaypointLoadingPage(),
            error: (error, stackTrace) => _WaypointErrorPage(
              error: error,
              onRetry: () => ref.read(waypointHomeProvider.notifier).reload(),
            ),
            data: (data) => _WaypointPageBody(data: data),
          ),
        ),
      ],
    );
    return Scaffold(
      key: const ValueKey<String>('waypoint-shell'),
      body: SafeArea(
        child: wide
            ? Row(
                children: <Widget>[
                  const WaypointNavigationRail(),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
      bottomNavigationBar: wide ? null : const WaypointBottomNavigation(),
    );
  }
}

final class _WaypointPageBody extends ConsumerWidget {
  const _WaypointPageBody({required this.data});

  final WaypointHomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(waypointUiProvider).section;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: switch (section) {
        WaypointSection.discover => WaypointDiscoverPage(data: data),
        WaypointSection.trips => WaypointTripsPage(data: data),
        WaypointSection.saved => WaypointSavedPage(data: data),
        WaypointSection.activity => WaypointActivityPage(data: data),
        WaypointSection.settings => WaypointSettingsPage(data: data),
      },
    );
  }
}

final class _ActionMessage extends StatelessWidget {
  const _ActionMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
    child: Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.check_circle_outline_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
}

final class WaypointLoadingPage extends StatelessWidget {
  const WaypointLoadingPage({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 44),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const WaypointSkeletonBox(width: 150, height: 16),
            const SizedBox(height: 12),
            const WaypointSkeletonBox(width: 310, height: 38),
            const SizedBox(height: 26),
            const WaypointSkeletonBox(height: 52, width: double.infinity),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisExtent: 270,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemBuilder: (context, index) =>
                    const WaypointDestinationSkeleton(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _WaypointErrorPage extends StatelessWidget {
  const _WaypointErrorPage({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const WaypointLogo(),
          const SizedBox(height: 22),
          Text(
            'Waypoint could not load this view.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'The configured data source reported an error. Demo and network failures remain visible.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey<String>('waypoint-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
          const SizedBox(height: 10),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    ),
  );
}
