import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_mutation_client.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_controller.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_error.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_state.dart';

import 'support/supplier_import_review_fixture.dart';

void main() {
  late ReviewHarness h;
  setUp(() => h = ReviewHarness());
  tearDown(() => h.dispose());

  for (final outcome in ['applied', 'already_applied']) {
    test(
      'startReview $outcome creates one intent at revision zero and reloads',
      () async {
        await h.controller.load();
        final previous = h.controller.state;
        final saved = reviewResolution(revision: 3);
        h.mutations.onExecute = (request) {
          final saving = h.controller.state as SupplierImportReviewSaving;
          expect(saving.loaded, same(previous));
          expect(saving.pendingMutation, same(request));
          h.resolutions.value = saved;
          return reviewOutcome(outcome, revision: 1);
        };

        expect(await h.controller.startReview(), isNull);
        expect(h.generatedIds, 1);
        final request = h.mutations.requests.single;
        expect(request.toMap(), {
          'tripId': 'trip-1',
          'extractionId': 'extraction-1',
          'expectedRevision': 0,
          'commandId': 'intent-1',
          'mutation': {'action': 'start_review'},
        });
        expect(
          (h.controller.state as SupplierImportReviewActive).resolution,
          same(saved.resolution),
        );
        expect(h.controller.state.pendingMutation, isNull);
        expect(h.calls, [
          'snapshot:trip-1/extraction-1',
          'resolution:trip-1/extraction-1',
          'mutation:start_review',
          'resolution:trip-1/extraction-1',
        ]);
      },
    );
  }

  final actions =
      <
        String,
        Future<SupplierImportReviewError?> Function(
          SupplierImportReviewController,
        )
      >{
        'set_decision': (c) => c.setDecision(reviewTitleDecision),
        'remove_decision': (c) => c.removeDecision('title'),
        'upsert_manual_item': (c) => c.upsertManualItem(reviewManualDay),
        'remove_manual_item': (c) => c.removeManualItem('consultant-day-1'),
      };
  for (final action in actions.entries) {
    for (final outcome in ['applied', 'already_applied']) {
      test(
        '${action.key} $outcome uses loaded revision and authoritative refresh',
        () async {
          final original = reviewResolution(revision: 4);
          h.resolutions.value = original;
          await h.controller.load();
          final refreshed = reviewResolution(revision: 9);
          h.mutations.onExecute = (request) {
            final state = h.controller.state as SupplierImportReviewSaving;
            expect(
              (state.loaded as SupplierImportReviewActive).resolution,
              same(original.resolution),
            );
            h.resolutions.value = refreshed;
            return reviewOutcome(outcome, revision: 6);
          };

          expect(await action.value(h.controller), isNull);
          expect(h.mutations.requests.single.expectedRevision, 4);
          expect(h.mutations.requests.single.mutation.action, action.key);
          expect(h.generatedIds, 1);
          expect(
            (h.controller.state as SupplierImportReviewActive).resolution,
            same(refreshed.resolution),
          );
          expect(h.resolutions.readCount, 2);
          expect(h.controller.state.pendingMutation, isNull);
        },
      );
    }
  }

  test(
    'local preconditions block mutations before load or before start',
    () async {
      final c = h.controller;
      for (final action in [
        c.startReview,
        ...actions.values.map(
          (a) =>
              () => a(c),
        ),
      ]) {
        expect(
          (await action())?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
      }
      await c.load();
      for (final action in actions.values) {
        expect(
          (await action(c))?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
      }
      expect(h.mutations.requests, isEmpty);
      expect(h.generatedIds, 0);
      expect(c.state, isA<SupplierImportReviewNotStarted>());
    },
  );

  for (final finalized in [false, true]) {
    test(
      'startReview is blocked for ${finalized ? "finalized" : "active"} resolution',
      () async {
        h.resolutions.value = reviewResolution(
          revision: 2,
          finalized: finalized,
        );
        await h.controller.load();
        expect(
          (await h.controller.startReview())?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        if (finalized) {
          for (final action in actions.values) {
            expect(
              (await action(h.controller))?.kind,
              SupplierImportReviewErrorKind.invalidLocalAction,
            );
          }
        }
        expect(h.mutations.requests, isEmpty);
        expect(h.generatedIds, 0);
      },
    );
  }

  test(
    'conflict reloads and exposes revision without replaying or rewriting intent',
    () async {
      h.resolutions.value = reviewResolution(revision: 2);
      await h.controller.load();
      final oldDisplay = h.controller.state;
      final read = Completer<SupplierImportResolutionReadResult>();
      final readStarted = Completer<void>();
      h.resolutions.onRead = () {
        readStarted.complete();
        return read.future;
      };
      h.mutations.outcome = reviewOutcome('resolution_conflict', revision: 5);
      final mutation = h.controller.setDecision(reviewTitleDecision);
      await readStarted.future;
      expect(h.controller.state.loaded, same(oldDisplay));
      read.complete(reviewResolution(revision: 7));
      expect(await mutation, isNull);
      final state = h.controller.state as SupplierImportReviewConflict;
      expect(state.currentRevision, 5);
      expect(
        (state.loaded as SupplierImportReviewActive).resolution.root.revision,
        7,
      );
      expect(state.pendingMutation, isNull);
      expect(h.mutations.requests.single.expectedRevision, 2);
      expect(h.generatedIds, 1);
      expect(
        (await h.controller.retryPendingMutation())?.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      expect(h.mutations.requests, hasLength(1));

      // Only a fresh, explicit intent can use the freshly read revision.
      h.resolutions.onRead = null;
      h.resolutions.value = reviewResolution(revision: 8);
      h.mutations.outcome = reviewOutcome('applied', revision: 8);
      expect(await h.controller.removeDecision('title'), isNull);
      expect(h.mutations.requests.last.expectedRevision, 7);
      expect(h.mutations.requests.last.commandId, 'intent-2');
    },
  );

  test(
    'not-started outcome reloads absence and permits explicit Start Review',
    () async {
      h.resolutions.value = reviewResolution();
      await h.controller.load();
      h.resolutions.value = const SupplierImportResolutionNotStarted();
      h.mutations.outcome = reviewOutcome(
        'resolution_not_started',
        revision: 0,
      );
      await h.controller.removeDecision('title');
      expect(h.controller.state, isA<SupplierImportReviewNotStarted>());
      expect(h.controller.state.pendingMutation, isNull);
      expect(h.mutations.requests, hasLength(1));
      h.mutations.onExecute = (_) {
        h.resolutions.value = reviewResolution();
        return reviewOutcome('applied', revision: 1);
      };
      await h.controller.startReview();
      expect(h.mutations.requests.last.expectedRevision, 0);
    },
  );

  test(
    'finalized outcome reloads locked state and blocks all future commands',
    () async {
      h.resolutions.value = reviewResolution();
      await h.controller.load();
      final locked = reviewResolution(revision: 3, finalized: true);
      h.resolutions.value = locked;
      h.mutations.outcome = reviewOutcome('resolution_finalized', revision: 3);
      await h.controller.removeDecision('title');
      expect(
        (h.controller.state as SupplierImportReviewFinalized).resolution,
        same(locked.resolution),
      );
      expect(h.controller.state.pendingMutation, isNull);
      for (final action in actions.values) {
        expect(
          (await action(h.controller))?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
      }
      expect(
        (await h.controller.retryPendingMutation())?.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      expect(h.mutations.requests, hasLength(1));
    },
  );

  for (final failure in <String, Object>{
    'unavailable/deadline mapped by client':
        const SupplierImportMutationFailure(
          SupplierImportMutationFailureKind.unavailable,
        ),
    'timeout': TimeoutException('private transport text'),
    'unknown network failure': StateError('private transport text'),
    'internal possibly committed failure': const SupplierImportMutationFailure(
      SupplierImportMutationFailureKind.internal,
    ),
  }.entries) {
    for (final outcome in ['applied', 'already_applied']) {
      test(
        '${failure.key} retains exact request for explicit $outcome retry',
        () async {
          h.resolutions.value = reviewResolution(revision: 4);
          await h.controller.load();
          h.mutations.error = failure.value;
          await h.controller.setDecision(reviewTitleDecision);
          final failed = h.controller.state as SupplierImportReviewFailed;
          final original = h.mutations.requests.single;
          final body = original.toMap();
          expect(
            failed.recovery,
            SupplierImportReviewRecovery.retryPendingMutation,
          );
          expect(failed.pendingMutation, same(original));
          expect(failed.error.userMessage, isNot(contains('private')));
          expect(
            (await h.controller.removeDecision('title'))?.kind,
            SupplierImportReviewErrorKind.invalidLocalAction,
          );
          expect(h.generatedIds, 1);

          h.mutations.error = null;
          h.mutations.outcome = reviewOutcome(outcome, revision: 5);
          h.resolutions.value = reviewResolution(revision: 6);
          expect(await h.controller.retryPendingMutation(), isNull);
          expect(h.mutations.requests.last, same(original));
          expect(original.toMap(), body);
          expect(original.expectedRevision, 4);
          expect(original.commandId, 'intent-1');
          expect(h.generatedIds, 1);
          expect(h.mutations.requests, hasLength(2));
          expect(h.controller.state.pendingMutation, isNull);
          expect(
            (h.controller.state as SupplierImportReviewActive)
                .resolution
                .root
                .revision,
            6,
          );
        },
      );
    }
  }

  test(
    'ambiguous Start Review retry preserves revision zero and original command',
    () async {
      await h.controller.load();
      h.mutations.error = const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.unavailable,
      );
      await h.controller.startReview();
      final command = h.mutations.requests.single;
      h.mutations.error = null;
      h.mutations.outcome = reviewOutcome('already_applied', revision: 1);
      h.resolutions.value = reviewResolution();
      await h.controller.retryPendingMutation();
      expect(h.mutations.requests.last, same(command));
      expect(command.expectedRevision, 0);
      expect(h.generatedIds, 1);
    },
  );

  for (final entry in {
    SupplierImportMutationFailureKind.invalidMutation:
        SupplierImportReviewErrorKind.invalidMutation,
    SupplierImportMutationFailureKind.permissionDenied:
        SupplierImportReviewErrorKind.permissionDenied,
    SupplierImportMutationFailureKind.sessionExpired:
        SupplierImportReviewErrorKind.sessionExpired,
    SupplierImportMutationFailureKind.invalidState:
        SupplierImportReviewErrorKind.serverPrecondition,
  }.entries) {
    test(
      '${entry.key} clears deterministic pending command and retains display',
      () async {
        h.resolutions.value = reviewResolution();
        await h.controller.load();
        final previous = h.controller.state;
        h.mutations.error = SupplierImportMutationFailure(entry.key);
        expect(
          (await h.controller.setDecision(reviewTitleDecision))?.kind,
          entry.value,
        );
        final failed = h.controller.state as SupplierImportReviewFailed;
        expect(failed.loaded, same(previous));
        expect(failed.pendingMutation, isNull);
        expect(failed.error.mutationFailureKind, entry.key);
        expect(
          (await h.controller.retryPendingMutation())?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        expect(h.mutations.requests, hasLength(1));
      },
    );
  }

  test(
    'double invocation and overlapping new intents are rejected before ID generation',
    () async {
      await h.controller.load();
      final network = Completer<SupplierImportResolutionMutationOutcome>();
      h.mutations.onExecute = (_) => network.future;
      final first = h.controller.startReview();
      final saving = h.controller.state;
      expect(saving, isA<SupplierImportReviewSaving>());
      for (final action in [
        h.controller.startReview,
        h.controller.refresh,
        h.controller.retryPendingMutation,
        () => h.controller.setDecision(reviewTitleDecision),
      ]) {
        expect(
          (await action())?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        expect(h.controller.state, same(saving));
      }
      expect(h.generatedIds, 1);
      expect(h.mutations.requests, hasLength(1));
      h.resolutions.value = reviewResolution();
      network.complete(reviewOutcome('applied', revision: 1));
      await first;
    },
  );

  for (final outcome in ['applied', 'already_applied']) {
    test(
      '$outcome followed by read failure retains pending and recovers by read only',
      () async {
        h.resolutions.value = reviewResolution();
        await h.controller.load();
        h.mutations.outcome = reviewOutcome(outcome);
        h.resolutions.error = const SupplierImportResolutionRepositoryFailure(
          SupplierImportResolutionRepositoryFailureKind.readFailed,
          'private detail',
        );
        await h.controller.setDecision(reviewTitleDecision);
        final failed = h.controller.state as SupplierImportReviewFailed;
        expect(failed.pendingMutation, same(h.mutations.requests.single));
        expect(failed.outcomeAwaitingRefresh, same(h.mutations.outcome));
        expect(failed.recovery, SupplierImportReviewRecovery.refresh);
        expect(
          (await h.controller.retryPendingMutation())?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        expect(
          (await h.controller.removeDecision('title'))?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        h.resolutions.error = null;
        h.resolutions.value = reviewResolution(revision: 3);
        expect(await h.controller.refresh(), isNull);
        expect(h.controller.state.pendingMutation, isNull);
        expect(h.mutations.requests, hasLength(1));
        expect(h.generatedIds, 1);
      },
    );
  }

  test(
    'successful response cannot clear pending before its revision is visible',
    () async {
      h.resolutions.value = reviewResolution();
      await h.controller.load();
      h.mutations.outcome = reviewOutcome('applied', revision: 3);
      await h.controller.setDecision(reviewTitleDecision);
      expect(
        (h.controller.state as SupplierImportReviewFailed).error.kind,
        SupplierImportReviewErrorKind.malformedData,
      );
      expect(
        h.controller.state.pendingMutation,
        same(h.mutations.requests.single),
      );
      h.resolutions.value = reviewResolution(revision: 3);
      await h.controller.refresh();
      expect(h.controller.state.pendingMutation, isNull);
    },
  );

  for (final outcome in [
    'resolution_conflict',
    'resolution_finalized',
    'resolution_not_started',
  ]) {
    test(
      '$outcome read failure clears intent but preserves outcome for later refresh',
      () async {
        h.resolutions.value = reviewResolution();
        await h.controller.load();
        h.mutations.outcome = reviewOutcome(
          outcome,
          revision: outcome == 'resolution_not_started' ? 0 : 3,
        );
        h.resolutions.error = StateError('private read details');
        await h.controller.setDecision(reviewTitleDecision);
        final failed = h.controller.state as SupplierImportReviewFailed;
        expect(failed.pendingMutation, isNull);
        expect(failed.outcomeAwaitingRefresh, same(h.mutations.outcome));
        expect(
          (await h.controller.setDecision(reviewTitleDecision))?.kind,
          SupplierImportReviewErrorKind.invalidLocalAction,
        );
        h.resolutions.error = null;
        h.resolutions.value = outcome == 'resolution_not_started'
            ? const SupplierImportResolutionNotStarted()
            : reviewResolution(
                revision: 3,
                finalized: outcome == 'resolution_finalized',
              );
        await h.controller.refresh();
        expect(
          h.controller.state,
          outcome == 'resolution_conflict'
              ? isA<SupplierImportReviewConflict>()
              : outcome == 'resolution_finalized'
              ? isA<SupplierImportReviewFinalized>()
              : isA<SupplierImportReviewNotStarted>(),
        );
        expect(h.mutations.requests, hasLength(1));
      },
    );
  }

  test(
    'ambiguous refresh does not infer success from a changed revision',
    () async {
      h.resolutions.value = reviewResolution();
      await h.controller.load();
      h.mutations.error = const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.unavailable,
      );
      await h.controller.setDecision(reviewTitleDecision);
      final pending = h.mutations.requests.single;
      h.resolutions.value = reviewResolution(revision: 5);
      await h.controller.refresh();
      final failed = h.controller.state as SupplierImportReviewFailed;
      expect(failed.pendingMutation, same(pending));
      expect(
        (failed.loaded as SupplierImportReviewActive).resolution.root.revision,
        5,
      );
      expect(pending.expectedRevision, 1);
      h.mutations.error = null;
      h.mutations.outcome = reviewOutcome('resolution_conflict', revision: 5);
      await h.controller.retryPendingMutation();
      expect(h.mutations.requests.last, same(pending));
      expect(h.controller.state, isA<SupplierImportReviewConflict>());
      expect(h.controller.state.pendingMutation, isNull);
    },
  );

  test(
    'refresh discovering finalization clears ambiguous pending request',
    () async {
      h.resolutions.value = reviewResolution();
      await h.controller.load();
      h.mutations.error = const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.unavailable,
      );
      await h.controller.setDecision(reviewTitleDecision);
      h.resolutions.value = reviewResolution(revision: 3, finalized: true);
      await h.controller.refresh();
      expect(h.controller.state, isA<SupplierImportReviewFinalized>());
      expect(h.controller.state.pendingMutation, isNull);
      expect(
        (await h.controller.retryPendingMutation())?.kind,
        SupplierImportReviewErrorKind.invalidLocalAction,
      );
      expect(h.mutations.requests, hasLength(1));
    },
  );

  test(
    'wrong callable resolution identity fails safely and retains idempotency identity',
    () async {
      await h.controller.load();
      h.mutations.outcome = reviewOutcome(
        'applied',
        resolutionId: 'other-extraction',
      );
      await h.controller.startReview();
      expect(
        (h.controller.state as SupplierImportReviewFailed).error.kind,
        SupplierImportReviewErrorKind.malformedData,
      );
      expect(
        h.controller.state.pendingMutation,
        same(h.mutations.requests.single),
      );
      expect(h.resolutions.readCount, 1);
    },
  );

  test(
    'invalid local identifier is sanitized before callable execution',
    () async {
      h.resolutions.value = reviewResolution();
      await h.controller.load();
      expect(
        (await h.controller.removeDecision('bad/path'))?.kind,
        SupplierImportReviewErrorKind.invalidMutation,
      );
      expect(h.mutations.requests, isEmpty);
      expect(h.generatedIds, 0);
    },
  );
}
