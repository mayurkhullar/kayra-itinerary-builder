import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_extraction_request_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_extraction_job.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/pages/supplier_import_review_page.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/reextraction_confirmation.dart';
import 'package:kayra_crm_v1/features/supplier_sources/presentation/widgets/supplier_source_extraction_status.dart';
import 'support/fake_itinerary_extraction.dart';
import 'support/supplier_extraction_fixture.dart';
import 'support/supplier_import_review_fixture.dart';
import 'support/supplier_import_resolution_fixture.dart';

void main() {
  late ReviewHarness h;
  late FakeItineraryExtractionJobRepository jobs;
  late FakeItineraryExtractionRequestClient requests;
  setUp(() {
    h = ReviewHarness();
    jobs = FakeItineraryExtractionJobRepository();
    requests = FakeItineraryExtractionRequestClient();
    jobs.jobs.add(
      fakeExtractionJob(
        id: 'job-1',
        status: KayraItineraryExtractionStatus.completed,
        resultType: KayraItineraryExtractionResultType.supplierExtraction,
        extractionContractVersion:
            KayraItineraryExtractionContractVersion.supplierExtractionV1,
        persistenceShape: KayraItineraryExtractionPersistenceShape.versioned,
        resultingExtractionId: 'extraction-1',
      ),
    );
    requests.handler = (_, _) async => ItineraryExtractionRequestResult(
      jobId: 'new-job',
      status: KayraItineraryExtractionStatus.queued,
      createdNew: true,
    );
  });
  tearDown(() async {
    h.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    double width = 1440,
    double scale = 1,
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await jobs.dispose();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SupplierImportReviewPage(
            tripId: 'trip-1',
            extractionId: 'extraction-1',
            dependencies: SupplierImportReviewDependencies(
              snapshots: h.snapshots,
              resolutions: h.resolutions,
              mutations: h.mutations,
            ),
            extractionDependencies: jobs.dependencies(requests: requests),
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Extract again'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await open(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Extract again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'secondary action, opening, Cancel, Escape and time make no requests',
    (tester) async {
      await show(tester);
      expect(find.widgetWithText(TextButton, 'Extract again'), findsOneWidget);
      expect(requests.calls, isEmpty);
      final reads = h.resolutions.readCount;
      await open(tester);
      expect(find.byType(ReextractionConfirmation), findsOneWidget);
      expect(
        find.textContaining('same uploaded supplier files'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Changes made during this review'),
        findsNothing,
      );
      expect(h.resolutions.readCount, reads);
      expect(requests.calls, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ReextractionConfirmation), findsNothing);
      await tester.pump(const Duration(hours: 1));
      expect(requests.calls, isEmpty);
      expect(h.mutations.requests, isEmpty);
    },
  );

  for (final manual in [false, true]) {
    testWidgets(
      'warns about existing ${manual ? 'manual items' : 'decisions'} without copying',
      (tester) async {
        final resolution = SupplierImportResolutionLoaded(
          SupplierImportResolutionAggregate.fromStoredDocuments(
            expectedTripId: 'trip-1',
            expectedExtractionId: 'extraction-1',
            rootDocumentId: 'extraction-1',
            rootData: supplierImportResolutionRoot(),
            decisionDocuments: manual
                ? []
                : [(documentId: 'title', data: supplierImportTitleDecision())],
            manualItemDocuments: manual
                ? [
                    (
                      documentId: 'consultant-day-1',
                      data: supplierImportManualDay(),
                    ),
                  ]
                : [],
            eventDocuments: [
              (documentId: 'command-1', data: supplierImportAuditEvent()),
            ],
          ),
        );
        h.resolutions.value = resolution;
        await show(tester);
        await open(tester);
        expect(
          find.textContaining('Changes made during this review'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Extract again'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(requests.calls, hasLength(1));
        expect(h.resolutions.value, same(resolution));
        expect(h.mutations.requests, isEmpty);
      },
    );
  }

  for (final createdNew in [true, false]) {
    testWidgets(
      'adopts authoritative job (createdNew=$createdNew), hides review, preserves failure UI',
      (tester) async {
        final pending = Completer<ItineraryExtractionRequestResult>();
        requests.handler = (_, _) => pending.future;
        await show(tester);
        await open(tester);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Extract again'),
        );
        button.onPressed!();
        // A second stale tap cannot pop another route or send a request.
        button.onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(requests.calls, hasLength(1));
        pending.complete(
          ItineraryExtractionRequestResult(
            jobId: 'new-job',
            status: KayraItineraryExtractionStatus.queued,
            createdNew: createdNew,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(jobs.observeCalls.single.jobId, 'new-job');
        expect(find.text('Review supplier extraction'), findsNothing);
        expect(find.byType(SupplierSourceExtractionStatus), findsOneWidget);
        jobs.emit(
          'new-job',
          fakeExtractionJob(
            id: 'new-job',
            status: KayraItineraryExtractionStatus.processing,
          ),
        );
        await tester.pump();
        jobs.emit(
          'new-job',
          fakeExtractionJob(
            id: 'new-job',
            status: KayraItineraryExtractionStatus.failed,
            failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Try Again'), findsOneWidget);
        expect(find.text('Review supplier extraction'), findsNothing);
        expect(requests.calls, hasLength(1));
        expect(h.mutations.requests, isEmpty);
      },
    );
  }

  testWidgets(
    'new V3 completion loads new Snapshot and independent Resolution',
    (tester) async {
      final original = h.snapshots.value;
      h.resolutions.value = reviewResolution();
      await show(tester);
      await confirm(tester);
      final replacement = SupplierExtractionSnapshot.fromStoredDocuments(
        expectedTripId: 'trip-1',
        expectedExtractionId: 'new-extraction',
        root: {
          ...supplierExtractionRoot(extractionId: 'new-extraction'),
          'jobId': 'new-job',
        },
        dayDocuments: supplierExtractionDayDocuments(),
        factDocuments: supplierExtractionFactDocuments(),
        reviewIssueDocuments: supplierExtractionReviewIssueDocuments(),
        trustedSourceFileIds: const ['file-1'],
      );
      h.snapshots.value = replacement;
      h.resolutions.value = const SupplierImportResolutionNotStarted();
      jobs.emit(
        'new-job',
        fakeExtractionJob(
          id: 'new-job',
          status: KayraItineraryExtractionStatus.completed,
          resultType: KayraItineraryExtractionResultType.supplierExtraction,
          extractionContractVersion:
              KayraItineraryExtractionContractVersion.supplierExtractionV1,
          persistenceShape: KayraItineraryExtractionPersistenceShape.versioned,
          resultingExtractionId: 'new-extraction',
        ),
      );
      await tester.pumpAndSettle();
      expect(h.calls, contains('snapshot:trip-1/new-extraction'));
      expect(h.calls, contains('resolution:trip-1/new-extraction'));
      expect(find.text('Review supplier extraction'), findsOneWidget);
      expect(h.mutations.requests, isEmpty);
      expect(original.extractionId, 'extraction-1');
      expect(requests.calls, hasLength(1));
    },
  );

  testWidgets(
    'production V2 replacement uses normal completed UI, not a V3 review',
    (tester) async {
      await show(tester);
      await confirm(tester);
      jobs.emit(
        'new-job',
        fakeExtractionJob(
          id: 'new-job',
          status: KayraItineraryExtractionStatus.completed,
          resultingDraftId: 'draft-new',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SupplierSourceExtractionStatus), findsOneWidget);
      expect(find.text('Extract again'), findsNothing);
      expect(h.snapshots.readCount, 1);
      expect(requests.calls, hasLength(1));
    },
  );

  for (final initiallyFinalized in [true, false]) {
    testWidgets(
      'finalization blocks rerun (already finalized=$initiallyFinalized)',
      (tester) async {
        if (initiallyFinalized) {
          h.resolutions.value = reviewResolution(finalized: true, revision: 2);
        }
        await show(tester);
        if (!initiallyFinalized) {
          await open(tester);
          h.resolutions.value = reviewResolution(finalized: true, revision: 2);
          await tester.tap(find.widgetWithText(FilledButton, 'Extract again'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Extract again'), findsNothing);
        expect(requests.calls, isEmpty);
      },
    );
  }
  testWidgets('non-V3 job fails closed without adding a V2 action', (
    tester,
  ) async {
    jobs.jobs.clear();
    jobs.jobs.add(
      fakeExtractionJob(
        status: KayraItineraryExtractionStatus.completed,
        resultingDraftId: 'draft-1',
      ),
    );
    await show(tester);
    expect(find.text('Extract again'), findsNothing);
    expect(requests.calls, isEmpty);
  });

  testWidgets('duplicate action taps open one dialog', (tester) async {
    await show(tester);
    final action = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Extract again'),
    );
    action.onPressed!();
    action.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(ReextractionConfirmation), findsOneWidget);
    expect(requests.calls, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('failed authoritative Resolution refresh sends no request', (
    tester,
  ) async {
    await show(tester);
    await open(tester);
    h.resolutions.error = StateError('offline');
    await tester.tap(find.widgetWithText(FilledButton, 'Extract again'));
    await tester.pumpAndSettle();
    expect(requests.calls, isEmpty);
    expect(find.text('Extract again'), findsNothing);
  });

  testWidgets('leaving during confirmation refresh cannot request', (
    tester,
  ) async {
    await show(tester);
    await open(tester);
    final pending = Completer<SupplierImportResolutionReadResult>();
    h.resolutions.onRead = () => pending.future;
    await tester.tap(find.widgetWithText(FilledButton, 'Extract again'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(const SupplierImportResolutionNotStarted());
    await tester.pump();
    expect(requests.calls, isEmpty);
  });

  for (final width in [
    375.0,
    390.0,
    430.0,
    768.0,
    1024.0,
    1280.0,
    1440.0,
    1920.0,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('confirmation fits $width at scale $scale', (tester) async {
        await show(tester, width: width, scale: scale);
        await open(tester);
        expect(tester.takeException(), isNull);
        expect(
          find.widgetWithText(FilledButton, 'Extract again'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(requests.calls, isEmpty);
      });
    }
  }
}
