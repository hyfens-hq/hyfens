import 'package:conformance/waypoint/platform/waypoint_permission.dart';
import 'package:conformance/waypoint/platform/waypoint_permission_result.dart';
import 'package:conformance/waypoint/presentation/widgets/waypoint_permission_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders granted status with a Test action', (tester) async {
    await _pumpPermissionRow(
      tester,
      status: WaypointPermissionStatus.granted,
      onRequest: () {},
    );

    expect(find.text('Granted'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets(
    'renders not checked state with a Test action and invokes the callback',
    (tester) async {
      var requestCount = 0;
      await _pumpPermissionRow(
        tester,
        status: null,
        onRequest: () => requestCount++,
      );

      expect(find.text('Not checked'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('waypoint-permission-camera')),
      );
      await tester.pump();

      expect(requestCount, 1);
    },
  );

  testWidgets('renders denied status and invokes the request callback', (
    tester,
  ) async {
    var requestCount = 0;
    await _pumpPermissionRow(
      tester,
      status: WaypointPermissionStatus.denied,
      onRequest: () => requestCount++,
    );

    expect(find.text('Denied'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('waypoint-permission-camera')),
    );
    await tester.pump();

    expect(requestCount, 1);
  });

  testWidgets('renders permanently denied status with a Settings action', (
    tester,
  ) async {
    await _pumpPermissionRow(
      tester,
      status: WaypointPermissionStatus.permanentlyDenied,
      onRequest: () {},
    );

    expect(find.text('Permanently denied'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Test'), findsNothing);
  });

  testWidgets(
    'invokes the callback for a permanently denied Settings action',
    (tester) async {
      var requestCount = 0;
      await _pumpPermissionRow(
        tester,
        status: WaypointPermissionStatus.permanentlyDenied,
        onRequest: () => requestCount++,
      );

      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('waypoint-permission-camera')),
      );
      await tester.pump();

      expect(requestCount, 1);
    },
  );

  testWidgets('renders restricted status with a Test action', (tester) async {
    await _pumpPermissionRow(
      tester,
      status: WaypointPermissionStatus.restricted,
      onRequest: () {},
    );

    expect(find.text('Restricted'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets('renders limited status with a Test action', (tester) async {
    await _pumpPermissionRow(
      tester,
      status: WaypointPermissionStatus.limited,
      onRequest: () {},
    );

    expect(find.text('Limited'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets('renders provisional status with a Test action', (tester) async {
    await _pumpPermissionRow(
      tester,
      status: WaypointPermissionStatus.provisional,
      onRequest: () {},
    );

    expect(find.text('Provisional'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets('renders unknown status with a Test action', (tester) async {
    await _pumpPermissionRow(
      tester,
      status: WaypointPermissionStatus.unknown,
      onRequest: () {},
    );

    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets('renders the label for each permission', (tester) async {
    const labels = <WaypointPermission, String>{
      WaypointPermission.location: 'Location',
      WaypointPermission.notifications: 'Notifications',
      WaypointPermission.camera: 'Camera',
      WaypointPermission.photos: 'Photo library',
    };

    for (final entry in labels.entries) {
      await _pumpPermissionRow(
        tester,
        permission: entry.key,
        status: WaypointPermissionStatus.granted,
        onRequest: () {},
      );

      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets(
    'renders the mapped icon and stable action key for each permission',
    (tester) async {
      const icons = <WaypointPermission, IconData>{
        WaypointPermission.location: Icons.location_on_outlined,
        WaypointPermission.notifications: Icons.notifications_none_rounded,
        WaypointPermission.camera: Icons.camera_alt_outlined,
        WaypointPermission.photos: Icons.photo_library_outlined,
      };

      for (final entry in icons.entries) {
        await _pumpPermissionRow(
          tester,
          permission: entry.key,
          status: WaypointPermissionStatus.granted,
          onRequest: () {},
        );

        expect(find.byIcon(entry.value), findsOneWidget);
        expect(
          find.byKey(ValueKey<String>('waypoint-permission-${entry.key.name}')),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('invokes the callback for each permission action key', (
    tester,
  ) async {
    const permissions = <WaypointPermission>[
      WaypointPermission.location,
      WaypointPermission.notifications,
      WaypointPermission.camera,
      WaypointPermission.photos,
    ];

    for (final permission in permissions) {
      WaypointPermission? receivedPermission;
      await _pumpPermissionRow(
        tester,
        permission: permission,
        status: WaypointPermissionStatus.granted,
        onRequest: () => receivedPermission = permission,
      );

      await tester.tap(
        find.byKey(ValueKey<String>('waypoint-permission-${permission.name}')),
      );
      await tester.pump();

      expect(receivedPermission, permission);
    }
  });
}

Future<void> _pumpPermissionRow(
  WidgetTester tester, {
  WaypointPermission permission = WaypointPermission.camera,
  required WaypointPermissionStatus? status,
  required VoidCallback onRequest,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WaypointPermissionRow(
          permission: permission,
          result: status == null
              ? null
              : WaypointPermissionResult(
                  permission: permission,
                  status: status,
                ),
          onRequest: onRequest,
        ),
      ),
    ),
  );
  await tester.pump();
}
