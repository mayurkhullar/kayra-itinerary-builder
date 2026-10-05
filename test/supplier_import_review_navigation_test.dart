import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_extraction_job.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/itinerary_extraction_controller.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/pages/supplier_import_review_page.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_upload_dependencies.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';
import 'package:kayra_crm_v1/features/supplier_sources/presentation/widgets/supplier_source_extraction_status.dart';
import 'package:kayra_crm_v1/features/trips/domain/kayra_trip.dart';
import 'package:kayra_crm_v1/features/trips/presentation/pages/trip_workspace_page.dart';
import 'package:kayra_crm_v1/shared/widgets/kayra_app_header.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_client_repository.dart';
import 'support/fake_itinerary_extraction.dart';
import 'support/fake_supplier_repository.dart';
import 'support/fake_supplier_source_repository.dart';
import 'support/fake_supplier_source_upload.dart';
import 'support/fake_trip_repository.dart';
import 'support/fake_user_profile_repository.dart';
import 'support/supplier_import_review_fixture.dart';

void main() {
  late ReviewHarness review;
  late FakeItineraryExtractionJobRepository jobs;
  late FakeItineraryExtractionRequestClient requests;

  setUp(() {
    review = ReviewHarness();
    jobs = FakeItineraryExtractionJobRepository();
    requests = FakeItineraryExtractionRequestClient();
  });
  tearDown(() async {
    review.dispose();
    await jobs.dispose();
  });

  Future<void> showWorkspace(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final trips = FakeTripRepository(clients: FakeClientRepository())
      ..trips.add(
        KayraTrip.fromMap({
          'clientId': 'client-1',
          'clientFirstName': 'Test',
          'clientLastName': 'Client',
          'tripName': 'Test Client – Tokyo & Kyoto – Apr 2027',
          'destinations': ['Tokyo', 'Kyoto'],
          'travelStartDate': DateTime.utc(2027, 4, 10),
          'numberOfNights': 5,
          'adults': 2,
          'children': 0,
          'infants': 0,
          'hotelCategory': '4_star',
          'tripType': 'fit',
          'status': 'draft',
          'ownerUid': 'test-user',
          'createdByUid': 'test-user',
          'createdAt': DateTime.utc(2026, 9, 1),
          'updatedAt': DateTime.utc(2026, 9, 25),
        }, documentId: 'trip-1'),
      );
    final sources = FakeSupplierSourceRepository()
      ..packages.add(
        SupplierSourcePackage(
          id: 'package-1',
          tripId: 'trip-1',
          supplierId: 'supplier-1',
          supplierNameSnapshot: 'Example Supplier',
          fileIds: const ['file-1'],
          uploadedByUid: 'test-user',
          createdAt: DateTime.utc(2026, 9, 25),
          updatedAt: DateTime.utc(2026, 9, 25),
          status: SupplierSourcePackageStatus.uploaded,
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DashboardPage(
          user: testProfile(TestUser()),
          onSignOut: () {},
          userProfileRepository: FakeUserProfileRepository(),
          clientRepository: FakeClientRepository(),
          tripRepository: trips,
          supplierRepository: FakeSupplierRepository(),
          supplierSourceRepository: sources,
          supplierSourceUploadDependencies: SupplierSourceUploadDependencies(
            picker: FakeSupplierSourceFilePicker(),
            executor: FakeSupplierSourceUploadExecutor(),
          ),
          itineraryExtractionDependencies: jobs.dependencies(
            requests: requests,
          ),
          supplierImportReviewDependencies: SupplierImportReviewDependencies(
            snapshots: review.snapshots,
            resolutions: review.resolutions,
            mutations: review.mutations,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trip = find.byKey(const ValueKey('trip-trip-1'));
    await tester.ensureVisible(trip);
    await tester.tap(trip);
    await tester.pumpAndSettle();
  }

  for (final width in <double>[390, 1440]) {
    testWidgets(
      '${width.toInt()}px completed V3 opens exact review session and Back returns to same Trip',
      (tester) async {
        jobs.jobs.add(
          fakeExtractionJob(
            status: KayraItineraryExtractionStatus.completed,
            extractionContractVersion:
                KayraItineraryExtractionContractVersion.supplierExtractionV1,
            resultType: KayraItineraryExtractionResultType.supplierExtraction,
            persistenceShape:
                KayraItineraryExtractionPersistenceShape.versioned,
            resultingExtractionId: 'extraction-1',
          ),
        );
        await showWorkspace(tester, width);
        expect(find.text('Extraction ready for review'), findsOneWidget);
        final entry = find.byKey(const ValueKey('review-extraction-package-1'));
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        final page = tester.widget<SupplierImportReviewPage>(
          find.byType(SupplierImportReviewPage),
        );
        expect(page.tripId, 'trip-1');
        expect(page.extractionId, 'extraction-1');
        expect(review.calls, [
          'snapshot:trip-1/extraction-1',
          'resolution:trip-1/extraction-1',
        ]);
        expect(find.byType(KayraAppHeader), findsOneWidget);
        expect(find.text('Japan Discovery'), findsOneWidget);
        expect(review.mutations.requests, isEmpty);
        expect(requests.calls, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('back-to-trip-workspace')));
        await tester.pumpAndSettle();
        expect(find.byType(SupplierImportReviewPage), findsNothing);
        expect(
          tester
              .widget<TripWorkspacePage>(find.byType(TripWorkspacePage))
              .tripId,
          'trip-1',
        );
        expect(find.text('Review extraction'), findsOneWidget);
        expect(review.snapshots.readCount, 1);
      },
    );

    testWidgets(
      '${width.toInt()}px V2 Draft ready stays unchanged and cannot open review',
      (tester) async {
        jobs.jobs.add(
          fakeExtractionJob(
            status: KayraItineraryExtractionStatus.completed,
            resultingDraftId: 'draft-1',
          ),
        );
        await showWorkspace(tester, width);
        expect(find.text('Draft ready'), findsOneWidget);
        expect(find.text('Review extraction'), findsNothing);
        expect(find.byType(SupplierImportReviewPage), findsNothing);
        expect(review.calls, isEmpty);
        expect(requests.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final state in [
    const ItineraryExtractionPackageState(
      kind: ItineraryExtractionPackageStateKind.queued,
      resultType: KayraItineraryExtractionResultType.supplierExtraction,
    ),
    const ItineraryExtractionPackageState(
      kind: ItineraryExtractionPackageStateKind.processing,
      resultType: KayraItineraryExtractionResultType.supplierExtraction,
    ),
    const ItineraryExtractionPackageState(
      kind: ItineraryExtractionPackageStateKind.failed,
      resultType: KayraItineraryExtractionResultType.supplierExtraction,
    ),
    const ItineraryExtractionPackageState(
      kind: ItineraryExtractionPackageStateKind.completed,
      resultType: KayraItineraryExtractionResultType.supplierExtraction,
    ),
    const ItineraryExtractionPackageState(
      kind: ItineraryExtractionPackageStateKind.completed,
      resultType: KayraItineraryExtractionResultType.supplierExtraction,
      resultingExtractionId: ' ',
    ),
    const ItineraryExtractionPackageState(
      kind: ItineraryExtractionPackageStateKind.completed,
      resultType: KayraItineraryExtractionResultType.supplierExtraction,
      resultingExtractionId: 'extraction-1',
      resultingDraftId: 'draft-1',
    ),
  ].indexed) {
    testWidgets(
      'non-completed or invalid V3 state ${state.$1} has no review action',
      (tester) async {
        final opened = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SupplierSourceExtractionStatus(
                packageId: 'package-1',
                state: state.$2,
                onRequest: () {},
                onReviewExtraction: opened.add,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Review extraction'), findsNothing);
        expect(opened, isEmpty);
      },
    );
  }
}
