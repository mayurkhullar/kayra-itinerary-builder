import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';
import 'package:kayra_crm_v1/features/trips/domain/kayra_trip.dart';
import 'package:kayra_crm_v1/features/trips/presentation/pages/trip_workspace_page.dart';
import 'package:kayra_crm_v1/features/trips/presentation/widgets/my_trips_list.dart';
import 'package:kayra_crm_v1/shared/widgets/kayra_app_header.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_client_repository.dart';
import 'support/fake_supplier_source_repository.dart';
import 'support/fake_trip_repository.dart';
import 'support/fake_user_profile_repository.dart';

KayraTrip _trip({TripStatus status = TripStatus.draft}) => KayraTrip.fromMap({
  'clientId': 'client-1',
  'clientFirstName': 'Mayur',
  'clientLastName': 'Sharma',
  'tripName': 'Mayur Sharma – Dubai & Abu Dhabi – Dec 2026',
  'destinations': ['Dubai', 'Abu Dhabi'],
  'travelStartDate': DateTime.utc(2026, 12, 12),
  'numberOfNights': 5,
  'adults': 2,
  'children': 1,
  'infants': 0,
  'hotelCategory': '5_star',
  'tripType': 'fit',
  'status': status.value,
  'ownerUid': 'test-user',
  'createdByUid': 'test-user',
  'createdAt': DateTime.utc(2026, 9, 1),
  'updatedAt': DateTime.utc(2026, 9, 25),
}, documentId: 'trip-1');

SupplierSourcePackage _package({
  required String id,
  required SupplierSourcePackageStatus status,
  String? supplierId,
  String? supplierName,
  List<String> fileIds = const [],
  int day = 25,
}) => SupplierSourcePackage(
  id: id,
  tripId: 'trip-1',
  supplierId: supplierId,
  supplierNameSnapshot: supplierName,
  fileIds: fileIds,
  uploadedByUid: 'test-user',
  createdAt: DateTime.utc(2026, 9, day),
  updatedAt: DateTime.utc(2026, 9, day),
  status: status,
);

void main() {
  late FakeTripRepository trips;
  late FakeSupplierSourceRepository sources;

  setUp(() {
    trips = FakeTripRepository(clients: FakeClientRepository())
      ..trips.add(_trip());
    sources = FakeSupplierSourceRepository();
  });

  void viewport(WidgetTester tester, double width, {double height = 1000}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> show(WidgetTester tester, {bool settle = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DashboardPage(
          user: testProfile(TestUser()),
          onSignOut: () {},
          userProfileRepository: FakeUserProfileRepository(),
          clientRepository: FakeClientRepository(),
          tripRepository: trips,
          supplierSourceRepository: sources,
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> openTrip(WidgetTester tester, {bool settle = true}) async {
    await tester.ensureVisible(find.byKey(const ValueKey('trip-trip-1')));
    await tester.tap(find.byKey(const ValueKey('trip-trip-1')));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  for (final width in <double>[390, 1440]) {
    testWidgets(
      '${width.toInt()}px Trip row opens workspace and reloads Trip',
      (tester) async {
        viewport(tester, width);
        await show(tester);
        expect(find.byType(MyTripsList), findsOneWidget);
        expect(trips.tripQueries, isEmpty);
        await openTrip(tester);
        expect(trips.tripQueries, ['trip-1']);
        expect(find.byType(TripWorkspacePage), findsOneWidget);
        expect(find.byType(KayraAppHeader), findsOneWidget);
        expect(find.text(_trip().tripName), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('workspace renders read-only Trip dossier details', (
    tester,
  ) async {
    viewport(tester, 1440);
    trips.trips[0] = _trip(status: TripStatus.sentToClient);
    await show(tester);
    await openTrip(tester);

    expect(find.text('Sent to Client'), findsOneWidget);
    expect(
      find.widgetWithText(ButtonStyleButton, 'Sent to Client'),
      findsNothing,
    );
    expect(find.textContaining('Mayur Sharma'), findsWidgets);
    expect(find.text('Dubai · Abu Dhabi'), findsOneWidget);
    expect(find.text('12–17 Dec 2026'), findsWidgets);
    expect(find.text('5 nights'), findsWidgets);
    expect(find.text('2 Adults · 1 Child · 0 Infants'), findsWidgets);
    expect(find.text('5 Star'), findsOneWidget);
    expect(find.text('FIT'), findsOneWidget);
    expect(find.text('Itinerary'), findsNothing);
    expect(find.text('Quotes'), findsNothing);
    expect(find.text('Payments'), findsNothing);
  });

  testWidgets('Trip loading keeps authenticated header visible', (
    tester,
  ) async {
    final pending = Completer<void>();
    trips.beforeGet = () => pending.future;
    await show(tester);
    await openTrip(tester, settle: false);
    expect(find.byType(KayraAppHeader), findsOneWidget);
    expect(
      find.byKey(const ValueKey('trip-workspace-loading')),
      findsOneWidget,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trip-workspace-title')), findsOneWidget);
  });

  testWidgets(
    'Supplier Sources exposes loading then empty state without upload',
    (tester) async {
      final pending = Completer<void>();
      sources.beforePackageList = () => pending.future;
      await show(tester);
      await openTrip(tester, settle: false);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('supplier-sources-loading')),
        findsOneWidget,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('No supplier sources yet'), findsOneWidget);
      expect(
        find.text(
          'Supplier quotations and itinerary files will appear here once added.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Upload'), findsNothing);
      expect(sources.packageQueries, ['trip-1']);
    },
  );

  testWidgets('existing packages render safe read-only fields and statuses', (
    tester,
  ) async {
    viewport(tester, 1440);
    sources.packages.addAll([
      _package(
        id: 'uploaded',
        status: SupplierSourcePackageStatus.uploaded,
        supplierId: 'supplier-1',
        supplierName: 'Atlas DMC',
        fileIds: ['file-1', 'file-2'],
      ),
      _package(
        id: 'uploading',
        status: SupplierSourcePackageStatus.uploading,
        day: 24,
      ),
      _package(
        id: 'failed',
        status: SupplierSourcePackageStatus.failed,
        day: 23,
      ),
    ]);
    await show(tester);
    await openTrip(tester);

    expect(find.text('Atlas DMC'), findsOneWidget);
    expect(find.text('Supplier not assigned'), findsNWidgets(2));
    expect(find.text('2 files'), findsOneWidget);
    expect(find.text('0 files'), findsNWidgets(2));
    expect(find.text('Uploaded'), findsOneWidget);
    expect(find.text('Uploading'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('25 Sep 2026'), findsOneWidget);
    for (final privateValue in [
      'uploaded',
      'uploading',
      'failed',
      'test-user',
      'supplier-1',
      'file-1',
    ]) {
      expect(find.text(privateValue), findsNothing);
    }
  });

  testWidgets('Supplier Source failure is safe and supports retry', (
    tester,
  ) async {
    sources.packageListError = StateError('private Firestore details');
    await show(tester);
    await openTrip(tester);
    expect(find.text('Supplier sources couldn’t be loaded.'), findsOneWidget);
    expect(find.textContaining('private Firestore'), findsNothing);
    sources.packageListError = null;
    final retry = find.widgetWithText(OutlinedButton, 'Try again');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('No supplier sources yet'), findsOneWidget);
    expect(sources.packageQueries, ['trip-1', 'trip-1']);
  });

  testWidgets('Trip unavailable hides errors and returns to My Trips', (
    tester,
  ) async {
    await show(tester);
    trips.getError = StateError('private permission-denied details');
    await openTrip(tester);
    expect(find.text('Trip unavailable'), findsOneWidget);
    expect(
      find.text(
        'This trip could not be loaded or you no longer have access to it.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('permission-denied'), findsNothing);
    expect(sources.packageQueries, isEmpty);
    await tester.tap(find.byKey(const ValueKey('back-to-my-trips')));
    await tester.pumpAndSettle();
    expect(find.byType(MyTripsList), findsOneWidget);
  });

  testWidgets('workspace Back and global My Trips return to list', (
    tester,
  ) async {
    viewport(tester, 1440);
    await show(tester);
    await openTrip(tester);
    await tester.tap(find.byKey(const ValueKey('back-to-my-trips')));
    await tester.pumpAndSettle();
    expect(find.byType(MyTripsList), findsOneWidget);

    await openTrip(tester);
    await tester.tap(find.widgetWithText(TextButton, 'My Trips'));
    await tester.pumpAndSettle();
    expect(find.byType(MyTripsList), findsOneWidget);
  });

  for (final width in <double>[375, 390, 430, 1440, 1920]) {
    testWidgets('workspace has no overflow at ${width.toInt()}px', (
      tester,
    ) async {
      viewport(tester, width, height: 800);
      sources.packages.add(
        _package(
          id: 'package',
          status: SupplierSourcePackageStatus.uploaded,
          supplierId: 'supplier',
          supplierName: 'A supplier with a long but readable company name',
          fileIds: ['one'],
        ),
      );
      await show(tester);
      await openTrip(tester);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('trip-workspace-scroll')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      expect(find.text('Supplier Sources'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
