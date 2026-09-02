import 'dart:async';

import 'package:alphax/alphax.dart';
import 'package:conformance/waypoint/application/waypoint_providers.dart';
import 'package:conformance/waypoint/application/waypoint_ui_state.dart';
import 'package:conformance/waypoint/data/waypoint_data_source.dart';
import 'package:conformance/waypoint/data/waypoint_repository.dart';
import 'package:conformance/waypoint/domain/waypoint_offer.dart';
import 'package:conformance/waypoint/platform/waypoint_permission.dart';
import 'package:conformance/waypoint/presentation/navigation/waypoint_navigation_rail.dart';
import 'package:conformance/waypoint/presentation/waypoint_app.dart';
import 'package:conformance/waypoint/presentation/widgets/waypoint_activity_tile.dart';
import 'package:conformance/waypoint/presentation/widgets/waypoint_asset_artwork.dart';
import 'package:conformance/waypoint/presentation/widgets/waypoint_offer_banner.dart';
import 'package:conformance/waypoint/presentation/widgets/waypoint_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'waypoint_loading_data_source.dart';
import 'waypoint_retry_data_source.dart';
import 'waypoint_test_support.dart';

void main() {
  testWidgets('renders demo content and toggles a destination as saved', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
    expect(find.text('Kyoto, Japan'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('waypoint-video')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('waypoint-offer-banner')),
      findsOneWidget,
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Waypoint',
    );
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme
          ?.textTheme
          .headlineMedium
          ?.fontFamily,
      'Inter',
    );
    final heading = find.text('Find somewhere worth remembering.');
    expect(heading, findsOneWidget);
    final TextStyle? headingStyle = tester
        .renderObject<RenderParagraph>(heading)
        .text
        .style;
    expect(headingStyle, isNotNull);
    expect(headingStyle!.fontFamily, 'Inter');

    final saveButton = find.byKey(
      const ValueKey<String>('waypoint-save-kyoto'),
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(tester.widget<IconButton>(saveButton).tooltip, 'Remove saved place');

    await tester.tap(find.text('Saved'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey<String>('waypoint-saved-page')),
      findsOneWidget,
    );
    expect(find.text('Kyoto, Japan'), findsOneWidget);
    expect(find.text('You have 1 saved place.'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove saved place'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-kyoto')),
      findsNothing,
    );
    expect(find.text('Kyoto, Japan'), findsNothing);
    expect(find.text('Nothing saved yet.'), findsOneWidget);
    expect(
      find.text('Use the bookmark on a destination to keep it here.'),
      findsOneWidget,
    );

    final browseDestinations = find.byKey(
      const ValueKey<String>('waypoint-saved-discover'),
    );
    await tester.tap(browseDestinations);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
  });

  testWidgets('bundled local demo renders its home hero', (tester) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    expect(find.text('Good morning, Asha'), findsOneWidget);
    expect(find.text('Find your next feeling'), findsOneWidget);
    expect(find.text('WEEKEND EDIT'), findsOneWidget);
    expect(find.text('Make room for somewhere new.'), findsOneWidget);
    expect(
      find.text(
        'Thoughtful places and flexible plans for your next few days away.',
      ),
      findsOneWidget,
    );
    expect(find.text('Plan a trip'), findsOneWidget);
    final heroArtwork = find.byKey(
      const ValueKey<String>('waypoint-home-hero-image'),
    );
    expect(heroArtwork, findsOneWidget);
    expect(
      tester.widget<WaypointAssetArtwork>(heroArtwork).assetPath,
      'assets/images/waypoint/hero-coast.svg',
    );

    final heroAction = find.byKey(
      const ValueKey<String>('waypoint-home-hero-action'),
    );
    await tester.ensureVisible(heroAction);
    await tester.tap(heroAction);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Start a small plan'), findsOneWidget);
    expect(
      find.text('Choose a place, a pace, and a few open days.'),
      findsOneWidget,
    );
    expect(find.text('Show ideas'), findsOneWidget);
    expect(find.text('Shape a small escape'), findsNothing);
    expect(find.text('Create planning brief'), findsNothing);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('When?'), findsOneWidget);
    expect(find.text('Travellers'), findsOneWidget);
    final destination = find.byKey(
      const ValueKey<String>('waypoint-plan-destination'),
    );
    expect(
      tester.widget<TextField>(destination).decoration?.hintText,
      'City, coast, or countryside',
    );
    final travelers = find.byKey(
      const ValueKey<String>('waypoint-plan-travelers'),
    );
    expect(tester.widget<Text>(travelers).data, '2');

    final increase = find.byKey(
      const ValueKey<String>('waypoint-plan-travelers-increase'),
    );
    await tester.ensureVisible(increase);
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.tap(increase);
      await tester.pump();
    }
    expect(tester.widget<Text>(travelers).data, '6');
    expect(tester.widget<IconButton>(increase).onPressed, isNull);

    final decrease = find.byKey(
      const ValueKey<String>('waypoint-plan-travelers-decrease'),
    );
    await tester.ensureVisible(decrease);
    for (var attempt = 6; attempt > 1; attempt--) {
      await tester.tap(decrease);
      await tester.pump();
    }
    expect(tester.widget<Text>(travelers).data, '1');
    expect(tester.widget<IconButton>(decrease).onPressed, isNull);
  });

  testWidgets(
    'bundled local demo switches hero layout at the responsive breakpoint',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(639, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final source = WaypointAlphaXDataSource(
        client: AlphaXClient(
          transport: WaypointDemoTransport(latency: Duration.zero),
        ),
        baseUri: Uri.parse('https://waypoint.demo/'),
        modeLabel: 'Test local demo',
        isDemo: true,
      );
      addTearDown(source.close);

      rootBundle.clear();
      await pumpWaypointTestApp(tester, dataSource: source);
      final homePage = find.byKey(
        const ValueKey<String>('waypoint-discover-page'),
      );
      const maxHomeLoadPumps = 40;
      for (
        var attempt = 0;
        attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(homePage, findsOneWidget);

      final heroArtwork = find.byKey(
        const ValueKey<String>('waypoint-home-hero-image'),
      );
      expect(heroArtwork, findsOneWidget);

      Widget? nearestHeroLayout() {
        Widget? layout;
        tester.element(heroArtwork).visitAncestorElements((element) {
          final widget = element.widget;
          if (widget is Row || widget is Column) {
            layout = widget;
            return false;
          }
          return true;
        });
        return layout;
      }

      expect(nearestHeroLayout(), isA<Column>());

      tester.view.physicalSize = const Size(720, 800);
      await tester.pump();

      expect(heroArtwork, findsOneWidget);
      expect(nearestHeroLayout(), isA<Row>());
    },
  );

  testWidgets('bundled local demo renders its time-limited offer', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final banner = find.byKey(const ValueKey<String>('waypoint-offer-banner'));
    expect(banner, findsOneWidget);
    await tester.ensureVisible(banner);
    expect(
      tester
          .widget<WaypointOfferBanner>(
            find.ancestor(
              of: banner,
              matching: find.byType(WaypointOfferBanner),
            ),
          )
          .offer
          .expiresAt,
      DateTime.utc(2030, 6, 30, 23, 59, 59),
    );
    final bannerDecoration = tester.widget<Container>(banner).decoration;
    expect(bannerDecoration, isA<BoxDecoration>());
    expect((bannerDecoration! as BoxDecoration).color, const Color(0xFFE47755));
    expect(
      find.descendant(
        of: banner,
        matching: find.byKey(const ValueKey<String>('waypoint-offer-dismiss')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: banner,
        matching: find.text('A little more time away'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: banner,
        matching: find.text(
          'Save a flexible long-weekend plan before this edit ends.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: banner, matching: find.text('Build a plan')),
      findsOneWidget,
    );

    final offerAction = find.byKey(
      const ValueKey<String>('waypoint-offer-action'),
    );
    await tester.tap(offerAction);
    await tester.pumpAndSettle();

    expect(find.text('Start a small plan'), findsOneWidget);
    expect(
      find.text('Choose a place, a pace, and a few open days.'),
      findsOneWidget,
    );
    expect(find.text('Show ideas'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('When?'), findsOneWidget);
    expect(find.text('Travellers'), findsOneWidget);
    final destination = find.byKey(
      const ValueKey<String>('waypoint-plan-destination'),
    );
    expect(
      tester.widget<TextField>(destination).decoration?.hintText,
      'City, coast, or countryside',
    );
    final travelers = find.byKey(
      const ValueKey<String>('waypoint-plan-travelers'),
    );
    expect(tester.widget<Text>(travelers).data, '2');

    final increase = find.byKey(
      const ValueKey<String>('waypoint-plan-travelers-increase'),
    );
    await tester.ensureVisible(increase);
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.tap(increase);
      await tester.pump();
    }
    expect(tester.widget<Text>(travelers).data, '6');
    expect(tester.widget<IconButton>(increase).onPressed, isNull);

    final decrease = find.byKey(
      const ValueKey<String>('waypoint-plan-travelers-decrease'),
    );
    await tester.ensureVisible(decrease);
    for (var attempt = 6; attempt > 1; attempt--) {
      await tester.tap(decrease);
      await tester.pump();
    }
    expect(tester.widget<Text>(travelers).data, '1');
    expect(tester.widget<IconButton>(decrease).onPressed, isNull);
  });

  testWidgets(
    'bundled local demo submits a planning brief and shows the Trips confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final source = WaypointAlphaXDataSource(
        client: AlphaXClient(
          transport: WaypointDemoTransport(latency: Duration.zero),
        ),
        baseUri: Uri.parse('https://waypoint.demo/'),
        modeLabel: 'Test local demo',
        isDemo: true,
      );
      addTearDown(source.close);

      rootBundle.clear();
      await pumpWaypointTestApp(tester, dataSource: source);
      final homePage = find.byKey(
        const ValueKey<String>('waypoint-discover-page'),
      );
      const maxHomeLoadPumps = 40;
      for (
        var attempt = 0;
        attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(homePage, findsOneWidget);

      final offerAction = find.byKey(
        const ValueKey<String>('waypoint-offer-action'),
      );
      await tester.ensureVisible(offerAction);
      await tester.tap(offerAction);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      final destination = find.byKey(
        const ValueKey<String>('waypoint-plan-destination'),
      );
      expect(destination, findsOneWidget);
      await tester.ensureVisible(destination);
      await tester.enterText(destination, 'Lisbon');
      await tester.pump();

      final submit = find.byKey(const ValueKey<String>('waypoint-plan-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);

      final tripsNavigation = find.byKey(
        const ValueKey<String>('waypoint-nav-trips'),
      );
      await tester.tap(tripsNavigation);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('waypoint-trips-page')),
        findsOneWidget,
      );
      expect(
        find.text('Your new planning brief is ready for the next step.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'non-dismissible offer keeps its content and action without a close control',
    (tester) async {
      var actionPressed = false;
      final offer = WaypointOffer(
        id: 'non-dismissible-offer',
        title: 'A quieter invitation',
        message: 'This offer should stay visible without a dismiss control.',
        actionLabel: 'Open the brief',
        expiresAt: DateTime.utc(2099, 12, 31),
        accentColor: '#B9DED2',
        isDismissible: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaypointOfferBanner(
              offer: offer,
              onAction: () => actionPressed = true,
              onDismiss: () {},
            ),
          ),
        ),
      );

      final banner = find.byKey(
        const ValueKey<String>('waypoint-offer-banner'),
      );
      expect(banner, findsOneWidget);
      expect(
        find.descendant(
          of: banner,
          matching: find.text('A quieter invitation'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: banner,
          matching: find.text(
            'This offer should stay visible without a dismiss control.',
          ),
        ),
        findsOneWidget,
      );

      final action = find.byKey(
        const ValueKey<String>('waypoint-offer-action'),
      );
      expect(action, findsOneWidget);
      expect(
        find.descendant(of: banner, matching: find.text('Open the brief')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('waypoint-offer-dismiss')),
        findsNothing,
      );

      await tester.tap(action);
      await tester.pump();
      expect(actionPressed, isTrue);
    },
  );

  testWidgets('bundled local demo renders destination distance', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    await tester.pumpAndSettle();

    final destinationCard = find.byKey(
      const ValueKey<String>('waypoint-destination-lantern-house'),
    );
    await tester.ensureVisible(destinationCard);
    expect(
      find.descendant(
        of: destinationCard,
        matching: find.text('0.8 km from your route'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: destinationCard, matching: find.text('Gion, Kyoto')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: destinationCard, matching: find.text('4.9')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: destinationCard, matching: find.text('3 nights')),
      findsOneWidget,
    );
  });

  testWidgets('bundled local demo exposes card accessibility semantics', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    await tester.pumpAndSettle();

    final semanticsHandle = tester.ensureSemantics();
    try {
      final destination = find.byKey(
        const ValueKey<String>('waypoint-destination-lantern-house'),
      );
      await tester.ensureVisible(destination);
      expect(destination, findsOneWidget);
      expect(
        tester.getSemantics(destination).label,
        startsWith('Open Lantern House'),
      );
      expect(tester.getSemantics(destination).flagsCollection.isButton, isTrue);

      final bottomNavigation = find.byKey(
        const ValueKey<String>('waypoint-bottom-navigation'),
      );
      await tester.tap(
        find.descendant(of: bottomNavigation, matching: find.text('Trips')),
      );
      await tester.pumpAndSettle();

      final tripCard = find.byKey(
        const ValueKey<String>('waypoint-trip-kyoto-notes'),
      );
      await tester.ensureVisible(tripCard);
      expect(tripCard, findsOneWidget);
      expect(
        tester.getSemantics(tripCard).label,
        startsWith('Open Kyoto field notes'),
      );
      expect(tester.getSemantics(tripCard).flagsCollection.isButton, isTrue);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('bundled local Discover detail renders source metadata', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final discoverPage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxDiscoverLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxDiscoverLoadPumps && discoverPage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(discoverPage, findsOneWidget);

    final destinationCard = find.byKey(
      const ValueKey<String>('waypoint-destination-lantern-house'),
    );
    await tester.ensureVisible(destinationCard);
    await tester.tap(destinationCard);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Stay')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('4.9 rating')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('3 nights')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('A calm machiya stay with a small inner garden.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('bundled local demo renders destination emojis', (tester) async {
    rootBundle.clear();
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    await pumpWaypointTestApp(tester, dataSource: source);
    const destinations = <({String id, String name, String emoji})>[
      (id: 'lantern-house', name: 'Lantern House', emoji: '⌂'),
      (id: 'blue-tram-table', name: 'Blue Tram Table', emoji: '✦'),
      (id: 'aurora-cabin', name: 'Aurora Cabin', emoji: '✧'),
      (id: 'rose-courtyard', name: 'Rose Courtyard', emoji: '◇'),
      (id: 'coastline-table', name: 'Coastline Table', emoji: '○'),
    ];
    final lastCard = find.byKey(
      const ValueKey<String>('waypoint-destination-coastline-table'),
    );
    const maxDestinationLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxDestinationLoadPumps && lastCard.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(lastCard, findsOneWidget);

    for (final destination in destinations) {
      final card = find.byKey(
        ValueKey<String>('waypoint-destination-${destination.id}'),
      );
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      expect(
        find.descendant(of: card, matching: find.text(destination.name)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text(destination.emoji)),
        findsOneWidget,
      );
    }
  });

  testWidgets('bundled local demo renders destination accent colors', (
    tester,
  ) async {
    rootBundle.clear();
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    await pumpWaypointTestApp(tester, dataSource: source);
    final lastCard = find.byKey(
      const ValueKey<String>('waypoint-destination-coastline-table'),
    );
    const maxDestinationLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxDestinationLoadPumps && lastCard.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(lastCard, findsOneWidget);

    const destinations = <({String cardKey, Color accentColor})>[
      (
        cardKey: 'waypoint-destination-lantern-house',
        accentColor: Color(0xFFD98267),
      ),
      (
        cardKey: 'waypoint-destination-blue-tram-table',
        accentColor: Color(0xFFE6A24F),
      ),
      (
        cardKey: 'waypoint-destination-aurora-cabin',
        accentColor: Color(0xFF5EB9A1),
      ),
      (
        cardKey: 'waypoint-destination-rose-courtyard',
        accentColor: Color(0xFFC46868),
      ),
      (
        cardKey: 'waypoint-destination-coastline-table',
        accentColor: Color(0xFF3C8E9F),
      ),
    ];

    for (final destination in destinations) {
      final card = find.byKey(ValueKey<String>(destination.cardKey));
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      final star = find.descendant(
        of: card,
        matching: find.byIcon(Icons.star_rounded),
      );
      expect(star, findsOneWidget);
      expect(tester.widget<Icon>(star).color, destination.accentColor);
    }
  });

  testWidgets('bundled local demo renders its card artwork assets', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final lastDestinationCard = find.byKey(
      const ValueKey<String>('waypoint-destination-coastline-table'),
    );
    const maxDestinationLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxDestinationLoadPumps &&
          lastDestinationCard.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(lastDestinationCard, findsOneWidget);

    Future<void> expectCardArtwork(String cardKey, String assetPath) async {
      final card = find.byKey(ValueKey<String>(cardKey));
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      final artwork = find.descendant(
        of: card,
        matching: find.byType(WaypointAssetArtwork),
      );
      expect(artwork, findsOneWidget);
      expect(tester.widget<WaypointAssetArtwork>(artwork).assetPath, assetPath);
    }

    const destinationArtwork = <({String cardKey, String assetPath})>[
      (
        cardKey: 'waypoint-destination-lantern-house',
        assetPath: 'assets/images/waypoint/kyoto.svg',
      ),
      (
        cardKey: 'waypoint-destination-blue-tram-table',
        assetPath: 'assets/images/waypoint/lisbon.svg',
      ),
      (
        cardKey: 'waypoint-destination-aurora-cabin',
        assetPath: 'assets/images/waypoint/reykjavik.svg',
      ),
      (
        cardKey: 'waypoint-destination-rose-courtyard',
        assetPath: 'assets/images/waypoint/jaipur.svg',
      ),
      (
        cardKey: 'waypoint-destination-coastline-table',
        assetPath: 'assets/images/waypoint/hero-coast.svg',
      ),
    ];
    for (final destination in destinationArtwork) {
      await expectCardArtwork(destination.cardKey, destination.assetPath);
    }

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('waypoint-trips-page')),
      findsOneWidget,
    );

    const tripArtwork = <({String cardKey, String assetPath})>[
      (
        cardKey: 'waypoint-trip-kyoto-notes',
        assetPath: 'assets/images/waypoint/kyoto.svg',
      ),
      (
        cardKey: 'waypoint-trip-lisbon-light',
        assetPath: 'assets/images/waypoint/lisbon.svg',
      ),
    ];
    for (final trip in tripArtwork) {
      await expectCardArtwork(trip.cardKey, trip.assetPath);
    }
  });

  testWidgets('bundled local demo searches destination descriptions', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final lanternHouse = find.byKey(
      const ValueKey<String>('waypoint-destination-lantern-house'),
    );
    expect(lanternHouse, findsOneWidget);

    final search = find.byKey(const ValueKey<String>('waypoint-search'));
    await tester.enterText(search, 'old city');
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-rose-courtyard')),
      findsOneWidget,
    );
    expect(lanternHouse, findsNothing);
  });

  testWidgets('bundled local demo renders its search suggestions', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    const suggestions = <String>[
      'quiet stays',
      'walkable cities',
      'weekend by the sea',
      'local food',
    ];
    for (var index = 0; index < suggestions.length; index++) {
      final suggestion = suggestions[index];
      expect(find.text(suggestion), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('waypoint-search-suggestion-$index')),
        findsOneWidget,
      );
    }

    const selectedSuggestion = 'local food';
    final selectedChip = find.byKey(
      const ValueKey<String>('waypoint-search-suggestion-3'),
    );
    await tester.ensureVisible(selectedChip);
    await tester.tap(selectedChip);
    await tester.pump();
    await tester.pump();

    final search = find.byKey(const ValueKey<String>('waypoint-search'));
    expect(
      tester.widget<TextField>(search).controller!.text,
      selectedSuggestion,
    );
    expect(find.text('No places match that search yet.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-lantern-house')),
      findsNothing,
    );
  });

  testWidgets('bundled local demo renders its route preview action', (
    tester,
  ) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final fakePlatform = _BundledRoutePreviewVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
    addTearDown(() {
      VideoPlayerPlatform.instance = previousPlatform;
    });

    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final previewTitle = find.text('Preview the route');
    const maxPreviewLoadPumps = 20;
    for (
      var attempt = 0;
      attempt < maxPreviewLoadPumps && previewTitle.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(previewTitle, findsOneWidget);
    expect(fakePlatform.creationOptions, hasLength(1));
    final creationOptions = fakePlatform.creationOptions.single;
    expect(creationOptions.dataSource.sourceType, DataSourceType.asset);
    expect(
      creationOptions.dataSource.asset,
      'assets/video/waypoint-route-preview.mp4',
    );

    final playButton = find.byKey(
      const ValueKey<String>('waypoint-video-play'),
    );
    expect(playButton, findsOneWidget);
    expect(tester.widget<IconButton>(playButton).tooltip, 'Play preview');

    final semanticsHandle = tester.ensureSemantics();
    try {
      final playSemantics = tester.getSemantics(playButton);
      expect(playSemantics.tooltip, 'Play preview');
    } finally {
      semanticsHandle.dispose();
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'uses the home hero video asset when route preview action is unavailable',
    (tester) async {
      final previousPlatform = VideoPlayerPlatform.instance;
      final fakePlatform = _BundledRoutePreviewVideoPlayerPlatform();
      VideoPlayerPlatform.instance = fakePlatform;
      addTearDown(() {
        VideoPlayerPlatform.instance = previousPlatform;
      });

      final home = Map<String, Object?>.from(waypointTestHomePayload());
      home['hero'] = <String, Object?>{
        'eyebrow': 'TEST HERO',
        'title': 'Hero-only video',
        'subtitle': 'Use the decoded hero asset.',
        'imageAsset': 'assets/images/waypoint/kyoto.svg',
        'videoAsset': 'assets/video/hero-only-test.mp4',
        'action': '',
        'actionLabel': '',
      };
      home['actions'] = <Object?>[];

      await pumpWaypointTestApp(
        tester,
        dataSource: WaypointTestDataSource(home: home),
      );
      const maxVideoLoadPumps = 20;
      for (
        var attempt = 0;
        attempt < maxVideoLoadPumps && fakePlatform.creationOptions.isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(fakePlatform.creationOptions, hasLength(1));
      final creationOptions = fakePlatform.creationOptions.single;
      expect(creationOptions.dataSource.sourceType, DataSourceType.asset);
      expect(
        creationOptions.dataSource.asset,
        'assets/video/hero-only-test.mp4',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('bundled local demo renders its Discover collections', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final firstCollection = find.byKey(
      const ValueKey<String>('waypoint-discover-collection-first-light'),
    );
    final warmColours = find.byKey(
      const ValueKey<String>('waypoint-discover-collection-warm-colours'),
    );
    await tester.ensureVisible(firstCollection);
    await tester.ensureVisible(warmColours);

    expect(
      find.descendant(of: firstCollection, matching: find.text('First light')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: firstCollection,
        matching: find.text('Places worth waking up for'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: warmColours, matching: find.text('Warm colours')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: warmColours,
        matching: find.text('A softer kind of city break'),
      ),
      findsOneWidget,
    );

    final firstArtwork = find.byKey(
      const ValueKey<String>(
        'waypoint-discover-collection-artwork-first-light',
      ),
    );
    final warmColoursArtwork = find.byKey(
      const ValueKey<String>(
        'waypoint-discover-collection-artwork-warm-colours',
      ),
    );
    expect(firstArtwork, findsOneWidget);
    expect(warmColoursArtwork, findsOneWidget);
    expect(
      tester.widget<WaypointAssetArtwork>(firstArtwork).assetPath,
      'assets/images/waypoint/reykjavik.svg',
    );
    expect(
      tester.widget<WaypointAssetArtwork>(warmColoursArtwork).assetPath,
      'assets/images/waypoint/jaipur.svg',
    );
  });

  testWidgets('bundled local demo renders its Discover categories', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    const categories = <String, String>{
      'slow': 'Slow mornings',
      'city': 'City breaks',
      'nature': 'Open skies',
      'food': 'Good tables',
    };
    const categoryIcons = <String, IconData>{
      'slow': Icons.coffee_outlined,
      'city': Icons.location_city_outlined,
      'nature': Icons.terrain_outlined,
      'food': Icons.restaurant_outlined,
    };
    for (final entry in categories.entries) {
      final category = find.byKey(
        ValueKey<String>('waypoint-discover-category-${entry.key}'),
      );
      await tester.ensureVisible(category);
      expect(category, findsOneWidget);
      expect(
        find.descendant(of: category, matching: find.text(entry.value)),
        findsOneWidget,
      );
      final categoryIcon = find.descendant(
        of: category,
        matching: find.byType(Icon),
      );
      expect(categoryIcon, findsOneWidget);
      expect(tester.widget<Icon>(categoryIcon).icon, categoryIcons[entry.key]);
    }
  });

  testWidgets('bundled local demo preserves its initial saved destination', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    await tester.pumpAndSettle();

    final destinationCard = find.byKey(
      const ValueKey<String>('waypoint-destination-lantern-house'),
    );
    expect(destinationCard, findsOneWidget);

    final saveButton = find.byKey(
      const ValueKey<String>('waypoint-save-lantern-house'),
    );
    expect(saveButton, findsOneWidget);
    expect(tester.widget<IconButton>(saveButton).tooltip, 'Remove saved place');

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    final savedNavigation = find.descendant(
      of: bottomNavigation,
      matching: find.text('Saved'),
    );
    expect(savedNavigation, findsOneWidget);
    await tester.tap(savedNavigation);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('waypoint-saved-page')),
      findsOneWidget,
    );
    expect(find.text('Lantern House'), findsOneWidget);
    expect(find.text('You have 1 saved place.'), findsOneWidget);

    await tester.tap(destinationCard);
    await tester.pumpAndSettle();

    final openDiscover = find.byKey(
      const ValueKey<String>('waypoint-saved-detail-discover'),
    );
    expect(openDiscover, findsOneWidget);
    await tester.tap(openDiscover);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
    final selectedContext = find.byKey(
      const ValueKey<String>('waypoint-discover-selected-context'),
    );
    expect(selectedContext, findsOneWidget);
    expect(
      find.descendant(
        of: selectedContext,
        matching: find.text('Comparing Gion, Kyoto with the full list.'),
      ),
      findsOneWidget,
    );

    await tester.tap(savedNavigation);
    await tester.pumpAndSettle();

    final savedCardSaveButton = find.descendant(
      of: destinationCard,
      matching: find.byKey(
        const ValueKey<String>('waypoint-save-lantern-house'),
      ),
    );
    expect(savedCardSaveButton, findsOneWidget);
    await tester.tap(savedCardSaveButton);
    await tester.pump();

    expect(destinationCard, findsNothing);
    expect(find.text('Nothing saved yet.'), findsOneWidget);
    expect(
      find.text('Use the bookmark on a destination to keep it here.'),
      findsOneWidget,
    );

    final browseDestinations = find.byKey(
      const ValueKey<String>('waypoint-saved-discover'),
    );
    expect(browseDestinations, findsOneWidget);
    expect(find.text('Browse destinations'), findsOneWidget);

    await tester.tap(browseDestinations);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
  });

  testWidgets('bundled local Activity feed renders both shipped updates', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Activity')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('waypoint-activity-page')),
      findsOneWidget,
    );
    final activityToggle = find.byKey(
      const ValueKey<String>('waypoint-activity-toggle'),
    );
    expect(
      find.descendant(of: activityToggle, matching: find.text('Start feed')),
      findsOneWidget,
    );

    await tester.tap(activityToggle);
    await tester.pumpAndSettle();

    expect(find.text('Your Kyoto plan was refreshed'), findsOneWidget);
    expect(find.text('Asha saved Lantern House'), findsOneWidget);
    final refreshedActivityTile = find.ancestor(
      of: find.text('Your Kyoto plan was refreshed'),
      matching: find.byType(WaypointActivityTile),
    );
    expect(refreshedActivityTile, findsOneWidget);
    expect(
      find.descendant(
        of: refreshedActivityTile,
        matching: find.text('Two new tea houses match your saved route.'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: refreshedActivityTile,
        matching: find.text('8 min ago'),
      ),
      findsOneWidget,
    );
    final refreshedActivityContainer = find.descendant(
      of: refreshedActivityTile,
      matching: find.byType(Container),
    );
    expect(refreshedActivityContainer, findsOneWidget);
    final refreshedActivityDecoration = tester
        .widget<Container>(refreshedActivityContainer)
        .decoration;
    expect(refreshedActivityDecoration, isA<BoxDecoration>());
    expect(
      (refreshedActivityDecoration! as BoxDecoration).color,
      const Color(0xFFD98267),
    );
    final refreshedActivityIcon = find.descendant(
      of: find.ancestor(
        of: find.text('Your Kyoto plan was refreshed'),
        matching: find.byType(WaypointActivityTile),
      ),
      matching: find.byType(Icon),
    );
    expect(refreshedActivityIcon, findsOneWidget);
    expect(
      tester.widget<Icon>(refreshedActivityIcon).icon,
      Icons.auto_awesome_rounded,
    );
    final savedActivityIcon = find.descendant(
      of: find.ancestor(
        of: find.text('Asha saved Lantern House'),
        matching: find.byType(WaypointActivityTile),
      ),
      matching: find.byType(Icon),
    );
    expect(savedActivityIcon, findsOneWidget);
    expect(tester.widget<Icon>(savedActivityIcon).icon, Icons.bookmark_rounded);
    final savedActivityTile = find.ancestor(
      of: find.text('Asha saved Lantern House'),
      matching: find.byType(WaypointActivityTile),
    );
    expect(savedActivityTile, findsOneWidget);
    expect(
      find.descendant(
        of: savedActivityTile,
        matching: find.text('It is now on your Kyoto shortlist.'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: savedActivityTile, matching: find.text('Yesterday')),
      findsOneWidget,
    );
    final savedActivityContainer = find.descendant(
      of: savedActivityTile,
      matching: find.byType(Container),
    );
    expect(savedActivityContainer, findsOneWidget);
    final savedActivityDecoration = tester
        .widget<Container>(savedActivityContainer)
        .decoration;
    expect(savedActivityDecoration, isA<BoxDecoration>());
    expect(
      (savedActivityDecoration! as BoxDecoration).color,
      const Color(0xFF4B927B),
    );
    expect(
      find.descendant(of: activityToggle, matching: find.text('Start feed')),
      findsOneWidget,
    );
  });

  testWidgets('bundled local Trips detail renders its shipped document', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    final kyotoTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-kyoto-notes'),
    );
    await tester.ensureVisible(kyotoTrip);
    await tester.tap(kyotoTrip);
    await tester.pumpAndSettle();

    final detailSheet = find.byType(BottomSheet);
    expect(
      find.descendant(
        of: detailSheet,
        matching: find.text('Kyoto field notes'),
      ),
      findsOneWidget,
    );

    final documents = find.byKey(
      const ValueKey<String>('waypoint-trip-documents-kyoto-notes'),
    );
    expect(documents, findsOneWidget);
    await tester.ensureVisible(documents);
    expect(
      find.descendant(
        of: documents,
        matching: find.text('Kyoto itinerary.pdf'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: documents, matching: find.text('Itinerary')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: documents, matching: find.text('248 KB')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: documents, matching: find.text('Rail pass note.txt')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: documents, matching: find.text('Travel note')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: documents, matching: find.text('12 KB')),
      findsOneWidget,
    );
    final documentRows = find.descendant(
      of: documents,
      matching: find.byType(ListTile),
    );
    expect(documentRows, findsNWidgets(2));
    final noteDocumentRow = find.ancestor(
      of: find.text('Rail pass note.txt'),
      matching: find.byType(ListTile),
    );
    expect(noteDocumentRow, findsOneWidget);
    expect(
      find.descendant(
        of: noteDocumentRow,
        matching: find.byIcon(Icons.note_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('bundled local Trips detail renders its shipped document icon', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    final kyotoTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-kyoto-notes'),
    );
    await tester.ensureVisible(kyotoTrip);
    await tester.tap(kyotoTrip);
    await tester.pumpAndSettle();

    final documents = find.byKey(
      const ValueKey<String>('waypoint-trip-documents-kyoto-notes'),
    );
    expect(documents, findsOneWidget);
    await tester.ensureVisible(documents);

    final documentRow = find.ancestor(
      of: find.text('Kyoto itinerary.pdf'),
      matching: find.byType(ListTile),
    );
    final documentIcon = find.descendant(
      of: documentRow,
      matching: find.byType(Icon),
    );
    expect(documentIcon, findsOneWidget);
    final renderedIcon = tester.widget<Icon>(documentIcon);
    expect(renderedIcon.icon, Icons.route_outlined);
    expect(renderedIcon.icon, isNot(equals(Icons.description_outlined)));
  });

  testWidgets('bundled local Trips detail toggles checklist completion', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    final kyotoTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-kyoto-notes'),
    );
    await tester.ensureVisible(kyotoTrip);
    await tester.tap(kyotoTrip);
    await tester.pumpAndSettle();

    final checklist = find.byKey(
      const ValueKey<String>('waypoint-trip-checklist-kyoto-notes'),
    );
    expect(checklist, findsOneWidget);

    final firstItem = find.byKey(
      const ValueKey<String>('waypoint-trip-checklist-item-kyoto-notes-0'),
    );
    final secondItem = find.byKey(
      const ValueKey<String>('waypoint-trip-checklist-item-kyoto-notes-1'),
    );
    expect(tester.widget<CheckboxListTile>(firstItem).value, isTrue);
    expect(tester.widget<CheckboxListTile>(secondItem).value, isFalse);
    expect(
      find.descendant(of: firstItem, matching: find.text('Reserve rail pass')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: firstItem,
        matching: find.text('Compare flexible options'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: secondItem, matching: find.text('Save a tea house')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: secondItem,
        matching: find.text('Choose a quiet evening slot'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(firstItem);
    await tester.tap(firstItem);
    await tester.pump();

    expect(tester.widget<CheckboxListTile>(firstItem).value, isFalse);
  });

  testWidgets('bundled local Trips detail preserves itinerary completion', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    final kyotoTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-kyoto-notes'),
    );
    await tester.ensureVisible(kyotoTrip);
    await tester.tap(kyotoTrip);
    await tester.pumpAndSettle();

    Finder itineraryRow(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(ListTile));

    Finder itineraryStatus(String title, int index) => find.descendant(
      of: itineraryRow(title),
      matching: find.byKey(
        ValueKey<String>('waypoint-trip-itinerary-status-kyoto-notes-$index'),
      ),
    );

    final completeStatus = itineraryStatus("Philosopher's Path", 0);
    final teaHouseStatus = itineraryStatus('Tea house reservation', 1);
    final lanternsStatus = itineraryStatus('Lanterns at Yasaka', 2);

    expect(completeStatus, findsOneWidget);
    expect(teaHouseStatus, findsOneWidget);
    expect(lanternsStatus, findsOneWidget);
    expect(
      tester.widget<Icon>(completeStatus).icon,
      Icons.check_circle_rounded,
    );
    expect(
      tester.widget<Icon>(teaHouseStatus).icon,
      Icons.radio_button_unchecked_rounded,
    );
    expect(
      tester.widget<Icon>(lanternsStatus).icon,
      Icons.radio_button_unchecked_rounded,
    );
  });

  testWidgets('bundled local Trips detail renders itinerary categories', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    final kyotoTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-kyoto-notes'),
    );
    await tester.ensureVisible(kyotoTrip);
    await tester.tap(kyotoTrip);
    await tester.pumpAndSettle();

    Finder itineraryRow(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(ListTile));

    Finder itineraryCategory(String title, int index) => find.descendant(
      of: itineraryRow(title),
      matching: find.byKey(
        ValueKey<String>('waypoint-trip-itinerary-category-kyoto-notes-$index'),
      ),
    );

    final philosopherCategory = itineraryCategory("Philosopher's Path", 0);
    final teaHouseCategory = itineraryCategory('Tea house reservation', 1);
    final lanternsCategory = itineraryCategory('Lanterns at Yasaka', 2);

    expect(philosopherCategory, findsOneWidget);
    expect(teaHouseCategory, findsOneWidget);
    expect(lanternsCategory, findsOneWidget);
    expect(
      find.descendant(of: philosopherCategory, matching: find.text('walk')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: teaHouseCategory, matching: find.text('food')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lanternsCategory, matching: find.text('culture')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: itineraryRow("Philosopher's Path"),
        matching: find.text('09:30'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: itineraryRow("Philosopher's Path"),
        matching: find.text('A slow walk beside the canal'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: itineraryRow('Tea house reservation'),
        matching: find.text('13:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: itineraryRow('Tea house reservation'),
        matching: find.text('A small room in Gion'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: itineraryRow('Lanterns at Yasaka'),
        matching: find.text('18:40'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: itineraryRow('Lanterns at Yasaka'),
        matching: find.text('Golden hour in the old quarter'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('bundled local demo surfaces the shipped Open skies trip', (
    tester,
  ) async {
    rootBundle.clear();
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    final openSkiesTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-reykjavik-open-skies'),
    );
    expect(openSkiesTrip, findsOneWidget);
    expect(
      find.descendant(of: openSkiesTrip, matching: find.text('Open skies')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openSkiesTrip,
        matching: find.text('Reykjavík, Iceland'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openSkiesTrip,
        matching: find.text('08–12 Sep 2027  |  4 nights'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(openSkiesTrip);
    await tester.tap(openSkiesTrip);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Open skies')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Reykjavík, Iceland')),
      findsOneWidget,
    );
  });

  testWidgets('bundled local demo renders its trip accent', (tester) async {
    rootBundle.clear();
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    final openSkiesTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-reykjavik-open-skies'),
    );
    expect(openSkiesTrip, findsOneWidget);
    await tester.ensureVisible(openSkiesTrip);

    final progress = find.descendant(
      of: openSkiesTrip,
      matching: find.byType(LinearProgressIndicator),
    );
    expect(progress, findsOneWidget);
    expect(
      tester.widget<LinearProgressIndicator>(progress).valueColor?.value,
      const Color(0xFF5EB9A1),
    );
  });

  testWidgets('bundled local demo renders its trip progress percentage', (
    tester,
  ) async {
    rootBundle.clear();
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    final kyotoTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-kyoto-notes'),
    );
    expect(kyotoTrip, findsOneWidget);
    await tester.ensureVisible(kyotoTrip);

    final progress = find.descendant(
      of: kyotoTrip,
      matching: find.byType(LinearProgressIndicator),
    );
    expect(progress, findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(progress).value, 0.62);

    final cardPercentage = find.descendant(
      of: kyotoTrip,
      matching: find.text('62%'),
    );
    await tester.ensureVisible(cardPercentage);
    expect(cardPercentage, findsOneWidget);

    final overviewPercentage = find.text('62% ready');
    await tester.ensureVisible(overviewPercentage);
    expect(overviewPercentage, findsOneWidget);

    final planPulse = find.ancestor(
      of: find.text('ready'),
      matching: find.byType(WaypointSurface),
    );
    expect(planPulse, findsOneWidget);
    expect(
      find.descendant(of: planPulse, matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: planPulse, matching: find.text('ready')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: planPulse, matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: planPulse, matching: find.text('stops')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: planPulse, matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: planPulse, matching: find.text('details')),
      findsOneWidget,
    );
  });

  testWidgets('bundled local demo renders its trip cover label', (
    tester,
  ) async {
    rootBundle.clear();
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    final openSkiesTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-reykjavik-open-skies'),
    );
    expect(openSkiesTrip, findsOneWidget);

    final coverLabel = find.descendant(
      of: openSkiesTrip,
      matching: find.text('Wind, water, and winter light'),
    );
    expect(coverLabel, findsOneWidget);
    final coverLabelText = tester.widget<Text>(coverLabel);
    expect(coverLabelText.maxLines, 2);
    expect(coverLabelText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('bundled local share-trip-note action opens and saves a note', (
    tester,
  ) async {
    rootBundle.clear();
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Settings')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('waypoint-settings-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('waypoint-settings-share-trip-note-title'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey<String>('waypoint-settings-share-trip-note-title'),
            ),
          )
          .data,
      'Add a travel note',
    );
    expect(find.text('Keep one small thought with the plan.'), findsOneWidget);

    final action = find.byKey(
      const ValueKey<String>('waypoint-settings-share-trip-note'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Add a travel note')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('Keep one small thought with the plan.'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Your note')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Save note')),
      findsOneWidget,
    );

    final noteField = find.byKey(const ValueKey<String>('waypoint-note-field'));
    expect(noteField, findsOneWidget);
    expect(
      tester.widget<TextField>(noteField).decoration?.hintText,
      'A place to return to…',
    );

    final save = find.byKey(const ValueKey<String>('waypoint-note-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(noteField, 'A quiet tea house to revisit.');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('waypoint-note-saved')),
      findsOneWidget,
    );
    expect(find.text('Note saved for this session.'), findsOneWidget);
  });

  testWidgets('hands off Discover Kyoto to a prefilled planning sheet', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    final destinationCard = find.byKey(
      const ValueKey<String>('waypoint-destination-kyoto'),
    );
    await tester.ensureVisible(destinationCard);
    await tester.tap(destinationCard);
    await tester.pumpAndSettle();

    final detailSheet = find.byType(BottomSheet);
    expect(detailSheet, findsOneWidget);
    expect(
      find.descendant(of: detailSheet, matching: find.text('Kyoto')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detailSheet, matching: find.text('Kyoto, Japan')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: detailSheet,
        matching: find.text(
          'Quiet lanes, good tea, and a slower morning rhythm.',
        ),
      ),
      findsOneWidget,
    );

    final planAction = find.byKey(
      const ValueKey<String>('waypoint-destination-plan'),
    );
    expect(
      find.descendant(of: detailSheet, matching: planAction),
      findsOneWidget,
    );
    await tester.ensureVisible(planAction);
    await tester.tap(planAction);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(planAction, findsNothing);

    final destination = find.byKey(
      const ValueKey<String>('waypoint-plan-destination'),
    );
    expect(destination, findsOneWidget);
    expect(tester.widget<TextField>(destination).controller!.text, 'Kyoto');

    final submit = find.byKey(const ValueKey<String>('waypoint-plan-submit'));
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });

  testWidgets('submits a prefilled Discover Kyoto planning sheet', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    final destinationCard = find.byKey(
      const ValueKey<String>('waypoint-destination-kyoto'),
    );
    await tester.ensureVisible(destinationCard);
    await tester.tap(destinationCard);
    await tester.pumpAndSettle();

    final detailSheet = find.byType(BottomSheet);
    expect(detailSheet, findsOneWidget);
    final planAction = find.byKey(
      const ValueKey<String>('waypoint-destination-plan'),
    );
    expect(
      find.descendant(of: detailSheet, matching: planAction),
      findsOneWidget,
    );
    await tester.ensureVisible(planAction);
    await tester.tap(planAction);
    await tester.pumpAndSettle();

    final destination = find.byKey(
      const ValueKey<String>('waypoint-plan-destination'),
    );
    expect(destination, findsOneWidget);
    expect(tester.widget<TextField>(destination).controller!.text, 'Kyoto');

    final submit = find.byKey(const ValueKey<String>('waypoint-plan-submit'));
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(destination, findsNothing);
    expect(find.text('Your planning brief is ready to review'), findsOneWidget);
  });

  testWidgets('default planner entry resets after a submitted prefilled plan', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    final destinationCard = find.byKey(
      const ValueKey<String>('waypoint-destination-kyoto'),
    );
    await tester.ensureVisible(destinationCard);
    await tester.tap(destinationCard);
    await tester.pumpAndSettle();

    final detailSheet = find.byType(BottomSheet);
    final planAction = find.byKey(
      const ValueKey<String>('waypoint-destination-plan'),
    );
    expect(
      find.descendant(of: detailSheet, matching: planAction),
      findsOneWidget,
    );
    await tester.ensureVisible(planAction);
    await tester.tap(planAction);
    await tester.pumpAndSettle();

    final destination = find.byKey(
      const ValueKey<String>('waypoint-plan-destination'),
    );
    expect(destination, findsOneWidget);
    expect(tester.widget<TextField>(destination).controller!.text, 'Kyoto');

    final submit = find.byKey(const ValueKey<String>('waypoint-plan-submit'));
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(destination, findsNothing);
    expect(find.text('Your planning brief is ready to review'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-header-settings')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('waypoint-settings-page')),
      findsOneWidget,
    );
    final openPlanningForm = find.byKey(
      const ValueKey<String>('waypoint-settings-plan'),
    );
    await tester.ensureVisible(openPlanningForm);
    await tester.tap(openPlanningForm);

    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(destination, findsOneWidget);
    expect(tester.widget<TextField>(destination).controller!.text, isEmpty);
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(destination, findsOneWidget);
    expect(tester.widget<TextField>(destination).controller!.text, isEmpty);
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
  });

  testWidgets('opens the saved Kyoto detail bottom sheet', (tester) async {
    await pumpWaypointTestApp(tester);

    final saveButton = find.byKey(
      const ValueKey<String>('waypoint-save-kyoto'),
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    await tester.tap(find.text('Saved'));
    await tester.pump(const Duration(milliseconds: 300));

    final destinationCard = find.byKey(
      const ValueKey<String>('waypoint-destination-kyoto'),
    );
    await tester.ensureVisible(destinationCard);
    await tester.tap(destinationCard);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Kyoto')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.text(
          'Quiet lanes, good tea, and a slower morning rhythm.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.text(
          'Open Discover to compare this place with the full list.',
        ),
      ),
      findsOneWidget,
    );

    final openDiscover = find.byKey(
      const ValueKey<String>('waypoint-saved-detail-discover'),
    );
    expect(find.descendant(of: sheet, matching: openDiscover), findsOneWidget);

    await tester.tap(openDiscover);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
    final selectedContext = find.byKey(
      const ValueKey<String>('waypoint-discover-selected-context'),
    );
    expect(selectedContext, findsOneWidget);
    expect(
      find.descendant(
        of: selectedContext,
        matching: find.text('Comparing Kyoto, Japan with the full list.'),
      ),
      findsOneWidget,
    );

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('waypoint-trips-page')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Discover')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
    expect(selectedContext, findsNothing);
  });

  testWidgets('renders and opens a secondary trip', (tester) async {
    final home = Map<String, Object?>.from(waypointTestHomePayload());
    home['trips'] = <Object?>[
      ...(home['trips'] as List<Object?>),
      <String, Object?>{
        'id': 'lisbon-light',
        'title': 'Lisbon in soft light',
        'destination': 'Lisbon, Portugal',
        'dateRange': '02–06 Jun 2027',
        'durationLabel': '4 nights',
        'imageAsset': 'assets/images/waypoint/lisbon.svg',
        'progress': 0.18,
        'itinerary': <Object?>[
          <String, Object?>{
            'time': '10:00',
            'title': 'Alfama photo walk',
            'detail': 'Start before the streets warm up',
            'category': 'walk',
            'done': false,
          },
        ],
        'checklist': <Object?>[
          <String, Object?>{
            'title': 'Pick a neighbourhood',
            'detail': 'Keep the first day walkable',
            'done': false,
          },
        ],
      },
    ];

    await pumpWaypointTestApp(
      tester,
      dataSource: WaypointTestDataSource(home: home),
    );

    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();

    final firstTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-kyoto-trip'),
    );
    final secondTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-lisbon-light'),
    );
    expect(firstTrip, findsOneWidget);
    expect(secondTrip, findsOneWidget);

    await tester.ensureVisible(secondTrip);
    await tester.tap(secondTrip);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Lisbon in soft light')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Lisbon, Portugal')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Alfama photo walk')),
      findsOneWidget,
    );
  });

  testWidgets('empty Trips state opens a blank planning form', (tester) async {
    final home = Map<String, Object?>.from(waypointTestHomePayload());
    home['trips'] = <Object?>[];

    await pumpWaypointTestApp(
      tester,
      dataSource: WaypointTestDataSource(home: home),
    );

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your next trip starts here.'), findsOneWidget);
    expect(
      find.text('Create a planning brief to give the idea a shape.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('waypoint-trip-kyoto-trip')),
      findsNothing,
    );

    final emptyPlan = find.byKey(
      const ValueKey<String>('waypoint-trips-empty-plan'),
    );
    await tester.tap(emptyPlan);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    final destination = find.byKey(
      const ValueKey<String>('waypoint-plan-destination'),
    );
    expect(destination, findsOneWidget);
    expect(tester.widget<TextField>(destination).controller!.text, isEmpty);

    final submit = find.byKey(const ValueKey<String>('waypoint-plan-submit'));
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
  });

  testWidgets('populated Trips plan CTA opens a blank planning form', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('waypoint-trips-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('waypoint-trips-empty-plan')),
      findsNothing,
    );

    final planCta = find.byKey(const ValueKey<String>('waypoint-plan-cta'));
    await tester.ensureVisible(planCta);
    await tester.tap(planCta);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    final destination = find.byKey(
      const ValueKey<String>('waypoint-plan-destination'),
    );
    expect(destination, findsOneWidget);
    expect(tester.widget<TextField>(destination).controller!.text, isEmpty);

    final submit = find.byKey(const ValueKey<String>('waypoint-plan-submit'));
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
  });

  testWidgets('renders the primary trip checklist in the detail sheet', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    final kyotoTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-kyoto-trip'),
    );
    await tester.ensureVisible(kyotoTrip);
    await tester.tap(kyotoTrip);
    await tester.pumpAndSettle();

    final checklist = find.byKey(
      const ValueKey<String>('waypoint-trip-checklist-kyoto-trip'),
    );
    expect(checklist, findsOneWidget);
    expect(
      find.descendant(of: checklist, matching: find.text('Rail pass')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: checklist, matching: find.text('Stay')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: checklist, matching: find.text('Tea reservation')),
      findsOneWidget,
    );
  });

  testWidgets('hands off the primary Kyoto trip to a planning sheet', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('waypoint-trips-page')),
      findsOneWidget,
    );

    final kyotoTrip = find.byKey(
      const ValueKey<String>('waypoint-trip-kyoto-trip'),
    );
    await tester.ensureVisible(kyotoTrip);
    await tester.tap(kyotoTrip);
    await tester.pumpAndSettle();

    final planAction = find.byKey(const ValueKey<String>('waypoint-trip-plan'));
    final detailSheet = find.ancestor(
      of: planAction,
      matching: find.byType(BottomSheet),
    );
    expect(detailSheet, findsOneWidget);

    await tester.ensureVisible(planAction);
    await tester.tap(planAction);
    await tester.pumpAndSettle();

    expect(detailSheet, findsNothing);

    final destination = find.byKey(
      const ValueKey<String>('waypoint-plan-destination'),
    );
    expect(destination, findsOneWidget);
    expect(
      tester.widget<TextField>(destination).controller!.text,
      equals('Kyoto'),
    );

    final submit = find.byKey(const ValueKey<String>('waypoint-plan-submit'));
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });

  testWidgets('shows the home loading skeleton until initial data resolves', (
    tester,
  ) async {
    final source = WaypointLoadingDataSource();
    addTearDown(source.release);

    await pumpWaypointTestApp(tester, dataSource: source);

    expect(find.byType(WaypointLoadingPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsNothing,
    );

    source.release();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
    expect(find.text('Kyoto, Japan'), findsOneWidget);
  });

  testWidgets('home load error recovers after retry', (tester) async {
    final source = WaypointFailOnceDataSource();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          waypointRepositoryProvider.overrideWithValue(
            WaypointRepository(source),
          ),
          waypointPermissionServiceProvider.overrideWithValue(
            WaypointTestPermissionService(),
          ),
        ],
        child: const WaypointApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(source.homeLoadAttempts, 1);
    expect(find.text('Waypoint could not load this view.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('waypoint-retry')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('waypoint-retry')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(source.homeLoadAttempts, 2);
    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
    expect(find.text('Kyoto, Japan'), findsOneWidget);
  });

  testWidgets(
    'persistent unavailable data source remains visible after retry',
    (tester) async {
      const errorMessage = 'Persistent test data source failure';
      await pumpWaypointTestApp(
        tester,
        dataSource: const WaypointUnavailableDataSource(errorMessage),
      );
      await tester.pumpAndSettle();

      final pageTitle = find.text('Waypoint could not load this view.');
      final errorCopy = find.text(
        'The configured data source reported an error. Demo and network failures remain visible.',
      );
      final retry = find.byKey(const ValueKey<String>('waypoint-retry'));
      final discoverPage = find.byKey(
        const ValueKey<String>('waypoint-discover-page'),
      );
      final demoDestination = find.text('Kyoto, Japan');

      expect(pageTitle, findsOneWidget);
      expect(errorCopy, findsOneWidget);
      expect(find.text(errorMessage), findsOneWidget);
      expect(retry, findsOneWidget);
      expect(discoverPage, findsNothing);
      expect(demoDestination, findsNothing);

      await tester.tap(retry);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(pageTitle, findsOneWidget);
      expect(errorCopy, findsOneWidget);
      expect(find.text(errorMessage), findsOneWidget);
      expect(retry, findsOneWidget);
      expect(discoverPage, findsNothing);
      expect(demoDestination, findsNothing);
    },
  );

  testWidgets('search narrows destinations through the repository seam', (
    tester,
  ) async {
    final source = WaypointTestDataSource();
    await pumpWaypointTestApp(tester, dataSource: source);

    final search = find.byKey(const ValueKey<String>('waypoint-search'));
    await tester.enterText(search, 'Lisbon');
    await tester.pump();
    await tester.pump();

    expect(find.text('Lisbon, Portugal'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-kyoto')),
      findsNothing,
    );
    expect(source.requestedPaths, contains('/api/search'));
  });

  testWidgets(
    'latest search result wins when an earlier response resolves late',
    (tester) async {
      final source = WaypointSearchRaceDataSource();
      addTearDown(source.releaseFirstSearch);
      await pumpWaypointTestApp(tester, dataSource: source);

      final search = find.byKey(const ValueKey<String>('waypoint-search'));
      await tester.enterText(search, 'Lisbon');
      await tester.pump();
      await source.firstSearchGated;

      await tester.enterText(search, 'Kyoto');
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('waypoint-destination-kyoto')),
        findsOneWidget,
      );

      source.releaseFirstSearch();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('waypoint-destination-kyoto')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('waypoint-destination-lisbon')),
        findsNothing,
      );
    },
  );

  testWidgets('Food filter shows Lisbon and hides Kyoto', (tester) async {
    await pumpWaypointTestApp(tester);

    final foodFilter = find.byKey(
      const ValueKey<String>('waypoint-filter-food'),
    );
    await tester.tap(foodFilter);
    await tester.pump();

    expect(tester.widget<ChoiceChip>(foodFilter).selected, isTrue);
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-lisbon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-kyoto')),
      findsNothing,
    );
  });

  testWidgets('bundled local Discover filters its merged destinations', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);

    final lastDestinationCard = find.byKey(
      const ValueKey<String>('waypoint-destination-coastline-table'),
    );
    const maxDestinationLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxDestinationLoadPumps &&
          lastDestinationCard.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(lastDestinationCard, findsOneWidget);

    const destinationIds = <String>[
      'lantern-house',
      'blue-tram-table',
      'aurora-cabin',
      'rose-courtyard',
      'coastline-table',
    ];

    Future<void> expectFilter({
      required String filter,
      required Set<String> included,
    }) async {
      final filterChip = find.byKey(
        ValueKey<String>('waypoint-filter-$filter'),
      );
      await tester.ensureVisible(filterChip);
      await tester.tap(filterChip);
      await tester.pump();

      expect(tester.widget<ChoiceChip>(filterChip).selected, isTrue);
      for (final destinationId in destinationIds) {
        final card = find.byKey(
          ValueKey<String>('waypoint-destination-$destinationId'),
        );
        if (included.contains(destinationId)) {
          await tester.ensureVisible(card);
          expect(card, findsOneWidget);
        } else {
          expect(card, findsNothing);
        }
      }
    }

    await expectFilter(filter: 'stay', included: {'lantern-house'});
    await expectFilter(
      filter: 'food',
      included: {'blue-tram-table', 'coastline-table'},
    );
    await expectFilter(filter: 'nature', included: {'aurora-cabin'});
    await expectFilter(filter: 'culture', included: {'rose-courtyard'});
  });

  testWidgets('search with no matches shows the empty state', (tester) async {
    await pumpWaypointTestApp(tester);

    final search = find.byKey(const ValueKey<String>('waypoint-search'));
    await tester.enterText(search, 'Nowhere');
    await tester.pump();
    await tester.pump();

    expect(find.text('No places match that search yet.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-lisbon')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-kyoto')),
      findsNothing,
    );
  });

  testWidgets('clearing a search restores the home destinations', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    final search = find.byKey(const ValueKey<String>('waypoint-search'));
    await tester.enterText(search, 'Lisbon');
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-lisbon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-kyoto')),
      findsNothing,
    );

    await tester.enterText(search, '');
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-lisbon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-kyoto')),
      findsOneWidget,
    );
  });

  testWidgets('search Retry recovers from one local failure', (tester) async {
    final source = WaypointSearchFailOnceDataSource();
    await pumpWaypointTestApp(tester, dataSource: source);

    final search = find.byKey(const ValueKey<String>('waypoint-search'));
    await tester.enterText(search, 'Lisbon');
    await tester.pump();
    await tester.pump();

    expect(source.searchAttempts, 1);
    expect(
      find.text('Search failed: Bad state: Test search failure'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    final retry = find.text('Retry');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();

    expect(source.searchAttempts, 2);
    expect(
      find.text('Search failed: Bad state: Test search failure'),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-lisbon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-kyoto')),
      findsNothing,
    );
  });

  testWidgets('dismisses the time-limited offer and submits a planning brief', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-offer-action')),
    );
    await tester.pumpAndSettle();

    final destination = find.byKey(
      const ValueKey<String>('waypoint-plan-destination'),
    );
    final submit = find.byKey(const ValueKey<String>('waypoint-plan-submit'));
    expect(destination, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.enterText(destination, 'Lisbon');
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(destination, findsNothing);
    expect(find.text('Your planning brief is ready to review'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-offer-dismiss')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('waypoint-offer-banner')),
      findsNothing,
    );
  });

  testWidgets('restores a dismissed active offer from Settings', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    final banner = find.byKey(const ValueKey<String>('waypoint-offer-banner'));
    expect(banner, findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-offer-dismiss')),
    );
    await tester.pump();
    expect(banner, findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-header-settings')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('waypoint-settings-page')),
      findsOneWidget,
    );
    expect(
      find.text(
        'The offer is currently dismissed. Use Show banner to test it again.',
      ),
      findsOneWidget,
    );
    final showOffer = find.byKey(
      const ValueKey<String>('waypoint-settings-show-offer'),
    );
    await tester.ensureVisible(showOffer);
    await tester.tap(showOffer);
    await tester.pump();
    expect(
      find.text(
        'The offer is currently dismissed. Use Show banner to test it again.',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Discover'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
    expect(banner, findsOneWidget);
  });

  testWidgets(
    'planning sheet validates whitespace and updates travelers and style',
    (tester) async {
      await pumpWaypointTestApp(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('waypoint-offer-action')),
      );
      await tester.pumpAndSettle();

      final destination = find.byKey(
        const ValueKey<String>('waypoint-plan-destination'),
      );
      final submit = find.byKey(const ValueKey<String>('waypoint-plan-submit'));
      await tester.enterText(destination, '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      final travelers = find.byKey(
        const ValueKey<String>('waypoint-plan-travelers'),
      );
      final decrease = find.byKey(
        const ValueKey<String>('waypoint-plan-travelers-decrease'),
      );
      final increase = find.byKey(
        const ValueKey<String>('waypoint-plan-travelers-increase'),
      );
      expect(tester.widget<Text>(travelers).data, '2');

      await tester.tap(decrease);
      await tester.pump();
      expect(tester.widget<Text>(travelers).data, '1');
      expect(tester.widget<IconButton>(decrease).onPressed, isNull);

      await tester.tap(decrease);
      await tester.pump();
      expect(tester.widget<Text>(travelers).data, '1');

      await tester.tap(increase);
      await tester.pump();
      expect(tester.widget<Text>(travelers).data, '2');

      final style = find.byKey(const ValueKey<String>('waypoint-plan-style'));
      await tester.tap(style);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Curious and local'));
      await tester.pump();

      expect(
        tester.widget<DropdownButtonFormField<String>>(style).initialValue,
        'Curious',
      );
    },
  );

  testWidgets('planning sheet opens, cancels, and confirms a date range', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    final plannerEntry = find.byKey(
      const ValueKey<String>('waypoint-offer-action'),
    );
    await tester.ensureVisible(plannerEntry);
    await tester.tap(plannerEntry);
    await tester.pumpAndSettle();

    final dates = find.byKey(const ValueKey<String>('waypoint-plan-dates'));
    expect(dates, findsOneWidget);
    final dateText = find.descendant(of: dates, matching: find.byType(Text));
    expect(dateText, findsOneWidget);
    final initialDateText = tester.widget<Text>(dateText).data!;
    final localizations = MaterialLocalizations.of(tester.element(dates));
    final picker = find.byType(DateRangePickerDialog);

    await tester.tap(dates);
    await tester.pumpAndSettle();
    expect(picker, findsOneWidget);

    final cancel = find.descendant(
      of: picker,
      matching: find.byType(CloseButton),
    );
    expect(cancel, findsOneWidget);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(picker, findsNothing);
    expect(tester.widget<Text>(dateText).data, initialDateText);

    await tester.tap(dates);
    await tester.pumpAndSettle();
    expect(picker, findsOneWidget);

    final dialog = tester.widget<DateRangePickerDialog>(picker);
    final pickerFirstDate = DateUtils.dateOnly(dialog.firstDate);
    final pickerLastDate = DateUtils.dateOnly(dialog.lastDate);
    final initialStartDate = DateUtils.dateOnly(dialog.initialDateRange!.start);
    final monthEnd = DateTime(
      initialStartDate.year,
      initialStartDate.month + 1,
      0,
    );
    final startDate = initialStartDate.day == monthEnd.day
        ? initialStartDate.subtract(const Duration(days: 1))
        : initialStartDate;
    final endDate = startDate.add(const Duration(days: 1));
    final today = DateUtils.dateOnly(DateTime.now());
    expect(!startDate.isBefore(today), isTrue);
    expect(!startDate.isBefore(pickerFirstDate), isTrue);
    expect(!endDate.isAfter(pickerLastDate), isTrue);

    final startDay = find.bySemanticsLabel(
      RegExp(RegExp.escape(localizations.formatFullDate(startDate))),
    );
    expect(startDay, findsOneWidget);
    await tester.tap(startDay);
    await tester.pump();

    final endDay = find.bySemanticsLabel(
      RegExp(RegExp.escape(localizations.formatFullDate(endDate))),
    );
    expect(endDay, findsOneWidget);
    await tester.tap(endDay);
    await tester.pump();

    final confirm = find.descendant(
      of: picker,
      matching: find.text(localizations.saveButtonLabel),
    );
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    final expectedDateText =
        '${localizations.formatMediumDate(startDate)}  to  '
        '${localizations.formatMediumDate(endDate)}';
    expect(tester.widget<Text>(dateText).data, expectedDateText);
  });

  testWidgets(
    'settings controls theme, media visibility, and permission state',
    (tester) async {
      final permissionService = WaypointTestPermissionService();
      await pumpWaypointTestApp(tester, permissionService: permissionService);

      await tester.tap(
        find.byKey(const ValueKey<String>('waypoint-header-settings')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('waypoint-settings-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('waypoint-permission-location')),
        findsOneWidget,
      );
      expect(find.text('Denied'), findsNWidgets(4));

      await tester.tap(find.text('Dark'));
      await tester.pump();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      final locationButton = find.byKey(
        const ValueKey<String>('waypoint-permission-location'),
      );
      await tester.ensureVisible(locationButton);
      await tester.tap(locationButton);
      await tester.pump();
      expect(
        permissionService.requested,
        contains(WaypointPermission.location),
      );

      const remainingPermissions = <WaypointPermission, String>{
        WaypointPermission.notifications: 'waypoint-permission-notifications',
        WaypointPermission.camera: 'waypoint-permission-camera',
        WaypointPermission.photos: 'waypoint-permission-photos',
      };
      for (final entry in remainingPermissions.entries) {
        final permissionButton = find.byKey(ValueKey<String>(entry.value));
        await tester.ensureVisible(permissionButton);
        await tester.tap(permissionButton);
        await tester.pump();

        expect(permissionService.requested, contains(entry.key));
      }
      expect(permissionService.requested, equals(WaypointPermission.values));

      final mediaButton = find.byKey(
        const ValueKey<String>('waypoint-settings-media'),
      );
      await tester.ensureVisible(mediaButton);
      await tester.tap(mediaButton);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('waypoint-video')),
        findsOneWidget,
      );
    },
  );

  testWidgets('bundled local Settings renders permission action copy', (
    tester,
  ) async {
    final source = WaypointAlphaXDataSource(
      client: AlphaXClient(
        transport: WaypointDemoTransport(latency: Duration.zero),
      ),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Test local demo',
      isDemo: true,
    );
    addTearDown(source.close);

    rootBundle.clear();
    await pumpWaypointTestApp(tester, dataSource: source);
    final homePage = find.byKey(
      const ValueKey<String>('waypoint-discover-page'),
    );
    const maxHomeLoadPumps = 40;
    for (
      var attempt = 0;
      attempt < maxHomeLoadPumps && homePage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(homePage, findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-header-settings')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('waypoint-settings-page')),
      findsOneWidget,
    );

    const permissionCopy = <String, String>{
      'Use my location': 'To suggest nearby places while you explore.',
      'Trip reminders': 'To remind you about saved plans and departures.',
      'Capture a travel note': 'To attach a photo to a local demo note.',
      'Choose from library': 'To add a saved image to a local demo note.',
    };
    for (final entry in permissionCopy.entries) {
      expect(find.text(entry.key), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
    }

    final dataMode = find.byKey(const ValueKey<String>('waypoint-data-mode'));
    expect(
      tester.widget<Text>(dataMode).data,
      'Data mode: Test local demo  |  Transport: Waypoint asset fixture',
    );

    final mediaButton = find.byKey(
      const ValueKey<String>('waypoint-settings-media'),
    );
    await tester.ensureVisible(mediaButton);
    await tester.tap(mediaButton);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('waypoint-video')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: mediaButton,
        matching: find.text('Hide video preview'),
      ),
      findsOneWidget,
    );

    await tester.tap(mediaButton);
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('waypoint-video')), findsNothing);
    expect(
      find.descendant(of: mediaButton, matching: find.text('Test video asset')),
      findsOneWidget,
    );
  });

  testWidgets('settings appearance control switches light and system themes', (
    tester,
  ) async {
    await pumpWaypointTestApp(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-header-settings')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final themeChoice = find.byKey(
      const ValueKey<String>('waypoint-theme-choice'),
    );
    expect(
      tester
          .widget<SegmentedButton<WaypointThemeChoice>>(themeChoice)
          .selected
          .single,
      WaypointThemeChoice.system,
    );

    await tester.tap(
      find.descendant(of: themeChoice, matching: find.text('Light')),
    );
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(
      tester
          .widget<SegmentedButton<WaypointThemeChoice>>(themeChoice)
          .selected
          .single,
      WaypointThemeChoice.light,
    );

    await tester.tap(
      find.descendant(of: themeChoice, matching: find.text('System')),
    );
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    expect(
      tester
          .widget<SegmentedButton<WaypointThemeChoice>>(themeChoice)
          .selected
          .single,
      WaypointThemeChoice.system,
    );
  });

  testWidgets('reloads demo data from Settings', (tester) async {
    final home = Map<String, Object?>.from(waypointTestHomePayload());
    final source = WaypointTestDataSource(home: home);
    await pumpWaypointTestApp(tester, dataSource: source);

    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
    expect(find.text('Kyoto, Japan'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-header-settings')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('waypoint-settings-page')),
      findsOneWidget,
    );

    (home['destinations'] as List<Object?>).add(<String, Object?>{
      'id': 'reykjavik-reload',
      'name': 'Reykjavik',
      'country': 'Iceland',
      'summary': 'A bright northern pause between sea, sky, and warm pools.',
      'category': 'Nature',
      'kind': 'nature',
      'locationLabel': 'Reykjavik, Iceland',
      'rating': 4.7,
      'durationLabel': '3 days',
      'imageAsset': 'assets/images/waypoint/lisbon.svg',
      'accentColor': '#B9DED2',
      'tags': <Object?>['geothermal pools', 'coast'],
      'saved': false,
    });

    final reload = find.byKey(
      const ValueKey<String>('waypoint-settings-reload'),
    );
    await tester.ensureVisible(reload);
    await tester.tap(reload);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 220));

    expect(
      source.requestedPaths.where((path) => path == '/api/home').length,
      2,
    );

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Discover')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();

    final reykjavik = find.byKey(
      const ValueKey<String>('waypoint-destination-reykjavik-reload'),
    );
    await tester.ensureVisible(reykjavik);
    expect(reykjavik, findsOneWidget);
    expect(
      find.descendant(of: reykjavik, matching: find.text('Reykjavik')),
      findsOneWidget,
    );
  });

  testWidgets('bottom navigation changes the visible section', (tester) async {
    await pumpWaypointTestApp(tester);

    await tester.tap(find.text('Trips'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('waypoint-trips-page')),
      findsOneWidget,
    );

    await tester.tap(find.text('Activity'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('waypoint-activity-page')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-activity-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start feed'), findsOneWidget);

    expect(
      find.byKey(const ValueKey<String>('waypoint-bottom-navigation')),
      findsOneWidget,
    );
    expect(WaypointSection.values, contains(WaypointSection.activity));
  });

  testWidgets('Activity stream retry recovers from one local failure', (
    tester,
  ) async {
    final source = WaypointActivityFailOnceDataSource();
    await pumpWaypointTestApp(tester, dataSource: source);

    await tester.tap(find.text('Activity'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('waypoint-activity-page')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-activity-toggle')),
    );
    await tester.pumpAndSettle();

    expect(source.activityAttempts, 1);
    expect(
      find.text('Activity failed: Bad state: Test activity stream failure'),
      findsOneWidget,
    );
    final retry = find.byKey(const ValueKey<String>('waypoint-activity-retry'));
    expect(retry, findsOneWidget);

    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(source.activityAttempts, 2);
    expect(
      find.text('Activity failed: Bad state: Test activity stream failure'),
      findsNothing,
    );
    expect(find.text('Kyoto saved to your shortlist'), findsOneWidget);
  });

  testWidgets('stopping Activity cancels before a late update is emitted', (
    tester,
  ) async {
    final source = WaypointActivityCancellationDataSource();
    addTearDown(source.release);
    await pumpWaypointTestApp(tester, dataSource: source);

    await tester.tap(find.text('Activity'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-activity-toggle')),
    );
    await source.started.future;
    await tester.pump();

    expect(find.text('Stop feed'), findsOneWidget);
    expect(find.text('Listening for changes'), findsOneWidget);
    expect(
      find.text(WaypointActivityCancellationDataSource.firstActivityTitle),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-activity-toggle')),
    );
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('waypoint-bottom-navigation')),
        matching: find.text('Activity'),
      ),
    );
    await tester.pump();
    expect(find.text('Start feed'), findsOneWidget);
    expect(find.text('The group is in sync'), findsOneWidget);
    expect(
      find.text(WaypointActivityCancellationDataSource.firstActivityTitle),
      findsOneWidget,
    );
    expect(find.textContaining('Activity failed:'), findsNothing);

    source.release();
    await tester.pumpAndSettle();

    expect(source.cancellationObserved, isTrue);
    expect(
      find.text(WaypointActivityCancellationDataSource.lateActivityTitle),
      findsNothing,
    );
  });

  testWidgets('navigating away from Activity cancels the active feed', (
    tester,
  ) async {
    final source = WaypointActivityCancellationDataSource();
    addTearDown(source.release);
    await pumpWaypointTestApp(tester, dataSource: source);

    final bottomNavigation = find.byKey(
      const ValueKey<String>('waypoint-bottom-navigation'),
    );
    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Activity')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('waypoint-activity-page')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-activity-toggle')),
    );
    await source.started.future;
    await tester.pump();

    expect(find.text('Stop feed'), findsOneWidget);
    expect(
      find.text(WaypointActivityCancellationDataSource.firstActivityTitle),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Trips')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('waypoint-trips-page')),
      findsOneWidget,
    );

    source.release();
    await tester.pumpAndSettle();

    expect(source.cancellationObserved, isTrue);
    expect(
      find.text(WaypointActivityCancellationDataSource.lateActivityTitle),
      findsNothing,
    );

    await tester.tap(
      find.descendant(of: bottomNavigation, matching: find.text('Activity')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('waypoint-activity-page')),
      findsOneWidget,
    );
    expect(find.text('Start feed'), findsOneWidget);
    expect(
      find.text(WaypointActivityCancellationDataSource.lateActivityTitle),
      findsNothing,
    );
  });

  testWidgets('refreshes each permission in the declared order', (
    tester,
  ) async {
    final permissionService = WaypointTestPermissionService();
    await pumpWaypointTestApp(tester, permissionService: permissionService);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-header-settings')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    permissionService.readPermissions.clear();

    final refreshButton = find.byKey(
      const ValueKey<String>('waypoint-permission-refresh'),
    );
    await tester.ensureVisible(refreshButton);
    await tester.tap(refreshButton);
    await tester.pump();
    await tester.pump();

    expect(
      permissionService.readPermissions,
      equals(WaypointPermission.values),
    );
  });

  testWidgets('updates a permission row after request returns a new status', (
    tester,
  ) async {
    final permissionService = WaypointTestPermissionService();
    await pumpWaypointTestApp(tester, permissionService: permissionService);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-header-settings')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('waypoint-settings-page')),
      findsOneWidget,
    );

    final locationButton = find.byKey(
      const ValueKey<String>('waypoint-permission-location'),
    );
    final locationRow = find.ancestor(
      of: locationButton,
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: locationRow, matching: find.text('Denied')),
      findsOneWidget,
    );

    permissionService.statuses[WaypointPermission.location] =
        WaypointPermissionStatus.granted;

    await tester.ensureVisible(locationButton);
    await tester.tap(locationButton);
    await tester.pump();

    expect(
      find.descendant(of: locationRow, matching: find.text('Granted')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: locationRow, matching: find.text('Test')),
      findsOneWidget,
    );
    expect(permissionService.requested, contains(WaypointPermission.location));
  });

  testWidgets('refresh displays the latest status for every permission', (
    tester,
  ) async {
    final permissionService = WaypointTestPermissionService();
    await pumpWaypointTestApp(tester, permissionService: permissionService);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-header-settings')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Denied'), findsNWidgets(4));

    permissionService.statuses.addAll(
      <WaypointPermission, WaypointPermissionStatus>{
        WaypointPermission.location: WaypointPermissionStatus.granted,
        WaypointPermission.notifications: WaypointPermissionStatus.restricted,
        WaypointPermission.camera: WaypointPermissionStatus.limited,
        WaypointPermission.photos: WaypointPermissionStatus.provisional,
      },
    );

    final refreshButton = find.byKey(
      const ValueKey<String>('waypoint-permission-refresh'),
    );
    await tester.ensureVisible(refreshButton);
    await tester.tap(refreshButton);
    await tester.pump();
    await tester.pump();

    const expectedStatuses = <WaypointPermission, String>{
      WaypointPermission.location: 'Granted',
      WaypointPermission.notifications: 'Restricted',
      WaypointPermission.camera: 'Limited',
      WaypointPermission.photos: 'Provisional',
    };
    for (final entry in expectedStatuses.entries) {
      final row = find.ancestor(
        of: find.byKey(
          ValueKey<String>('waypoint-permission-${entry.key.name}'),
        ),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: row, matching: find.text(entry.value)),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'refresh routes a newly permanently denied permission to settings',
    (tester) async {
      final permissionService = WaypointTestPermissionService();
      await pumpWaypointTestApp(tester, permissionService: permissionService);

      await tester.tap(
        find.byKey(const ValueKey<String>('waypoint-header-settings')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      permissionService.statuses[WaypointPermission.camera] =
          WaypointPermissionStatus.permanentlyDenied;

      final refreshButton = find.byKey(
        const ValueKey<String>('waypoint-permission-refresh'),
      );
      await tester.ensureVisible(refreshButton);
      await tester.tap(refreshButton);
      await tester.pump();
      await tester.pump();

      final cameraButton = find.byKey(
        const ValueKey<String>('waypoint-permission-camera'),
      );
      await tester.ensureVisible(cameraButton);
      final cameraRow = find.ancestor(
        of: cameraButton,
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: cameraRow,
          matching: find.text('Permanently denied'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cameraRow, matching: find.text('Settings')),
        findsOneWidget,
      );

      final openSettingsCallsBefore = permissionService.openSettingsCalls;
      await tester.tap(cameraButton);
      await tester.pump();

      expect(
        permissionService.openSettingsCalls,
        greaterThan(openSettingsCallsBefore),
      );
      expect(
        permissionService.requested,
        isNot(contains(WaypointPermission.camera)),
      );
    },
  );

  testWidgets(
    'refresh routes remaining permanently denied permissions to settings',
    (tester) async {
      final permissionService = WaypointTestPermissionService();
      await pumpWaypointTestApp(tester, permissionService: permissionService);

      await tester.tap(
        find.byKey(const ValueKey<String>('waypoint-header-settings')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      const remainingPermissions = <WaypointPermission, String>{
        WaypointPermission.location: 'waypoint-permission-location',
        WaypointPermission.notifications: 'waypoint-permission-notifications',
        WaypointPermission.photos: 'waypoint-permission-photos',
      };
      for (final entry in remainingPermissions.entries) {
        permissionService.statuses[entry.key] =
            WaypointPermissionStatus.permanentlyDenied;

        final refreshButton = find.byKey(
          const ValueKey<String>('waypoint-permission-refresh'),
        );
        await tester.ensureVisible(refreshButton);
        await tester.tap(refreshButton);
        await tester.pump();
        await tester.pump();

        final permissionButton = find.byKey(ValueKey<String>(entry.value));
        await tester.ensureVisible(permissionButton);
        final permissionRow = find.ancestor(
          of: permissionButton,
          matching: find.byType(ListTile),
        );
        expect(
          find.descendant(
            of: permissionRow,
            matching: find.text('Permanently denied'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: permissionRow, matching: find.text('Settings')),
          findsOneWidget,
        );

        final openSettingsCallsBefore = permissionService.openSettingsCalls;
        await tester.tap(permissionButton);
        await tester.pump();

        expect(
          permissionService.openSettingsCalls,
          greaterThan(openSettingsCallsBefore),
        );
        expect(permissionService.requested, isNot(contains(entry.key)));
      }
    },
  );

  testWidgets(
    'permanently denied permission keeps its status and opens settings',
    (tester) async {
      final permissionService = WaypointTestPermissionService(
        statuses: <WaypointPermission, WaypointPermissionStatus>{
          WaypointPermission.location:
              WaypointPermissionStatus.permanentlyDenied,
        },
      );
      await pumpWaypointTestApp(tester, permissionService: permissionService);

      await tester.tap(
        find.byKey(const ValueKey<String>('waypoint-header-settings')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('Permanently denied'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('waypoint-permission-location')),
      );
      await tester.pump();

      expect(permissionService.openSettingsCalls, 1);
      expect(
        permissionService.requested,
        isNot(contains(WaypointPermission.location)),
      );
    },
  );

  testWidgets('destination cards fit a narrow phone viewport', (tester) async {
    tester.view.physicalSize = const Size(432, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpWaypointTestApp(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('waypoint-destination-kyoto')),
      findsOneWidget,
    );
  });

  testWidgets('wide layout starts at exactly 900 logical pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpWaypointTestApp(tester);

    expect(find.byType(WaypointNavigationRail), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('waypoint-bottom-navigation')),
      findsNothing,
    );
  });

  testWidgets('horizontal SafeArea padding uses the available width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    const horizontalPadding = FakeViewPadding(left: 20, right: 20);
    tester.view.padding = horizontalPadding;
    tester.view.viewPadding = horizontalPadding;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await pumpWaypointTestApp(tester);

    expect(find.byType(WaypointNavigationRail), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('waypoint-bottom-navigation')),
      findsOneWidget,
    );

    final settingsButton = find.byKey(
      const ValueKey<String>('waypoint-header-settings'),
    );
    expect(settingsButton, findsOneWidget);

    final semanticsHandle = tester.ensureSemantics();
    try {
      expect(tester.getSemantics(settingsButton).tooltip, 'Open settings');
    } finally {
      semanticsHandle.dispose();
    }

    await tester.tap(settingsButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('waypoint-settings-page')),
      findsOneWidget,
    );
  });

  testWidgets('wide layout uses the navigation rail for section navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpWaypointTestApp(tester);

    expect(find.byType(WaypointNavigationRail), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('waypoint-bottom-navigation')),
      findsNothing,
    );

    final saveButton = find.byKey(
      const ValueKey<String>('waypoint-save-kyoto'),
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    final savedNavigation = find.byKey(
      const ValueKey<String>('waypoint-nav-saved'),
    );
    await tester.tap(savedNavigation);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('waypoint-saved-page')),
      findsOneWidget,
    );

    final destinationCard = find.byKey(
      const ValueKey<String>('waypoint-destination-kyoto'),
    );
    await tester.ensureVisible(destinationCard);
    await tester.tap(destinationCard);
    await tester.pumpAndSettle();

    final openDiscover = find.byKey(
      const ValueKey<String>('waypoint-saved-detail-discover'),
    );
    expect(openDiscover, findsOneWidget);
    await tester.tap(openDiscover);
    await tester.pumpAndSettle();

    final selectedContext = find.byKey(
      const ValueKey<String>('waypoint-discover-selected-context'),
    );
    expect(selectedContext, findsOneWidget);
    expect(
      find.descendant(
        of: selectedContext,
        matching: find.text('Comparing Kyoto, Japan with the full list.'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('waypoint-nav-trips')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('waypoint-trips-page')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-nav-discover')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('waypoint-discover-page')),
      findsOneWidget,
    );
    expect(selectedContext, findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-nav-settings')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('waypoint-settings-page')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-nav-activity')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('waypoint-activity-page')),
      findsOneWidget,
    );
  });
}

final class _BundledRoutePreviewVideoPlayerPlatform
    extends VideoPlayerPlatform {
  final List<VideoCreationOptions> creationOptions = <VideoCreationOptions>[];
  final Map<int, StreamController<VideoEvent>> _eventStreams =
      <int, StreamController<VideoEvent>>{};
  int _nextPlayerId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = _nextPlayerId++;
    final eventStream = StreamController<VideoEvent>();
    creationOptions.add(options);
    _eventStreams[playerId] = eventStream;
    eventStream.onListen = () {
      scheduleMicrotask(() {
        if (eventStream.isClosed) {
          return;
        }
        eventStream.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 1),
            size: const Size(640, 360),
          ),
        );
      });
    };
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _eventStreams[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Future<void> dispose(int playerId) async {
    final eventStream = _eventStreams.remove(playerId);
    if (eventStream != null && !eventStream.isClosed) {
      unawaited(eventStream.close());
    }
  }
}
