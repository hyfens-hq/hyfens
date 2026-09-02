import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/waypoint_providers.dart';
import '../../application/waypoint_ui_state.dart';
import '../../domain/waypoint_destination.dart';
import '../../domain/waypoint_discover_category.dart';
import '../../domain/waypoint_discover_collection.dart';
import '../../domain/waypoint_home_data.dart';
import '../../domain/waypoint_home_hero.dart';
import '../../domain/waypoint_test_action.dart';
import '../widgets/waypoint_asset_artwork.dart';
import '../widgets/waypoint_destination_card.dart';
import '../widgets/waypoint_offer_banner.dart';
import '../widgets/waypoint_planning_sheet.dart';
import '../widgets/waypoint_section_header.dart';
import '../widgets/waypoint_skeleton.dart';
import '../widgets/waypoint_surface.dart';
import '../widgets/waypoint_video_preview.dart';

final class WaypointDiscoverPage extends ConsumerStatefulWidget {
  const WaypointDiscoverPage({super.key, required this.data});

  final WaypointHomeData data;

  @override
  ConsumerState<WaypointDiscoverPage> createState() =>
      _WaypointDiscoverPageState();
}

final class _WaypointDiscoverPageState
    extends ConsumerState<WaypointDiscoverPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(waypointUiProvider).query,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(waypointUiProvider);
    final search = ref.watch(waypointSearchProvider);
    final greeting = widget.data.greeting;
    final discoverTitle = widget.data.discoverTitle;
    final hero = widget.data.hero;
    final categories = widget.data.categories;
    final collections = widget.data.collections;
    final searchSuggestions = widget.data.searchSuggestions;
    final offer = widget.data.offer;
    final plannerAction = _findOpenPlannerAction(widget.data.actions);
    final routePreviewAction = _findRoutePreviewAction(widget.data.actions);
    final videoAsset =
        routePreviewAction?.assetPath ??
        (_hasContent(hero?.videoAsset) ? hero?.videoAsset : null);
    WaypointDestination? selectedDestination;
    for (final destination in widget.data.destinations) {
      if (destination.id == ui.selectedDestinationId) {
        selectedDestination = destination;
        break;
      }
    }
    final showOffer =
        offer != null &&
        offer.isActive(DateTime.now()) &&
        ui.dismissedOfferId != offer.id;
    return SingleChildScrollView(
      key: const ValueKey<String>('waypoint-discover-page'),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              WaypointSectionHeader(
                title: greeting == null || greeting.isEmpty
                    ? 'Find somewhere worth remembering.'
                    : greeting,
                description:
                    discoverTitle == null || discoverTitle.trim().isEmpty
                    ? 'Curated places and practical ideas for your next trip.'
                    : discoverTitle,
              ),
              if (hero != null) ...<Widget>[
                const SizedBox(height: 22),
                _HomeHero(
                  hero: hero,
                  onAction: hero.action == 'open_planner'
                      ? () => showWaypointPlanningSheet(
                          context,
                          action: plannerAction,
                        )
                      : null,
                ),
              ],
              if (collections.isNotEmpty) ...<Widget>[
                const SizedBox(height: 28),
                _DiscoverCollections(collections: collections),
              ],
              if (categories.isNotEmpty) ...<Widget>[
                const SizedBox(height: 28),
                _DiscoverCategories(categories: categories),
              ],
              if (selectedDestination != null) ...<Widget>[
                const SizedBox(height: 14),
                WaypointSurface(
                  key: const ValueKey<String>(
                    'waypoint-discover-selected-context',
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.compare_arrows_rounded, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Comparing ${selectedDestination.locationLabel} with the full list.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              TextField(
                key: const ValueKey<String>('waypoint-search'),
                controller: _searchController,
                onChanged: _search,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search a city, a feeling, or a place type',
                ),
              ),
              if (searchSuggestions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                _SearchSuggestions(
                  suggestions: searchSuggestions,
                  onSelected: _selectSearchSuggestion,
                ),
              ],
              const SizedBox(height: 14),
              _FilterBar(selected: ui.filter),
              if (showOffer) ...<Widget>[
                const SizedBox(height: 18),
                WaypointOfferBanner(
                  offer: offer,
                  onAction: () {
                    if (offer.action == 'open_planner') {
                      showWaypointPlanningSheet(context, action: plannerAction);
                      return;
                    }
                    showWaypointPlanningSheet(context);
                  },
                  onDismiss: () => ref
                      .read(waypointUiProvider.notifier)
                      .dismissOffer(offer.id),
                ),
              ],
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final video = WaypointVideoPreview(
                    assetPath: videoAsset,
                    title: routePreviewAction?.title,
                    playLabel: routePreviewAction?.submitLabel,
                  );
                  final copy = WaypointSurface(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.movie_creation_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'See the pace before you book the plan.',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'A local video asset keeps media loading and playback inside the demo app.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          key: const ValueKey<String>('waypoint-video-action'),
                          onPressed: () => showWaypointPlanningSheet(context),
                          icon: const Icon(Icons.event_note_outlined),
                          label: const Text('Plan around it'),
                        ),
                      ],
                    ),
                  );
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(flex: 6, child: video),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: copy),
                          ],
                        )
                      : Column(
                          children: <Widget>[
                            video,
                            const SizedBox(height: 14),
                            copy,
                          ],
                        );
                },
              ),
              const SizedBox(height: 28),
              Text(
                'Made for your pace',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Save a few options now. Decide the details later.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              search.when(
                loading: () => const _DestinationLoadingGrid(),
                error: (error, stackTrace) => _SearchError(
                  message: error.toString(),
                  onRetry: () => ref
                      .read(waypointSearchProvider.notifier)
                      .search(ui.query),
                ),
                data: (destinations) {
                  final visible = destinations
                      .where(
                        (destination) => _matchesFilter(destination, ui.filter),
                      )
                      .toList(growable: false);
                  return visible.isEmpty
                      ? const _EmptySearchState()
                      : LayoutBuilder(
                          builder: (context, constraints) => GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: visible.length,
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 340,
                                  mainAxisExtent: 420,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                ),
                            itemBuilder: (context, index) {
                              final destination = visible[index];
                              return WaypointDestinationCard(
                                destination: destination,
                                isSaved: ref
                                    .read(waypointUiProvider.notifier)
                                    .isSaved(destination),
                                onTap: () =>
                                    _showDestination(context, destination),
                                onSave: () => ref
                                    .read(waypointUiProvider.notifier)
                                    .toggleSaved(destination),
                              );
                            },
                          ),
                        );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _search(String value) {
    ref.read(waypointUiProvider.notifier).setQuery(value);
    ref.read(waypointSearchProvider.notifier).search(value);
  }

  void _selectSearchSuggestion(String suggestion) {
    _searchController.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    _search(suggestion);
  }

  WaypointTestAction? _findOpenPlannerAction(List<WaypointTestAction> actions) {
    for (final action in actions) {
      if (action.id == 'open_planner' &&
          action.type == 'bottom_sheet' &&
          _hasContent(action.title) &&
          _hasContent(action.subtitle) &&
          _hasContent(action.submitLabel)) {
        return action;
      }
    }
    return null;
  }

  WaypointTestAction? _findRoutePreviewAction(
    List<WaypointTestAction> actions,
  ) {
    for (final action in actions) {
      if (action.id == 'watch_route_preview' &&
          action.type == 'video' &&
          _hasContent(action.assetPath) &&
          _hasContent(action.title) &&
          _hasContent(action.submitLabel)) {
        return action;
      }
    }
    return null;
  }

  bool _hasContent(String? value) => value?.trim().isNotEmpty ?? false;

  bool _matchesFilter(
    WaypointDestination destination,
    WaypointDestinationFilter filter,
  ) => switch (filter) {
    WaypointDestinationFilter.all => true,
    WaypointDestinationFilter.stay =>
      destination.kind == WaypointDestinationKind.stay,
    WaypointDestinationFilter.food =>
      destination.kind == WaypointDestinationKind.food,
    WaypointDestinationFilter.nature =>
      destination.kind == WaypointDestinationKind.nature ||
          destination.kind == WaypointDestinationKind.mountain,
    WaypointDestinationFilter.culture =>
      destination.kind == WaypointDestinationKind.culture,
  };

  Future<void> _showDestination(
    BuildContext context,
    WaypointDestination destination,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              destination.name,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              destination.locationLabel,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Text(
              destination.summary,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(label: Text(destination.category)),
                Chip(
                  label: Text(
                    '${destination.rating.toStringAsFixed(1)} rating',
                  ),
                ),
                Chip(label: Text(destination.durationLabel)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey<String>('waypoint-destination-plan'),
                onPressed: () {
                  Navigator.of(context).pop();
                  showWaypointPlanningSheet(
                    this.context,
                    initialDestination: destination.name,
                  );
                },
                icon: const Icon(Icons.event_note_outlined),
                label: const Text('Plan this destination'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _SearchSuggestions extends StatelessWidget {
  const _SearchSuggestions({
    required this.suggestions,
    required this.onSelected,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (var index = 0; index < suggestions.length; index++)
        ActionChip(
          key: ValueKey<String>('waypoint-search-suggestion-$index'),
          label: Text(suggestions[index]),
          onPressed: () => onSelected(suggestions[index]),
        ),
    ],
  );
}

final class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.hero, required this.onAction});

  final WaypointHomeHero hero;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      child: AspectRatio(
        aspectRatio: 1.35,
        child: WaypointAssetArtwork(
          key: const ValueKey<String>('waypoint-home-hero-image'),
          assetPath: hero.imageAsset,
          semanticsLabel: '${hero.title} hero artwork',
        ),
      ),
    );
    final copy = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            hero.eyebrow,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(hero.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(hero.subtitle, style: Theme.of(context).textTheme.bodyLarge),
          if (onAction != null) ...<Widget>[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey<String>('waypoint-home-hero-action'),
                onPressed: onAction,
                icon: const Icon(Icons.event_note_outlined),
                label: Text(hero.actionLabel),
              ),
            ),
          ],
        ],
      ),
    );

    return WaypointSurface(
      key: const ValueKey<String>('waypoint-home-hero'),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 640;
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 5, child: image),
                    Expanded(flex: 5, child: copy),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[image, copy],
                );
        },
      ),
    );
  }
}

final class _DiscoverCollections extends StatelessWidget {
  const _DiscoverCollections({required this.collections});

  final List<WaypointDiscoverCollection> collections;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const WaypointSectionHeader(
        title: 'Curated collections',
        description: 'Follow a feeling to somewhere new.',
      ),
      const SizedBox(height: 16),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: collections.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 520,
          mainAxisExtent: 300,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemBuilder: (context, index) =>
            _DiscoverCollectionCard(collection: collections[index]),
      ),
    ],
  );
}

final class _DiscoverCollectionCard extends StatelessWidget {
  const _DiscoverCollectionCard({required this.collection});

  final WaypointDiscoverCollection collection;

  @override
  Widget build(BuildContext context) => WaypointSurface(
    key: ValueKey<String>('waypoint-discover-collection-${collection.id}'),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 150,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            child: WaypointAssetArtwork(
              key: ValueKey<String>(
                'waypoint-discover-collection-artwork-${collection.id}',
              ),
              assetPath: collection.imageAsset,
              semanticsLabel: '${collection.title} collection artwork',
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          collection.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          collection.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

final class _DiscoverCategories extends StatelessWidget {
  const _DiscoverCategories({required this.categories});

  final List<WaypointDiscoverCategory> categories;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey<String>('waypoint-discover-categories'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const WaypointSectionHeader(
        title: 'Browse categories',
        description: 'Start with a feeling and see where it leads.',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final category in categories)
            Chip(
              key: ValueKey<String>(
                'waypoint-discover-category-${category.id}',
              ),
              avatar: Icon(_iconFor(category.icon), size: 18),
              label: Text(category.label),
            ),
        ],
      ),
    ],
  );

  IconData _iconFor(String value) => switch (value.toLowerCase()) {
    'coffee' => Icons.coffee_outlined,
    'city' => Icons.location_city_outlined,
    'mountain' => Icons.terrain_outlined,
    'plate' => Icons.restaurant_outlined,
    _ => Icons.explore_outlined,
  };
}

final class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.selected});

  final WaypointDestinationFilter selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: <Widget>[
        for (final filter in WaypointDestinationFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: ValueKey<String>('waypoint-filter-${filter.name}'),
              label: Text(_labelFor(filter)),
              selected: selected == filter,
              onSelected: (_) =>
                  ref.read(waypointUiProvider.notifier).setFilter(filter),
              showCheckmark: false,
            ),
          ),
      ],
    ),
  );

  String _labelFor(WaypointDestinationFilter filter) => switch (filter) {
    WaypointDestinationFilter.all => 'All',
    WaypointDestinationFilter.stay => 'Stay',
    WaypointDestinationFilter.food => 'Food',
    WaypointDestinationFilter.nature => 'Nature',
    WaypointDestinationFilter.culture => 'Culture',
  };
}

final class _DestinationLoadingGrid extends StatelessWidget {
  const _DestinationLoadingGrid();

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: 4,
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 340,
      mainAxisExtent: 420,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
    ),
    itemBuilder: (context, index) => const WaypointDestinationSkeleton(),
  );
}

final class _SearchError extends StatelessWidget {
  const _SearchError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => WaypointSurface(
    child: Row(
      children: <Widget>[
        const Icon(Icons.error_outline_rounded),
        const SizedBox(width: 12),
        Expanded(child: Text('Search failed: $message')),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

final class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) => const WaypointSurface(
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('No places match that search yet.'),
      ),
    ),
  );
}
