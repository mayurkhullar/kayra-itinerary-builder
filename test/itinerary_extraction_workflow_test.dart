import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_extraction_request_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_extraction_job.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/itinerary_extraction_controller.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_upload_dependencies.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';
import 'package:kayra_crm_v1/features/supplier_sources/presentation/widgets/supplier_source_extraction_status.dart';
import 'package:kayra_crm_v1/features/supplier_sources/presentation/widgets/supplier_sources_section.dart';

import 'support/fake_itinerary_extraction.dart';
import 'support/fake_supplier_repository.dart';
import 'support/fake_supplier_source_repository.dart';
import 'support/fake_supplier_source_upload.dart';

SupplierSourcePackage _package({
  String id = 'package-1',
  SupplierSourcePackageStatus status = SupplierSourcePackageStatus.uploaded,
  int day = 28,
}) => SupplierSourcePackage(
  id: id,
  tripId: 'trip-1',
  fileIds: status == SupplierSourcePackageStatus.uploaded
      ? ['file-1']
      : const [],
  uploadedByUid: 'agent-1',
  createdAt: DateTime.utc(2026, 9, day),
  updatedAt: DateTime.utc(2026, 9, day),
  status: status,
);

void main() {
  late FakeSupplierSourceRepository sources;
  late FakeItineraryExtractionJobRepository jobs;
  late FakeItineraryExtractionRequestClient requests;

  setUp(() {
    sources = FakeSupplierSourceRepository();
    jobs = FakeItineraryExtractionJobRepository();
    requests = FakeItineraryExtractionRequestClient();
    addTearDown(jobs.dispose);
  });

  void viewport(WidgetTester tester, double width, {double height = 900}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> showSection(WidgetTester tester, {double width = 390}) async {
    viewport(tester, width);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SupplierSourcesSection(
              tripId: 'trip-1',
              uploadedByUid: 'agent-1',
              repository: sources,
              supplierRepository: FakeSupplierRepository(),
              uploadDependencies: SupplierSourceUploadDependencies(
                picker: FakeSupplierSourceFilePicker(),
                executor: FakeSupplierSourceUploadExecutor(),
              ),
              extractionDependencies: jobs.dependencies(requests: requests),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('only uploaded package without a job shows Generate Draft', (
    tester,
  ) async {
    sources.packages.addAll([
      _package(id: 'uploaded'),
      _package(
        id: 'uploading',
        status: SupplierSourcePackageStatus.uploading,
        day: 27,
      ),
      _package(
        id: 'failed',
        status: SupplierSourcePackageStatus.failed,
        day: 26,
      ),
    ]);
    await showSection(tester);

    expect(find.text('Generate Draft'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('generate-draft-uploaded')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('generate-draft-uploading')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('generate-draft-failed')), findsNothing);
    expect(jobs.listCalls, ['trip-1']);
  });

  testWidgets('callable in flight disables duplicate request clicks', (
    tester,
  ) async {
    sources.packages.add(_package());
    final completion = Completer<ItineraryExtractionRequestResult>();
    requests.handler = (_, _) => completion.future;
    await showSection(tester);

    await tester.tap(find.byKey(const ValueKey('generate-draft-package-1')));
    await tester.pump();
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('generate-draft-package-1')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Starting draft…'), findsOneWidget);
    expect(requests.calls, hasLength(1));

    completion.complete(
      ItineraryExtractionRequestResult(
        jobId: 'job-1',
        status: KayraItineraryExtractionStatus.queued,
        createdNew: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(requests.calls, hasLength(1));
    expect(find.text('Preparing draft…'), findsOneWidget);
  });

  for (final entry in <KayraItineraryExtractionStatus, String>{
    KayraItineraryExtractionStatus.queued: 'Preparing draft…',
    KayraItineraryExtractionStatus.processing: 'Building itinerary draft…',
    KayraItineraryExtractionStatus.completed: 'Draft ready',
  }.entries) {
    testWidgets('${entry.key.value} renders ${entry.value}', (tester) async {
      sources.packages.add(_package());
      jobs.jobs.add(
        fakeExtractionJob(
          status: entry.key,
          resultingDraftId:
              entry.key == KayraItineraryExtractionStatus.completed
              ? 'draft-1'
              : null,
        ),
      );
      await showSection(tester);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });
  }

  testWidgets('completed state without a draft ID never claims success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SupplierSourceExtractionStatus(
            packageId: 'package-1',
            state: const ItineraryExtractionPackageState(
              kind: ItineraryExtractionPackageStateKind.completed,
            ),
            onRequest: () {},
          ),
        ),
      ),
    );
    expect(find.text('Draft ready'), findsNothing);
    expect(find.text('Couldn’t build draft'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('failed job shows mapped reason and human-controlled retry', (
    tester,
  ) async {
    sources.packages.add(_package());
    jobs.jobs.add(
      fakeExtractionJob(
        status: KayraItineraryExtractionStatus.failed,
        failureCode: KayraItineraryExtractionFailureCode.unsupportedSource,
      ),
    );
    await showSection(tester);
    expect(find.text('Couldn’t build draft'), findsOneWidget);
    expect(
      find.text(
        'One or more uploaded file formats cannot yet be processed for itinerary extraction.',
      ),
      findsOneWidget,
    );
    expect(requests.calls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('retry-draft-package-1')));
    await tester.pump();
    expect(requests.calls.single.sourcePackageId, 'package-1');
  });

  testWidgets('createdNew false attaches to existing job and follows it live', (
    tester,
  ) async {
    sources.packages.add(_package());
    requests.handler = (_, _) async => ItineraryExtractionRequestResult(
      jobId: 'existing-job',
      status: KayraItineraryExtractionStatus.processing,
      createdNew: false,
    );
    await showSection(tester);
    await tester.tap(find.byKey(const ValueKey('generate-draft-package-1')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Building itinerary draft…'), findsOneWidget);
    expect(jobs.observeCalls, [(tripId: 'trip-1', jobId: 'existing-job')]);
    jobs.emit(
      'existing-job',
      fakeExtractionJob(
        id: 'existing-job',
        status: KayraItineraryExtractionStatus.completed,
        resultingDraftId: 'draft-existing',
      ),
    );
    await tester.pump();
    expect(find.text('Draft ready'), findsOneWidget);
    expect(find.text('Generate Draft'), findsNothing);
  });

  testWidgets('leaving the section cancels an active job listener', (
    tester,
  ) async {
    sources.packages.add(_package());
    jobs.jobs.add(fakeExtractionJob(id: 'active-job'));
    await showSection(tester);
    expect(jobs.observeCalls, [(tripId: 'trip-1', jobId: 'active-job')]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(jobs.cancellations, 1);
  });

  testWidgets('late old-job errors cannot replace a newer retry state', (
    tester,
  ) async {
    sources.packages.add(_package());
    jobs.jobs.add(fakeExtractionJob(id: 'old-active'));
    requests.handler = (_, _) async => ItineraryExtractionRequestResult(
      jobId: 'new-job',
      status: KayraItineraryExtractionStatus.queued,
      createdNew: true,
    );
    await showSection(tester);
    jobs.emitError('old-active', StateError('first private error'));
    await tester.pump();
    expect(find.text('Couldn’t build draft'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('retry-draft-package-1')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Preparing draft…'), findsOneWidget);

    jobs.emitError('old-active', StateError('stale private error'));
    await tester.pump();
    expect(find.text('Preparing draft…'), findsOneWidget);
    expect(find.textContaining('stale private'), findsNothing);
  });

  const failureMessages = {
    KayraItineraryExtractionFailureCode.sourceUnavailable:
        'The Supplier Source could not be read. Please check the uploaded files and try again.',
    KayraItineraryExtractionFailureCode.unsupportedSource:
        'One or more uploaded file formats cannot yet be processed for itinerary extraction.',
    KayraItineraryExtractionFailureCode.extractionFailed:
        'The itinerary could not be extracted. Please try again.',
    KayraItineraryExtractionFailureCode.invalidExtractionResult:
        'The extracted itinerary needs another attempt before it can be used.',
    KayraItineraryExtractionFailureCode.draftPersistenceFailed:
        'The itinerary was extracted but could not be saved. Please try again.',
  };
  for (final entry in failureMessages.entries) {
    test('${entry.key.value} has the documented safe message', () {
      expect(itineraryExtractionFailureMessage(entry.key), entry.value);
    });
  }
  test('unknown failed-job reason has a safe generic message', () {
    expect(
      itineraryExtractionFailureMessage(null),
      'We couldn’t build the itinerary draft. Please try again.',
    );
  });

  for (final width in <double>[390, 1440]) {
    testWidgets('${width.toInt()}px extraction states do not overflow', (
      tester,
    ) async {
      sources.packages.add(_package());
      jobs.jobs.add(
        fakeExtractionJob(
          status: KayraItineraryExtractionStatus.failed,
          failureCode: KayraItineraryExtractionFailureCode.unsupportedSource,
        ),
      );
      await showSection(tester, width: width);
      expect(find.text('Couldn’t build draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
