import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_extraction_request_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_extraction_job.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/itinerary_extraction_controller.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';
import 'package:kayra_crm_v1/features/supplier_sources/presentation/widgets/supplier_source_extraction_status.dart';

import 'support/fake_itinerary_extraction.dart';

final _time = DateTime.utc(2026, 10, 9);
final _package = SupplierSourcePackage(
  id: 'package-1',
  tripId: 'trip-1',
  fileIds: ['file-1'],
  uploadedByUid: 'agent-1',
  createdAt: _time,
  updatedAt: _time,
  status: SupplierSourcePackageStatus.uploaded,
);

void main() {
  for (final status in [
    KayraItineraryExtractionStatus.queued,
    KayraItineraryExtractionStatus.processing,
  ]) {
    testWidgets(
      '${status.value} deadline only updates presentation, never requests or polls',
      (tester) async {
        var now = _time;
        final jobs = FakeItineraryExtractionJobRepository();
        final requests = FakeItineraryExtractionRequestClient();
        jobs.jobs.add(
          fakeExtractionJob(
            status: status,
            staleAfter: now.add(const Duration(seconds: 10)),
          ),
        );
        final controller = ItineraryExtractionController(
          tripId: 'trip-1',
          jobs: jobs,
          requests: requests,
          now: () => now,
        );
        await controller.load();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => SupplierSourceExtractionStatus(
                  packageId: 'package-1',
                  state: controller.stateFor(_package),
                  onRequest: () => controller.request('package-1'),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Try again'), findsNothing);
        expect(
          controller.stateFor(_package).kind,
          status == KayraItineraryExtractionStatus.queued
              ? ItineraryExtractionPackageStateKind.queued
              : ItineraryExtractionPackageStateKind.processing,
        );
        now = now.add(const Duration(seconds: 10));
        await tester.pump(const Duration(seconds: 10));
        expect(
          find.text('This extraction is taking longer than expected.'),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
        expect(requests.calls, isEmpty);
        expect(jobs.listCalls, hasLength(1));
        expect(jobs.observeCalls, hasLength(1));
        now = now.add(const Duration(hours: 1));
        await tester.pump(const Duration(hours: 1));
        expect(requests.calls, isEmpty);
        expect(jobs.listCalls, hasLength(1));
        controller.dispose();
        await jobs.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final replacement in [false, true]) {
    testWidgets(
      'explicit retry adopts ${replacement ? 'replacement' : 'same fresh job'} and blocks duplicate taps',
      (tester) async {
        var now = _time;
        final jobs = FakeItineraryExtractionJobRepository();
        final requests = FakeItineraryExtractionRequestClient();
        final old = fakeExtractionJob(
          id: 'old',
          staleAfter: now.subtract(const Duration(seconds: 1)),
        );
        jobs.jobs.add(old);
        final response = Completer<ItineraryExtractionRequestResult>();
        requests.handler = (_, _) => response.future;
        final controller = ItineraryExtractionController(
          tripId: 'trip-1',
          jobs: jobs,
          requests: requests,
          now: () => now,
        );
        await controller.load();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => SupplierSourceExtractionStatus(
                  packageId: 'package-1',
                  state: controller.stateFor(_package),
                  onRequest: () => controller.request('package-1'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Try again'));
        await controller.request('package-1');
        await tester.pump();
        expect(requests.calls, [
          (tripId: 'trip-1', sourcePackageId: 'package-1'),
        ]);
        expect(
          controller.stateFor(_package).kind,
          ItineraryExtractionPackageStateKind.requesting,
        );
        response.complete(
          ItineraryExtractionRequestResult(
            jobId: replacement ? 'new' : 'old',
            status: KayraItineraryExtractionStatus.queued,
            createdNew: replacement,
          ),
        );
        await tester.pump();
        jobs.emit(
          replacement ? 'new' : 'old',
          replacement
              ? fakeExtractionJob(
                  id: 'new',
                  staleAfter: now.add(const Duration(minutes: 15)),
                )
              : old,
        );
        await tester.pump();
        expect(
          controller.stateFor(_package).kind,
          ItineraryExtractionPackageStateKind.queued,
        );
        expect(find.text('Try again'), findsNothing);
        expect(jobs.observeCalls.last.jobId, replacement ? 'new' : 'old');
        // A fast clock may re-offer after the presentation cooldown, but never send.
        now = now.add(const Duration(minutes: 1));
        await tester.pump(const Duration(minutes: 1));
        expect(requests.calls, hasLength(1));
        expect(jobs.listCalls, hasLength(1));
        controller.dispose();
        await jobs.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final width in <double>[375, 390, 430, 768, 1024, 1280, 1440, 1920]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'recovery at ${width.toInt()}px and ${scale * 100}% text has no overflow',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SupplierSourceExtractionStatus(
                      packageId: 'package-1',
                      state: const ItineraryExtractionPackageState(
                        kind: ItineraryExtractionPackageStateKind.longRunning,
                      ),
                      onRequest: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text('Try again'), findsOneWidget);
          expect(tester.takeException(), isNull);
          final button = tester.getRect(find.byType(TextButton));
          expect(button.left, greaterThanOrEqualTo(0));
          expect(button.right, lessThanOrEqualTo(width));
        },
      );
    }
  }
}
