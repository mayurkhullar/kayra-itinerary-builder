import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_upload_dependencies.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_candidate.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_failure.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_progress.dart';
import 'package:kayra_crm_v1/features/supplier_sources/presentation/widgets/supplier_sources_section.dart';
import 'package:kayra_crm_v1/features/suppliers/domain/kayra_supplier.dart';
import 'package:kayra_crm_v1/features/suppliers/presentation/widgets/supplier_form.dart';
import 'package:kayra_crm_v1/features/trips/domain/kayra_trip.dart';
import 'package:kayra_crm_v1/features/trips/presentation/pages/trip_workspace_page.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_client_repository.dart';
import 'support/fake_supplier_repository.dart';
import 'support/fake_supplier_source_repository.dart';
import 'support/fake_supplier_source_upload.dart';
import 'support/fake_trip_repository.dart';
import 'support/fake_user_profile_repository.dart';

KayraTrip _trip() => KayraTrip.fromMap({
  'clientId': 'client-1',
  'clientFirstName': 'Maya',
  'clientLastName': 'Kapoor',
  'tripName': 'Maya Kapoor – Tokyo & Kyoto – Nov 2026',
  'destinations': ['Tokyo', 'Kyoto'],
  'travelStartDate': DateTime.utc(2026, 11, 10),
  'numberOfNights': 7,
  'adults': 2,
  'children': 0,
  'infants': 0,
  'hotelCategory': '5_star',
  'tripType': 'fit',
  'status': 'draft',
  'ownerUid': 'authenticated-user',
  'createdByUid': 'authenticated-user',
  'createdAt': DateTime.utc(2026, 9, 1),
  'updatedAt': DateTime.utc(2026, 9, 26),
}, documentId: 'trip-1');

KayraSupplier _supplier({
  required String id,
  required String name,
  SupplierStatus status = SupplierStatus.active,
  List<String> destinations = const [],
}) => KayraSupplier(
  id: id,
  details: SupplierDetails(name: name, destinationCoverage: destinations),
  status: status,
  createdByUid: 'admin-user',
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 26),
);

SupplierSourceUploadCandidate _candidate(String name, {int size = 128}) =>
    SupplierSourceUploadCandidate(
      originalFileName: name,
      bytes: Uint8List.fromList(List<int>.filled(size, 7)),
    );

SupplierSourcePackage _package({
  required SupplierSourcePackageStatus status,
  String? supplierId,
  String? supplierName,
  List<String> fileIds = const [],
}) => SupplierSourcePackage(
  id: 'package-${status.value}',
  tripId: 'trip-1',
  supplierId: supplierId,
  supplierNameSnapshot: supplierName,
  fileIds: fileIds,
  uploadedByUid: 'authenticated-user',
  createdAt: DateTime.utc(2026, 9, 26),
  updatedAt: DateTime.utc(2026, 9, 26),
  status: status,
);

void main() {
  late FakeSupplierRepository suppliers;
  late FakeSupplierSourceRepository sources;
  late FakeSupplierSourceFilePicker picker;
  late FakeSupplierSourceUploadExecutor executor;
  late SupplierSourceUploadDependencies dependencies;

  setUp(() {
    suppliers = FakeSupplierRepository();
    sources = FakeSupplierSourceRepository();
    picker = FakeSupplierSourceFilePicker();
    executor = FakeSupplierSourceUploadExecutor();
    dependencies = SupplierSourceUploadDependencies(
      picker: picker,
      executor: executor,
    );
  });

  void viewport(WidgetTester tester, double width, {double height = 900}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> showSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SupplierSourcesSection(
              tripId: 'trip-1',
              uploadedByUid: 'authenticated-user',
              repository: sources,
              supplierRepository: suppliers,
              uploadDependencies: dependencies,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    final add = find.byKey(const ValueKey('add-supplier-source'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
  }

  Future<void> chooseFiles(WidgetTester tester) async {
    final choose = find.byKey(const ValueKey('choose-supplier-source-files'));
    await tester.ensureVisible(choose);
    await tester.pumpAndSettle();
    await tester.tap(choose);
    await tester.pumpAndSettle();
  }

  Future<void> openCreateSupplier(WidgetTester tester) async {
    final action = find.byKey(const ValueKey('add-new-supplier'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(SupplierForm), findsOneWidget);
  }

  Future<void> fillNewSupplier(
    WidgetTester tester, {
    String name = 'New Horizon DMC',
  }) async {
    for (final entry in <String, String>{
      'supplier-name': name,
      'supplier-contact-0-Name': 'Asha Rao',
      'supplier-contact-0-Phone': '+91 98765 43210',
    }.entries) {
      final field = find.byKey(ValueKey(entry.key));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
      await tester.pump();
    }
  }

  Future<void> cancelCreateSupplier(WidgetTester tester) async {
    final cancel = find.descendant(
      of: find.byType(SupplierForm),
      matching: find.widgetWithText(TextButton, 'Cancel'),
    );
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
  }

  Future<void> settleSuccessfulUpload(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  Finder uploadButton() => find.byKey(const ValueKey('upload-supplier-source'));

  testWidgets(
    'Add Supplier Source opens with optional Supplier and active choices only',
    (tester) async {
      suppliers.suppliers.addAll([
        _supplier(
          id: 'active-1',
          name: 'Atlas DMC',
          destinations: ['Japan', 'South Korea'],
        ),
        _supplier(
          id: 'inactive-1',
          name: 'Legacy DMC',
          status: SupplierStatus.inactive,
        ),
      ]);
      await showSection(tester);

      expect(find.text('No supplier sources yet'), findsOneWidget);
      await openDialog(tester);

      expect(find.text('Add Supplier Source'), findsNWidgets(2));
      expect(
        find.text(
          'Upload the supplier quotation or itinerary files received for this trip.',
        ),
        findsOneWidget,
      );
      expect(find.text('Supplier not assigned'), findsOneWidget);
      expect(find.text('+ Add new supplier'), findsOneWidget);
      expect(find.text('Atlas DMC'), findsOneWidget);
      expect(find.text('Legacy DMC'), findsNothing);
      expect(tester.widget<FilledButton>(uploadButton()).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('supplier-source-supplier-search')),
        'korea',
      );
      await tester.pump();
      expect(find.text('Atlas DMC'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling Supplier creation preserves upload state', (
    tester,
  ) async {
    suppliers.suppliers.add(
      _supplier(id: 'selected-1', name: 'Selected Supplier'),
    );
    picker.selections.add([_candidate('selected quote.pdf')]);
    await showSection(tester);
    await openDialog(tester);
    await tester.tap(find.byKey(const ValueKey('supplier-option-selected-1')));
    await chooseFiles(tester);

    await openCreateSupplier(tester);
    await cancelCreateSupplier(tester);

    expect(
      find.byKey(const ValueKey('supplier-source-upload-dialog')),
      findsOneWidget,
    );
    expect(find.text('selected quote.pdf'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('supplier-option-selected-1')),
        matching: find.byIcon(Icons.radio_button_checked_rounded),
      ),
      findsOneWidget,
    );
    expect(picker.calls, 1);
    expect(suppliers.creations, isEmpty);
  });

  testWidgets(
    'created Supplier refreshes, auto-selects, and supplies ID and snapshot',
    (tester) async {
      suppliers.suppliers.add(
        _supplier(
          id: 'inactive-1',
          name: 'Inactive Supplier',
          status: SupplierStatus.inactive,
        ),
      );
      picker.selections.add([_candidate('new supplier quote.pdf')]);
      await showSection(tester);
      await openDialog(tester);
      expect(find.text('Inactive Supplier'), findsNothing);
      await chooseFiles(tester);
      await openCreateSupplier(tester);
      await fillNewSupplier(tester);
      final create = find.descendant(
        of: find.byType(SupplierForm),
        matching: find.widgetWithText(FilledButton, 'Create Supplier'),
      );
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();

      expect(find.byType(SupplierForm), findsNothing);
      expect(find.text('new supplier quote.pdf'), findsOneWidget);
      expect(find.text('New Horizon DMC'), findsOneWidget);
      expect(find.text('Inactive Supplier'), findsNothing);
      expect(suppliers.listCalls, 2);
      expect(suppliers.creations.single.uid, 'authenticated-user');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('supplier-option-created-1')),
          matching: find.byIcon(Icons.radio_button_checked_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(uploadButton());
      await settleSuccessfulUpload(tester);
      expect(executor.calls.single.supplierId, 'created-1');
      expect(executor.calls.single.supplierNameSnapshot, 'New Horizon DMC');
    },
  );

  testWidgets('nested Supplier creation failure is safe and retryable', (
    tester,
  ) async {
    picker.selections.add([_candidate('retained quote.pdf')]);
    suppliers.beforeSave = () async => throw StateError('private Firestore');
    await showSection(tester);
    await openDialog(tester);
    await chooseFiles(tester);
    await openCreateSupplier(tester);
    await fillNewSupplier(tester);
    final create = find.descendant(
      of: find.byType(SupplierForm),
      matching: find.widgetWithText(FilledButton, 'Create Supplier'),
    );
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(find.byType(SupplierForm), findsOneWidget);
    expect(
      find.text('Supplier couldn’t be created. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private Firestore'), findsNothing);
    await cancelCreateSupplier(tester);
    expect(find.text('retained quote.pdf'), findsOneWidget);
  });

  testWidgets('picker selections keep order, allow additions and removal', (
    tester,
  ) async {
    picker.selections.addAll([
      [_candidate('first quotation.pdf'), _candidate('second rates.xlsx')],
      [_candidate('third notes.txt')],
    ]);
    await showSection(tester);
    await openDialog(tester);
    await chooseFiles(tester);

    final first = find.text('first quotation.pdf');
    final second = find.text('second rates.xlsx');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(find.text('Add more files'), findsOneWidget);
    expect(tester.widget<FilledButton>(uploadButton()).onPressed, isNotNull);

    await chooseFiles(tester);
    final third = find.text('third notes.txt');
    expect(third, findsOneWidget);
    expect(tester.getTopLeft(second).dy, lessThan(tester.getTopLeft(third).dy));
    expect(picker.calls, 2);

    await tester.tap(find.byTooltip('Remove second rates.xlsx'));
    await tester.pump();
    expect(second, findsNothing);
    await tester.tap(find.byTooltip('Remove first quotation.pdf'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove third notes.txt'));
    await tester.pump();
    expect(tester.widget<FilledButton>(uploadButton()).onPressed, isNull);
  });

  testWidgets(
    'Dashboard passes trip, authenticated UID and Supplier snapshot',
    (tester) async {
      viewport(tester, 1440);
      final trips = FakeTripRepository(clients: FakeClientRepository())
        ..trips.add(_trip());
      suppliers.suppliers.add(
        _supplier(id: 'supplier-1', name: 'Sakura Ground Services'),
      );
      picker.selections.add([_candidate('quote.pdf'), _candidate('rates.csv')]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DashboardPage(
            user: testProfile(TestUser(uid: 'authenticated-user')),
            onSignOut: () {},
            userProfileRepository: FakeUserProfileRepository(),
            clientRepository: FakeClientRepository(),
            tripRepository: trips,
            supplierRepository: suppliers,
            supplierSourceRepository: sources,
            supplierSourceUploadDependencies: dependencies,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('trip-trip-1')));
      await tester.tap(find.byKey(const ValueKey('trip-trip-1')));
      await tester.pumpAndSettle();
      await openDialog(tester);
      await tester.tap(
        find.byKey(const ValueKey('supplier-option-supplier-1')),
      );
      await chooseFiles(tester);
      await tester.tap(uploadButton());
      await settleSuccessfulUpload(tester);

      expect(executor.calls, hasLength(1));
      final call = executor.calls.single;
      expect(call.tripId, 'trip-1');
      expect(call.uploadedByUid, 'authenticated-user');
      expect(call.supplierId, 'supplier-1');
      expect(call.supplierNameSnapshot, 'Sakura Ground Services');
      expect(call.candidates.map((candidate) => candidate.originalFileName), [
        'quote.pdf',
        'rates.csv',
      ]);
      expect(find.byType(TripWorkspacePage), findsOneWidget);
    },
  );

  testWidgets('Supplier load failure permits an unassigned upload', (
    tester,
  ) async {
    suppliers.beforeLoad = () async => throw StateError('private details');
    picker.selections.add([_candidate('quote.pdf')]);
    await showSection(tester);
    await openDialog(tester);

    expect(
      find.text(
        'Suppliers couldn’t be loaded. You can continue without assigning one.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('private details'), findsNothing);
    await chooseFiles(tester);
    await tester.tap(uploadButton());
    await settleSuccessfulUpload(tester);

    expect(executor.calls.single.supplierId, isNull);
    expect(executor.calls.single.supplierNameSnapshot, isNull);
  });

  testWidgets('picker validation issues render safe human messages', (
    tester,
  ) async {
    await showSection(tester);
    await openDialog(tester);
    const cases = <SupplierSourceUploadValidationIssue, String>{
      SupplierSourceUploadValidationIssue.unsupportedType:
          'This file type isn’t supported.',
      SupplierSourceUploadValidationIssue.tooLarge:
          'Each file must be 25 MB or smaller.',
      SupplierSourceUploadValidationIssue.emptyFile:
          'This file is empty and can’t be uploaded.',
    };
    for (final entry in cases.entries) {
      picker.error = SupplierSourceUploadFailure(
        SupplierSourceUploadFailureKind.validation,
        validationIssue: entry.key,
      );
      await chooseFiles(tester);
      expect(find.text(entry.value), findsOneWidget);
    }
    expect(find.textContaining('SupplierSourceUploadFailure'), findsNothing);
  });

  testWidgets('active upload locks controls and renders emitted progress', (
    tester,
  ) async {
    final completion = Completer<CompletedSupplierSourceUpload>();
    executor.handler = (_) => completion.future;
    picker.selections.add([
      _candidate('first quote.pdf'),
      _candidate('second rates.xlsx'),
    ]);
    await showSection(tester);
    await openDialog(tester);
    await chooseFiles(tester);
    await tester.tap(uploadButton());
    await tester.pump();

    expect(find.text('Choose files'), findsNothing);
    expect(find.text('Add more files'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Cancel Upload'), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('close-supplier-source-upload')),
          )
          .onPressed,
      isNull,
    );

    executor.emit(
      const SupplierSourceUploadProgress(
        state: SupplierSourceUploadState.uploading,
        totalFiles: 2,
        currentFileIndex: 0,
        currentFileName: 'first quote.pdf',
        bytesTransferred: 64,
        totalBytes: 128,
      ),
    );
    await tester.pump();
    expect(find.text('Uploading 1 of 2…'), findsOneWidget);
    expect(find.text('first quote.pdf'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('supplier-source-byte-progress')),
          )
          .value,
      0.5,
    );

    executor.emit(
      const SupplierSourceUploadProgress(
        state: SupplierSourceUploadState.finalizing,
        totalFiles: 2,
      ),
    );
    await tester.pump();
    expect(find.text('Finalising…'), findsOneWidget);
    executor.emit(
      const SupplierSourceUploadProgress(
        state: SupplierSourceUploadState.rollingBack,
        totalFiles: 2,
      ),
    );
    await tester.pump();
    expect(find.text('Cleaning up…'), findsOneWidget);

    completion.complete(
      CompletedSupplierSourceUpload(
        tripId: 'trip-1',
        packageId: 'package-1',
        fileIds: const ['file-1', 'file-2'],
      ),
    );
    await tester.pump();
    expect(find.text('Supplier source uploaded'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  });

  testWidgets('successful upload closes, refreshes, and stays in workspace', (
    tester,
  ) async {
    picker.selections.add([_candidate('quote.pdf'), _candidate('rates.xlsx')]);
    executor.handler = (call) async {
      sources.packages.add(
        _package(
          status: SupplierSourcePackageStatus.uploaded,
          fileIds: const ['file-1', 'file-2'],
        ),
      );
      return CompletedSupplierSourceUpload(
        tripId: call.tripId,
        packageId: 'package-uploaded',
        fileIds: const ['file-1', 'file-2'],
      );
    };
    await showSection(tester);
    expect(sources.packageQueries, ['trip-1']);
    await openDialog(tester);
    await chooseFiles(tester);
    await tester.tap(uploadButton());
    await tester.pump();
    await tester.pump();
    expect(find.text('Supplier source uploaded'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('supplier-source-upload-dialog')),
      findsNothing,
    );
    expect(find.text('Uploaded'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);
    expect(sources.packageQueries, ['trip-1', 'trip-1']);
    expect(find.text('Supplier Sources'), findsOneWidget);
  });

  testWidgets('normal failure is sanitized and refreshes after Close', (
    tester,
  ) async {
    picker.selections.add([_candidate('quote.pdf')]);
    executor.handler = (_) async {
      sources.packages.add(
        _package(status: SupplierSourcePackageStatus.failed),
      );
      throw SupplierSourceUploadFailure(
        SupplierSourceUploadFailureKind.upload,
        packageId: 'package-failed',
      );
    };
    await showSection(tester);
    await openDialog(tester);
    await chooseFiles(tester);
    await tester.tap(uploadButton());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Upload couldn’t be completed. No incomplete source files were kept.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('package-failed'), findsNothing);
    expect(sources.packageQueries, ['trip-1']);
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();
    expect(sources.packageQueries, ['trip-1', 'trip-1']);
    expect(find.text('Failed'), findsOneWidget);
  });

  testWidgets('rollbackIncomplete renders the stronger warning', (
    tester,
  ) async {
    picker.selections.add([_candidate('quote.pdf')]);
    executor.handler = (_) async => throw SupplierSourceUploadFailure(
      SupplierSourceUploadFailureKind.rollbackIncomplete,
      originalKind: SupplierSourceUploadFailureKind.upload,
      packageId: 'package-failed',
      cleanupFailedFileIds: const ['file-private'],
    );
    await showSection(tester);
    await openDialog(tester);
    await chooseFiles(tester);
    await tester.tap(uploadButton());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Upload couldn’t be completed and some cleanup could not be confirmed. Please contact an administrator before uploading these files again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('file-private'), findsNothing);
  });

  for (final width in <double>[390, 1440]) {
    testWidgets('${width.toInt()}px upload surface has no overflow', (
      tester,
    ) async {
      viewport(tester, width);
      suppliers.suppliers.add(
        _supplier(
          id: 'supplier-long',
          name:
              'A deliberately long active supplier name that must remain contained',
          destinations: const [
            'A deliberately long destination coverage value',
          ],
        ),
      );
      picker.selections.add([
        for (var index = 1; index <= 8; index++)
          _candidate(
            'very-long-supplier-quotation-filename-number-$index-for-layout-testing.pdf',
          ),
      ]);
      await showSection(tester);
      await openDialog(tester);
      await chooseFiles(tester);

      expect(
        find.byKey(const ValueKey('supplier-source-upload-dialog')),
        findsOneWidget,
      );
      expect(find.text('Upload Supplier Source'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '${width.toInt()}px nested Supplier creation preserves upload dialog',
      (tester) async {
        viewport(tester, width);
        picker.selections.add([_candidate('responsive quote.pdf')]);
        await showSection(tester);
        await openDialog(tester);
        expect(find.text('+ Add new supplier').hitTestable(), findsOneWidget);
        await chooseFiles(tester);
        await openCreateSupplier(tester);
        await fillNewSupplier(
          tester,
          name:
              'A deliberately long newly created Supplier name for responsive validation',
        );
        expect(tester.takeException(), isNull);
        final create = find.descendant(
          of: find.byType(SupplierForm),
          matching: find.widgetWithText(FilledButton, 'Create Supplier'),
        );
        await tester.ensureVisible(create);
        await tester.tap(create);
        await tester.pumpAndSettle();

        expect(find.byType(SupplierForm), findsNothing);
        expect(find.text('responsive quote.pdf'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('supplier-option-created-1')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
