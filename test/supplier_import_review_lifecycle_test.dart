import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_extraction_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_error.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_state.dart';

import 'support/supplier_extraction_fixture.dart';
import 'support/supplier_import_review_fixture.dart';

void main() {
  late ReviewHarness h;
  setUp(() => h = ReviewHarness());
  tearDown(() => h.dispose());

  test(
    'initial state and fixed session identity require no Firebase initialization',
    () {
      expect(h.controller.state, isA<SupplierImportReviewInitial>());
      expect(h.controller.state.loaded, isNull);
      expect(h.controller.state.pendingMutation, isNull);
      expect(h.controller.tripId, 'trip-1');
      expect(h.controller.extractionId, 'extraction-1');
      expect(h.calls, isEmpty);
    },
  );

  for (final mode in ['not started', 'active', 'finalized']) {
    test('loads Snapshot then $mode Resolution without mutation', () async {
      h.resolutions.value = mode == 'not started'
          ? const SupplierImportResolutionNotStarted()
          : reviewResolution(revision: 2, finalized: mode == 'finalized');
      final states = <SupplierImportReviewState>[];
      h.controller.addListener(() => states.add(h.controller.state));
      expect(await h.controller.load(), isNull);
      expect(states.first, isA<SupplierImportReviewLoading>());
      expect(
        h.controller.state,
        mode == 'not started'
            ? isA<SupplierImportReviewNotStarted>()
            : mode == 'active'
            ? isA<SupplierImportReviewActive>()
            : isA<SupplierImportReviewFinalized>(),
      );
      expect(h.controller.state.loaded!.snapshot, same(h.snapshots.value));
      expect(h.calls, [
        'snapshot:trip-1/extraction-1',
        'resolution:trip-1/extraction-1',
      ]);
      expect(h.mutations.requests, isEmpty);
      expect(h.generatedIds, 0);
    });
  }

  for (final kind in SupplierExtractionRepositoryFailureKind.values) {
    test(
      'Snapshot $kind is sanitized and stops before Resolution read',
      () async {
        h.snapshots.error = SupplierExtractionRepositoryFailure(
          kind,
          'private source detail',
        );
        final error = await h.controller.load();
        expect(
          error!.kind,
          kind == SupplierExtractionRepositoryFailureKind.malformed
              ? SupplierImportReviewErrorKind.malformedData
              : SupplierImportReviewErrorKind.snapshotLoad,
        );
        expect(error.snapshotFailureKind, kind);
        expect(error.userMessage, isNot(contains('private')));
        expect(h.controller.state.loaded, isNull);
        expect(h.resolutions.readCount, 0);
        expect(h.mutations.requests, isEmpty);
        h.snapshots.error = null;
        expect(await h.controller.load(), isNull);
        expect(h.controller.state, isA<SupplierImportReviewNotStarted>());
      },
    );
  }

  for (final kind in SupplierImportResolutionRepositoryFailureKind.values) {
    test(
      'Resolution $kind retains recoverable display and safe error',
      () async {
        h.resolutions.value = reviewResolution();
        await h.controller.load();
        final previous = h.controller.state;
        h.resolutions.error = SupplierImportResolutionRepositoryFailure(
          kind,
          'private document data',
        );
        final error = await h.controller.refresh();
        expect(error!.kind, switch (kind) {
          SupplierImportResolutionRepositoryFailureKind.malformed =>
            SupplierImportReviewErrorKind.malformedData,
          SupplierImportResolutionRepositoryFailureKind.permissionDenied =>
            SupplierImportReviewErrorKind.permissionDenied,
          SupplierImportResolutionRepositoryFailureKind.readFailed =>
            SupplierImportReviewErrorKind.resolutionLoad,
        });
        expect(error.resolutionFailureKind, kind);
        expect(error.userMessage, isNot(contains('private')));
        expect(h.controller.state.loaded, same(previous));
        expect(h.snapshots.readCount, 1);
        expect(
          (await h.controller.setDecision(reviewTitleDecision))?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        expect(h.mutations.requests, isEmpty);
      },
    );
  }

  test(
    'initial Resolution read failure caches the valid Snapshot for recovery',
    () async {
      h.resolutions.error = StateError('private backend response');
      await h.controller.load();
      final error = (h.controller.state as SupplierImportReviewFailed).error;
      expect(error.kind, SupplierImportReviewErrorKind.resolutionLoad);
      expect(error.userMessage, isNot(contains('private')));
      h.resolutions.error = null;
      await h.controller.refresh();
      expect(h.snapshots.readCount, 1);
      expect(h.resolutions.readCount, 2);
    },
  );

  for (final mismatch in ['trip', 'extraction']) {
    test(
      'Snapshot $mismatch mismatch fails before combining repositories',
      () async {
        final tripId = mismatch == 'trip' ? 'other-trip' : 'trip-1';
        final extractionId = mismatch == 'extraction'
            ? 'other-extraction'
            : 'extraction-1';
        h.snapshots.value = SupplierExtractionSnapshot.fromStoredDocuments(
          expectedTripId: tripId,
          expectedExtractionId: extractionId,
          root: supplierExtractionRoot(
            tripId: tripId,
            extractionId: extractionId,
          ),
          dayDocuments: supplierExtractionDayDocuments(),
          factDocuments: supplierExtractionFactDocuments(),
          reviewIssueDocuments: supplierExtractionReviewIssueDocuments(),
          trustedSourceFileIds: const ['file-1'],
        );
        expect(
          (await h.controller.load())?.kind,
          SupplierImportReviewErrorKind.malformedData,
        );
        expect(h.controller.state.loaded, isNull);
        expect(h.resolutions.readCount, 0);
      },
    );
  }

  for (final mismatch in ['trip', 'extraction', 'package']) {
    test(
      'Resolution $mismatch mismatch is refused without displaying foreign data',
      () async {
        h.resolutions.value = reviewResolution(
          tripId: mismatch == 'trip' ? 'other-trip' : 'trip-1',
          extractionId: mismatch == 'extraction'
              ? 'other-extraction'
              : 'extraction-1',
          sourcePackageId: mismatch == 'package'
              ? 'other-package'
              : 'package-1',
        );
        expect(
          (await h.controller.load())?.kind,
          SupplierImportReviewErrorKind.malformedData,
        );
        expect(h.controller.state.loaded, isNull);
        expect(h.mutations.requests, isEmpty);
      },
    );
  }

  test(
    'refresh updates authoritative state while keeping the same immutable Snapshot',
    () async {
      await h.controller.load();
      final snapshot = h.controller.state.loaded!.snapshot;
      final days = snapshot.days;
      final facts = snapshot.facts;
      for (final result in [
        reviewResolution(revision: 4),
        reviewResolution(revision: 6, finalized: true),
      ]) {
        h.resolutions.value = result;
        await h.controller.refresh();
        expect(h.controller.state.loaded!.snapshot, same(snapshot));
        expect(snapshot.days, same(days));
        expect(snapshot.facts, same(facts));
      }
      expect(h.snapshots.readCount, 1);
      expect(h.resolutions.readCount, 3);
      expect(h.mutations.requests, isEmpty);
    },
  );

  test(
    'older Snapshot load cannot overwrite or continue after newer refresh',
    () async {
      final older = Completer<SupplierExtractionSnapshot>();
      h.snapshots.onRead = () => older.future;
      final load = h.controller.load();
      h.snapshots.onRead = null;
      h.resolutions.value = reviewResolution(revision: 3);
      await h.controller.refresh();
      final current = h.controller.state;
      older.complete(h.snapshots.value);
      await load;
      expect(h.controller.state, same(current));
      expect(h.resolutions.readCount, 1);
    },
  );

  test('older Resolution read cannot overwrite a newer refresh', () async {
    await h.controller.load();
    final older = Completer<SupplierImportResolutionReadResult>();
    h.resolutions.onRead = () => older.future;
    final refresh = h.controller.refresh();
    h.resolutions.onRead = null;
    h.resolutions.value = reviewResolution(revision: 6);
    await h.controller.refresh();
    final current = h.controller.state;
    older.complete(reviewResolution(revision: 2));
    await refresh;
    expect(h.controller.state, same(current));
  });

  test('older failed read cannot replace a newer successful load', () async {
    await h.controller.load();
    final older = Completer<SupplierImportResolutionReadResult>();
    h.resolutions.onRead = () => older.future;
    final refresh = h.controller.refresh();
    h.resolutions.onRead = null;
    await h.controller.refresh();
    final current = h.controller.state;
    older.completeError(StateError('stale private error'));
    await refresh;
    expect(h.controller.state, same(current));
  });

  for (final phase in [
    'Snapshot',
    'Resolution',
    'callable',
    'post-save refresh',
  ]) {
    test(
      'dispose prevents late $phase updates and follow-up operations',
      () async {
        Future<SupplierImportReviewError?> operation;
        void Function() complete;
        if (phase == 'Snapshot') {
          final pending = Completer<SupplierExtractionSnapshot>();
          h.snapshots.onRead = () => pending.future;
          operation = h.controller.load();
          complete = () => pending.complete(h.snapshots.value);
        } else {
          h.resolutions.value = reviewResolution();
          await h.controller.load();
          if (phase == 'callable') {
            final pending =
                Completer<SupplierImportResolutionMutationOutcome>();
            h.mutations.onExecute = (_) => pending.future;
            operation = h.controller.setDecision(reviewTitleDecision);
            complete = () => pending.complete(reviewOutcome('applied'));
          } else {
            final pending = Completer<SupplierImportResolutionReadResult>();
            final entered = Completer<void>();
            h.resolutions.onRead = () {
              entered.complete();
              return pending.future;
            };
            operation = phase == 'Resolution'
                ? h.controller.refresh()
                : h.controller.setDecision(reviewTitleDecision);
            await entered.future;
            complete = () => pending.complete(reviewResolution(revision: 2));
          }
        }
        final state = h.controller.state;
        final calls = List.of(h.calls);
        var notifications = 0;
        h.controller.addListener(() => notifications++);
        h.dispose();
        complete();
        await operation;
        expect(h.controller.state, same(state));
        expect(notifications, 0);
        expect(h.calls, calls);
        expect(
          (await h.controller.refresh())?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
      },
    );
  }

  test(
    'mutation remains exclusive until the authoritative read completes',
    () async {
      h.resolutions.value = reviewResolution();
      await h.controller.load();
      final entered = Completer<void>();
      final pending = Completer<SupplierImportResolutionReadResult>();
      h.resolutions.onRead = () {
        entered.complete();
        return pending.future;
      };
      final save = h.controller.setDecision(reviewTitleDecision);
      await entered.future;
      expect(h.controller.state, isA<SupplierImportReviewSaving>());
      expect(
        (await h.controller.removeDecision('title'))?.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      expect(
        (await h.controller.refresh())?.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      expect(h.generatedIds, 1);
      pending.complete(reviewResolution(revision: 2));
      await save;
    },
  );

  test(
    'normal active mutations reject rapid double clicks without a second command ID',
    () async {
      h.resolutions.value = reviewResolution();
      await h.controller.load();
      final pending = Completer<SupplierImportResolutionMutationOutcome>();
      h.mutations.onExecute = (_) => pending.future;
      final first = h.controller.setDecision(reviewTitleDecision);
      expect(
        (await h.controller.setDecision(reviewTitleDecision))?.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      expect(h.generatedIds, 1);
      expect(h.mutations.requests, hasLength(1));
      h.resolutions.value = reviewResolution(revision: 2);
      pending.complete(reviewOutcome('applied'));
      await first;
    },
  );

  test(
    'controller boundary has no direct Firebase writes or local readiness policy',
    () {
      final code = File(
        'lib/features/itineraries/presentation/controllers/supplier_import_review_controller.dart',
      ).readAsStringSync();
      expect(code, isNot(contains('package:cloud_firestore')));
      expect(code, isNot(contains('package:cloud_functions')));
      expect(code, isNot(contains('FirebaseFirestore')));
      expect(code, isNot(contains('FirebaseFunctions')));
      expect(code, isNot(contains('FirestoreItineraryDraftV2Repository(')));
      for (final method in [
        'finalize',
        'approve',
        'completeImport',
        'createDraft',
        'canFinalize',
      ]) {
        expect(code, isNot(matches(RegExp('\\b$method\\s*\\('))));
      }
      final production = File(
        'functions/src/itineraryExtraction/requestAdmin.ts',
      ).readAsStringSync();
      expect(
        production,
        contains(
          'currentProductionExtractionContractVersion =\n  itineraryDraftExtractionContractVersion;',
        ),
      );
    },
  );
}
