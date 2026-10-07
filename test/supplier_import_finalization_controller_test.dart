import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_draft_v2_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_finalization_client.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_mutation_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/itinerary_draft_v2.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_finalization.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_error.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_finalization_state.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_state.dart';
import 'support/supplier_import_finalization_fixture.dart';
import 'support/supplier_import_review_fixture.dart';

void main() {
  late FinalizationHarness h;
  setUp(() => h = FinalizationHarness());
  tearDown(() => h.dispose());
  for (final name in ['applied', 'already_applied']) {
    test(
      '$name uses one exact current-revision command then Resolution and V2 reads',
      () async {
        await h.controller.load();
        final snapshot = h.controller.state.loaded!.snapshot;
        h.finalizations.onExecute = (request) {
          expect(h.controller.state, isA<SupplierImportReviewFinalizing>());
          h.seal();
          return finalizationOutcome(name);
        };
        expect(await h.controller.finalizeReview(), isNull);
        expect(
          h.finalizations.requests.single.toMap(),
          finalizationRequest().toMap(),
        );
        expect(h.generatedIds, 1);
        expect(h.mutations.requests, isEmpty);
        final state = h.controller.state as SupplierImportReviewFinalized;
        expect(state.draft, same(h.drafts.value));
        expect(state.snapshot, same(snapshot));
        expect(state.finalization!.request, isNull);
        expect(h.calls, [
          'snapshot:trip-1/extraction-1',
          'resolution:trip-1/extraction-1',
          'finalize',
          'resolution:trip-1/extraction-1',
          'draft:trip-1/draft-1',
        ]);
        expect(
          (await h.controller.finalizeReview())!.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        expect(
          (await h.controller.setDecision(reviewTitleDecision))!.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
      },
    );
  }
  test('no local readiness algorithm or per-item acceptance gates', () async {
    await h.controller.load();
    expect(
      (h.controller.state as SupplierImportReviewActive).resolution.decisions,
      isEmpty,
    );
    h.finalizations.onExecute = (_) {
      h.seal();
      return finalizationOutcome('applied');
    };
    await h.controller.finalizeReview();
    expect(h.finalizations.requests, hasLength(1));
    expect(h.mutations.requests, isEmpty);
  });
  for (final mode in ['active', 'absent', 'wrong draft', 'wrong revision']) {
    test('success requires authoritative sealed linkage: $mode', () async {
      await h.controller.load();
      h.finalizations.outcome = finalizationOutcome(
        'applied',
        draftId: mode == 'wrong draft' ? 'other' : 'draft-1',
      );
      if (mode == 'absent') {
        h.resolutions.value = const SupplierImportResolutionNotStarted();
      }
      if (mode == 'wrong draft') h.seal();
      if (mode == 'wrong revision') {
        h.resolutions.value = reviewResolution(revision: 4, finalized: true);
      }
      expect(
        (await h.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.malformedData,
      );
      expect(h.controller.state, isA<SupplierImportReviewFailed>());
      expect(h.calls.where((c) => c.startsWith('draft:')), isEmpty);
      expect(
        (await h.controller.retryPendingFinalization())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
    });
  }
  for (final field in [
    'trip',
    'draft',
    'extraction',
    'package',
    'revision',
    'command',
  ]) {
    test(
      'V2 $field linkage mismatch fails safely and remains locked',
      () async {
        await h.controller.load();
        h.seal();
        h.drafts.value = finalizationDraft(
          tripId: field == 'trip' ? 'other' : 'trip-1',
          draftId: field == 'draft' ? 'other' : 'draft-1',
          extractionId: field == 'extraction' ? 'other' : 'extraction-1',
          packageId: field == 'package' ? 'other' : 'package-1',
          evaluatedRevision: field == 'revision' ? 1 : 2,
          commandId: field == 'command' ? 'other' : 'intent-1',
        );
        expect(
          (await h.controller.finalizeReview())!.draftFailureKind,
          ItineraryDraftV2RepositoryFailureKind.identityMismatch,
        );
        expect(h.controller.state.loaded, isA<SupplierImportReviewFinalized>());
        expect(
          (h.controller.state.loaded as SupplierImportReviewFinalized).draft,
          isNull,
        );
        expect(
          (await h.controller.setDecision(reviewTitleDecision))!.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
      },
    );
  }
  for (final kind in ItineraryDraftV2RepositoryFailureKind.values) {
    test(
      'V2 $kind is sanitized; refresh retries only authoritative reads',
      () async {
        await h.controller.load();
        h.seal();
        h.drafts.error = ItineraryDraftV2RepositoryFailure(kind);
        final error = await h.controller.finalizeReview();
        expect(error!.draftFailureKind, kind);
        expect(h.controller.state.loaded, isA<SupplierImportReviewFinalized>());
        expect(
          (h.controller.state as SupplierImportReviewFailed).recovery,
          SupplierImportReviewRecovery.refresh,
        );
        expect(
          (await h.controller.retryPendingFinalization())!.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        h.drafts.error = null;
        expect(await h.controller.refresh(), isNull);
        expect(
          (h.controller.state as SupplierImportReviewFinalized).draft,
          same(h.drafts.value),
        );
        expect(h.finalizations.requests, hasLength(1));
        expect(h.generatedIds, 1);
      },
    );
  }
  test(
    'not_ready retains immutable server findings and Snapshot without mutations/retry',
    () async {
      await h.controller.load();
      final snapshot = h.controller.state.loaded!.snapshot;
      h.finalizations.outcome = finalizationOutcome('not_ready');
      expect(await h.controller.finalizeReview(), isNull);
      final state = h.controller.state as SupplierImportReviewActive;
      final result =
          state.finalization!.outcome as SupplierImportFinalizationNotReady;
      expect(result.blockers, hasLength(1));
      expect(result.warnings, hasLength(1));
      expect(result.evaluatedRevision, 2);
      expect(state.snapshot, same(snapshot));
      expect(state.finalization!.request, isNull);
      expect(h.resolutions.readCount, 2);
      expect(h.mutations.requests, isEmpty);
      expect(h.finalizations.requests, hasLength(1));
      expect(
        (await h.controller.retryPendingFinalization())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
    },
  );
  test(
    'conflict reloads clears command and requires new explicit intent at fresh revision',
    () async {
      await h.controller.load();
      h.resolutions.value = reviewResolution(revision: 5);
      h.finalizations.outcome = finalizationOutcome(
        'resolution_conflict',
        revision: 5,
      );
      await h.controller.finalizeReview();
      final conflict = h.controller.state as SupplierImportReviewConflict;
      expect(conflict.currentRevision, 5);
      expect(conflict.finalization!.request, isNull);
      expect(
        (await h.controller.retryPendingFinalization())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      expect(h.finalizations.requests, hasLength(1));
      h.finalizations.outcome = finalizationOutcome('not_ready', revision: 6);
      await h.controller.finalizeReview();
      expect(h.finalizations.requests.last.expectedRevision, 5);
      expect(h.finalizations.requests.last.commandId, 'intent-2');
    },
  );
  test('not started reloads without starting review', () async {
    await h.controller.load();
    h.resolutions.value = const SupplierImportResolutionNotStarted();
    h.finalizations.outcome = finalizationOutcome('resolution_not_started');
    await h.controller.finalizeReview();
    expect(h.controller.state, isA<SupplierImportReviewNotStarted>());
    expect(
      h.controller.state.finalization!.outcome,
      isA<SupplierImportFinalizationNotStarted>(),
    );
    expect(h.mutations.requests, isEmpty);
  });
  test(
    'another finalizer result loads its authoritative V2 without overwrite',
    () async {
      await h.controller.load();
      h.seal();
      h.drafts.value = finalizationDraft(commandId: 'another-command');
      h.finalizations.outcome = finalizationOutcome('resolution_finalized');
      expect(await h.controller.finalizeReview(), isNull);
      expect(
        (h.controller.state as SupplierImportReviewFinalized).draft,
        same(h.drafts.value),
      );
      expect(h.controller.state.finalization!.request, isNull);
      expect(h.finalizations.requests, hasLength(1));
    },
  );
  test('ordinary reload discovers finalized V2', () async {
    h.seal();
    h.drafts.value = finalizationDraft(commandId: 'another-command');
    expect(await h.controller.load(), isNull);
    expect(
      (h.controller.state as SupplierImportReviewFinalized).draft,
      same(h.drafts.value),
    );
    expect(h.finalizations.requests, isEmpty);
  });
  test(
    'legacy reader composition remains finalized without inventing V2',
    () async {
      final legacy = ReviewHarness();
      addTearDown(legacy.dispose);
      legacy.resolutions.value = reviewResolution(revision: 3, finalized: true);
      expect(await legacy.controller.load(), isNull);
      expect(
        (legacy.controller.state as SupplierImportReviewFinalized).draft,
        isNull,
      );
      expect(
        (await legacy.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
    },
  );
  test('capacity is typed non-retryable without a loop', () async {
    await h.controller.load();
    h.finalizations.outcome = finalizationOutcome(
      'persistence_capacity_exceeded',
    );
    await h.controller.finalizeReview();
    expect(
      h.controller.state.finalization!.outcome,
      isA<SupplierImportFinalizationCapacityExceeded>(),
    );
    expect(h.controller.state.finalization!.request, isNull);
    expect(
      (await h.controller.retryPendingFinalization())!.kind,
      SupplierImportReviewErrorKind.invalidLocalAction,
    );
    expect(h.finalizations.requests, hasLength(1));
    expect(h.mutations.requests, isEmpty);
  });
  for (final error in <Object>[
    const SupplierImportFinalizationFailure(
      SupplierImportFinalizationFailureKind.unavailable,
    ),
    const SupplierImportFinalizationFailure(
      SupplierImportFinalizationFailureKind.internal,
    ),
    TimeoutException('PRIVATE'),
    StateError('PRIVATE'),
  ]) {
    test(
      'ambiguous ${error.runtimeType} preserves exact command and byte-equivalent explicit retry',
      () async {
        await h.controller.load();
        h.finalizations.error = error;
        await h.controller.finalizeReview();
        final original = h.finalizations.requests.single;
        final body = jsonEncode(original.toMap());
        expect(h.controller.state.finalization!.request, same(original));
        expect(
          (h.controller.state as SupplierImportReviewFailed).recovery,
          SupplierImportReviewRecovery.retryPendingFinalization,
        );
        expect(
          (await h.controller.finalizeReview())!.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        expect(
          (await h.controller.setDecision(reviewTitleDecision))!.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        h.resolutions.value = reviewResolution(revision: 7);
        await h.controller.refresh();
        expect(h.controller.state.finalization!.request, same(original));
        expect(original.expectedRevision, 2);
        h.finalizations.error = null;
        h.finalizations.outcome = finalizationOutcome('already_applied');
        h.seal();
        expect(await h.controller.retryPendingFinalization(), isNull);
        expect(h.finalizations.requests.last, same(original));
        expect(jsonEncode(h.finalizations.requests.last.toMap()), body);
        expect(h.generatedIds, 1);
        expect(h.finalizations.requests, hasLength(2));
      },
    );
  }
  for (final kind in [
    SupplierImportFinalizationFailureKind.sessionExpired,
    SupplierImportFinalizationFailureKind.permissionDenied,
    SupplierImportFinalizationFailureKind.invalidRequest,
    SupplierImportFinalizationFailureKind.invalidState,
  ]) {
    test('definitive $kind clears retry intent', () async {
      await h.controller.load();
      h.finalizations.error = SupplierImportFinalizationFailure(kind);
      expect(
        (await h.controller.finalizeReview())!.finalizationFailureKind,
        kind,
      );
      expect(h.controller.state.finalization!.request, isNull);
      expect(
        (await h.controller.retryPendingFinalization())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
    });
  }
  test(
    'unconfirmed malformed acknowledgement preserves exact intent',
    () async {
      await h.controller.load();
      h.finalizations.outcome = SupplierImportFinalizationOutcome.fromMap({
        ...finalizationResponse('applied'),
        'resolutionId': 'foreign',
      });
      expect(
        (await h.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.malformedData,
      );
      expect(
        h.controller.state.finalization!.request,
        same(h.finalizations.requests.single),
      );
      expect(h.resolutions.readCount, 1);
    },
  );
  test(
    'success Resolution read failure recovers by read without replay',
    () async {
      await h.controller.load();
      h.resolutions.error = StateError('PRIVATE');
      await h.controller.finalizeReview();
      expect(
        h.controller.state.finalization!.phase,
        SupplierImportReviewFinalizationPhase.awaitingReload,
      );
      expect(
        (await h.controller.retryPendingFinalization())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      h.resolutions.error = null;
      h.seal();
      expect(await h.controller.refresh(), isNull);
      expect(h.finalizations.requests, hasLength(1));
    },
  );
  test(
    'finalization exclusive through transport and follow-up V2 read',
    () async {
      await h.controller.load();
      final transport = Completer<SupplierImportFinalizationOutcome>();
      h.finalizations.onExecute = (_) => transport.future;
      final read = Completer<ItineraryDraftV2>();
      final entered = Completer<void>();
      h.drafts.onRead = () {
        entered.complete();
        return read.future;
      };
      final task = h.controller.finalizeReview();
      Future<void> blocked() async {
        for (final action in [
          h.controller.finalizeReview,
          h.controller.retryPendingFinalization,
          h.controller.refresh,
          () => h.controller.setDecision(reviewTitleDecision),
        ]) {
          expect(
            (await action())!.kind,
            SupplierImportReviewErrorKind.invalidLocalAction,
          );
        }
        expect(h.generatedIds, 1);
      }

      await blocked();
      h.seal();
      transport.complete(finalizationOutcome('applied'));
      await entered.future;
      await blocked();
      read.complete(h.drafts.value);
      await task;
    },
  );
  test(
    'mutation in flight and ambiguous mutation block finalization',
    () async {
      await h.controller.load();
      final pending = Completer<SupplierImportResolutionMutationOutcome>();
      h.mutations.onExecute = (_) => pending.future;
      final task = h.controller.setDecision(reviewTitleDecision);
      expect(
        (await h.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      pending.completeError(
        const SupplierImportMutationFailure(
          SupplierImportMutationFailureKind.unavailable,
        ),
      );
      await task;
      expect(
        (await h.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      expect(h.finalizations.requests, isEmpty);
      expect(h.generatedIds, 1);
    },
  );
  test(
    'initial/loading/not-started/disposed lifecycle blocks without generating commands',
    () async {
      expect(
        (await h.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      final read = Completer<SupplierImportResolutionReadResult>();
      h.resolutions.onRead = () => read.future;
      final task = h.controller.load();
      expect(
        (await h.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      read.complete(const SupplierImportResolutionNotStarted());
      await task;
      expect(
        (await h.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      h.dispose();
      expect(
        (await h.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      expect(h.generatedIds, 0);
    },
  );
  for (final phase in ['callable', 'resolution', 'draft']) {
    test('dispose ignores late $phase completion', () async {
      await h.controller.load();
      final gate = Completer<void>();
      final entered = Completer<void>();
      h.finalizations.onExecute = (_) async {
        if (phase == 'callable') {
          entered.complete();
          await gate.future;
        }
        h.seal();
        return finalizationOutcome('applied');
      };
      if (phase == 'resolution') {
        h.resolutions.onRead = () async {
          entered.complete();
          await gate.future;
          return reviewResolution(revision: 3, finalized: true);
        };
      }
      if (phase == 'draft') {
        h.drafts.onRead = () async {
          entered.complete();
          await gate.future;
          return h.drafts.value;
        };
      }
      final task = h.controller.finalizeReview();
      await entered.future;
      final state = h.controller.state;
      final calls = List.of(h.calls);
      h.dispose();
      gate.complete();
      await task;
      expect(h.controller.state, same(state));
      expect(h.calls, calls);
    });
  }
  test(
    'older draft refresh cannot overwrite newer authoritative state',
    () async {
      h.seal();
      final old = Completer<ItineraryDraftV2>();
      final entered = Completer<void>();
      h.drafts.onRead = () {
        entered.complete();
        return old.future;
      };
      final task = h.controller.load();
      await entered.future;
      h.drafts.onRead = null;
      await h.controller.refresh();
      final latest = h.controller.state;
      old.complete(h.drafts.value);
      await task;
      expect(h.controller.state, same(latest));
    },
  );
  test(
    'dependencies inject finalizer and V2 reader without Firebase in controller',
    () async {
      final dependencies = SupplierImportReviewDependencies(
        snapshots: h.snapshots,
        resolutions: h.resolutions,
        mutations: h.mutations,
        finalizations: h.finalizations,
        drafts: h.drafts,
      );
      final c = dependencies.createController('trip-1', 'extraction-1');
      addTearDown(c.dispose);
      await c.load();
      h.finalizations.outcome = finalizationOutcome('not_ready');
      await c.finalizeReview();
      expect(h.finalizations.requests, hasLength(1));
      final code = File(
        'lib/features/itineraries/presentation/controllers/supplier_import_review_finalization.dart',
      ).readAsStringSync();
      expect(code, isNot(contains('FirebaseFirestore')));
      expect(code, isNot(contains('FirebaseFunctions')));
      expect(code, isNot(contains('assembleSupplierImport')));
    },
  );
  test(
    'capacity stays blocked at unchanged revision, including after refresh',
    () async {
      await h.controller.load();
      h.finalizations.outcome = finalizationOutcome(
        'persistence_capacity_exceeded',
      );
      await h.controller.finalizeReview();
      expect(
        (await h.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      await h.controller.refresh();
      expect(
        (await h.controller.finalizeReview())!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      expect(h.finalizations.requests, hasLength(1));
      h.resolutions.value = reviewResolution(revision: 4);
      await h.controller.refresh();
      h.finalizations.outcome = finalizationOutcome('not_ready', revision: 5);
      expect(await h.controller.finalizeReview(), isNull);
      expect(h.finalizations.requests.last.expectedRevision, 4);
      expect(h.finalizations.requests, hasLength(2));
    },
  );
  test('failed refresh cannot remove ambiguous exact-command retry', () async {
    await h.controller.load();
    h.finalizations.error = const SupplierImportFinalizationFailure(
      SupplierImportFinalizationFailureKind.unavailable,
    );
    await h.controller.finalizeReview();
    final command = h.finalizations.requests.single;
    h.resolutions.error = StateError('PRIVATE');
    await h.controller.refresh();
    expect(
      (h.controller.state as SupplierImportReviewFailed).recovery,
      SupplierImportReviewRecovery.retryPendingFinalization,
    );
    expect(h.controller.state.finalization!.request, same(command));
    h.resolutions.error = null;
    h.finalizations.error = null;
    h.seal();
    h.finalizations.outcome = finalizationOutcome('already_applied');
    expect(await h.controller.retryPendingFinalization(), isNull);
    expect(h.finalizations.requests.last, same(command));
  });
  test(
    'ambiguous refresh finding sealed V2 preserves exact retry, never permits edits',
    () async {
      await h.controller.load();
      h.finalizations.error = const SupplierImportFinalizationFailure(
        SupplierImportFinalizationFailureKind.unavailable,
      );
      await h.controller.finalizeReview();
      final command = h.finalizations.requests.single;
      h.seal();
      await h.controller.refresh();
      expect(h.controller.state.loaded, isA<SupplierImportReviewFinalized>());
      expect(h.controller.state.finalization!.request, same(command));
      expect(
        (await h.controller.setDecision(reviewTitleDecision))!.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      h.finalizations.error = null;
      h.finalizations.outcome = finalizationOutcome('already_applied');
      expect(await h.controller.retryPendingFinalization(), isNull);
      expect(h.generatedIds, 1);
    },
  );
  for (final name in [
    'not_ready',
    'resolution_conflict',
    'resolution_not_started',
    'resolution_finalized',
    'persistence_capacity_exceeded',
  ]) {
    test(
      '$name survives failed follow-up read without transport replay',
      () async {
        await h.controller.load();
        h.finalizations.outcome = finalizationOutcome(name);
        h.resolutions.error = StateError('PRIVATE');
        await h.controller.finalizeReview();
        expect(
          h.controller.state.finalization!.outcome,
          same(h.finalizations.outcome),
        );
        expect(h.controller.state.finalization!.request, isNull);
        expect(
          (await h.controller.retryPendingFinalization())!.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        h.resolutions.error = null;
        if (name == 'resolution_finalized') h.seal();
        if (name == 'resolution_not_started') {
          h.resolutions.value = const SupplierImportResolutionNotStarted();
        }
        expect(await h.controller.refresh(), isNull);
        expect(h.finalizations.requests, hasLength(1));
      },
    );
  }
  for (final name in ['applied', 'not_ready']) {
    test(
      '$name response revision mismatch is ambiguous and never read as success',
      () async {
        await h.controller.load();
        h.finalizations.outcome = finalizationOutcome(name, revision: 8);
        expect(
          (await h.controller.finalizeReview())!.kind,
          SupplierImportReviewErrorKind.malformedData,
        );
        expect(
          h.controller.state.finalization!.request,
          same(h.finalizations.requests.single),
        );
        expect(h.resolutions.readCount, 1);
      },
    );
  }
  test(
    'older failed draft read cannot overwrite newer successful refresh',
    () async {
      h.seal();
      final old = Completer<ItineraryDraftV2>();
      final entered = Completer<void>();
      h.drafts.onRead = () {
        entered.complete();
        return old.future;
      };
      final task = h.controller.load();
      await entered.future;
      h.drafts.onRead = null;
      await h.controller.refresh();
      final current = h.controller.state;
      old.completeError(StateError('PRIVATE'));
      await task;
      expect(h.controller.state, same(current));
    },
  );
}
