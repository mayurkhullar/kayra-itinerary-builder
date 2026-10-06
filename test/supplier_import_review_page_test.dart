import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_extraction_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_mutation_client.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/pages/supplier_import_review_page.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/review_components.dart';

import 'support/supplier_extraction_fixture.dart';
import 'support/supplier_import_review_fixture.dart';
import 'support/supplier_import_resolution_fixture.dart';

void main() {
  late ReviewHarness h;
  late SupplierImportReviewDependencies dependencies;
  setUp(() {
    h = ReviewHarness();
    dependencies = SupplierImportReviewDependencies(
      snapshots: h.snapshots,
      resolutions: h.resolutions,
      mutations: h.mutations,
    );
  });
  tearDown(() => h.dispose());

  Future<void> show(
    WidgetTester tester, {
    double width = 1440,
    bool settle = true,
    double textScale = 1,
    VoidCallback? onBack,
  }) async {
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
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SupplierImportReviewPage(
            tripId: 'trip-1',
            extractionId: 'extraction-1',
            dependencies: dependencies,
            onBack: onBack ?? () {},
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> tap(
    WidgetTester tester,
    String key, {
    bool settle = true,
  }) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Finder inside(String key, String text) =>
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));

  testWidgets('loading renders a framed state with header and Back', (
    tester,
  ) async {
    final pending = Completer<SupplierExtractionSnapshot>();
    h.snapshots.onRead = () => pending.future;
    await show(tester, settle: false);
    expect(find.text('Review supplier extraction'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-loading')), findsOneWidget);
    expect(find.text('Loading supplier extraction…'), findsOneWidget);
    expect(find.text('Back to Trip Workspace'), findsOneWidget);
    expect(find.text('Start review'), findsNothing);
    pending.complete(h.snapshots.value);
    await tester.pumpAndSettle();
  });

  testWidgets('opening shows complete not-started Snapshot without mutation', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('Japan Discovery'), findsOneWidget);
    expect(find.text('Start review'), findsOneWidget);
    expect(h.snapshots.readCount, 1);
    expect(h.resolutions.readCount, 1);
    expect(h.mutations.requests, isEmpty);
    for (final section in [
      'review-issues',
      'review-itinerary',
      'review-unassigned',
      'review-package-accommodation',
      'review-package-inclusions',
      'review-package-exclusions',
      'review-package-conditions',
      'review-flights',
      'review-visas',
      'review-commercial-notice',
    ]) {
      expect(find.byKey(ValueKey(section)), findsOneWidget);
    }
  });

  testWidgets(
    'summary uses actual counts and explicit blocker/warning severity',
    (tester) async {
      await show(tester);
      for (final (label, count) in [
        ('Days', 2),
        ('Services', 3),
        ('Unassigned services', 1),
        ('Package facts', 4),
        ('Flights', 1),
        ('Visa facts', 1),
        ('Review issues', 6),
        ('Blockers', 3),
        ('Warnings', 3),
      ]) {
        expect(
          tester.widget<Text>(find.byKey(ValueKey('review-count-$label'))).data,
          '$count',
        );
      }
      expect(find.widgetWithText(ReviewBadge, 'Blocker'), findsNWidgets(3));
      expect(find.widgetWithText(ReviewBadge, 'Warning'), findsNWidgets(3));
      expect(find.text('Resolution required'), findsNWidgets(3));
      expect(find.text('Whole extraction'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('review-issue-review-2')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('review-issue-review-1')))
              .dy,
        ),
      );
    },
  );

  testWidgets(
    'days preserve source numbering, explicit dates, order and assigned services',
    (tester) async {
      await show(tester);
      expect(inside('review-day-staged-day-1', 'Source day 3'), findsOneWidget);
      expect(inside('review-day-staged-day-2', 'Source day 7'), findsOneWidget);
      expect(inside('review-day-staged-day-1', '10 Apr 2027'), findsWidgets);
      expect(inside('review-day-staged-day-2', '12 Apr 2027'), findsOneWidget);
      expect(inside('review-day-staged-day-1', 'Hotel stay'), findsOneWidget);
      expect(
        inside('review-day-staged-day-2', 'Kyoto city tour'),
        findsOneWidget,
      );
      expect(
        inside('review-day-staged-day-1', 'Kyoto city tour'),
        findsNothing,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('review-day-staged-day-1')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('review-day-staged-day-2')))
              .dy,
        ),
      );
      expect(find.text('Arrival and hotel check-in.'), findsOneWidget);
      expect(
        find.text('Operating order is supplier supplied.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'hotel, transfer and activity structured fields render faithfully',
    (tester) async {
      await show(tester);
      for (final text in [
        'Example Tokyo Hotel',
        'Check-in',
        'Check-out',
        'Deluxe Room',
        'Breakfast',
        'Rooms',
        '4 Star',
        'Narita Airport',
        'Tokyo hotel',
        'Coach',
        'Shared',
        '4 hours',
        'Sightseeing',
        '10:30',
        '12:00',
        'Central district',
      ]) {
        expect(find.text(text), findsWidgets);
      }
      expect(inside('review-service-staged-service-1', 'Pickup'), findsNothing);
      expect(
        inside('review-service-staged-service-3', 'Check-in'),
        findsNothing,
      );
      expect(
        inside('review-service-staged-service-2', 'Kyoto city tour'),
        findsOneWidget,
      );
      expect(find.text('Service inclusions'), findsNWidgets(3));
      expect(find.text('Service conditions'), findsNWidgets(3));
      expect(find.text('Keep supplier operating notes.'), findsNWidgets(3));
    },
  );

  testWidgets('unassigned services stay outside all day cards', (tester) async {
    await show(tester);
    expect(inside('review-unassigned', 'Airport transfer'), findsOneWidget);
    expect(inside('review-itinerary', 'Airport transfer'), findsNothing);
    expect(find.text('Needs day assignment'), findsOneWidget);
  });

  testWidgets(
    'package scope and statement groups stay separate with all attributes',
    (tester) async {
      await show(tester);
      expect(
        inside('review-package-accommodation', 'Example Tokyo Hotel'),
        findsOneWidget,
      );
      expect(inside('review-package-accommodation', 'Nights'), findsOneWidget);
      expect(inside('review-package-accommodation', 'Check-in'), findsNothing);
      expect(inside('review-package-accommodation', 'Check-out'), findsNothing);
      expect(
        inside('review-package-inclusions', 'Three dinners'),
        findsOneWidget,
      );
      expect(
        inside('review-package-exclusions', 'Lunches not stated as included'),
        findsOneWidget,
      );
      expect(
        inside('review-package-conditions', 'Shared basis'),
        findsOneWidget,
      );
      expect(inside('review-package-inclusions', 'per stay'), findsOneWidget);
      expect(
        inside('review-package-inclusions', 'Hotel · Meal'),
        findsOneWidget,
      );
      expect(
        inside('review-package-conditions', 'Transfer · Sightseeing'),
        findsOneWidget,
      );
    },
  );

  testWidgets('flight and visa facts retain distinct non-commercial fields', (
    tester,
  ) async {
    await show(tester);
    for (final text in [
      'Example Air · EA 101',
      'DEL',
      'NRT',
      '9 Apr 2027',
      '22:15',
      '08:30',
      'Economy',
      'Y',
      'Direct sector',
      'Economy class',
    ]) {
      expect(inside('review-flights', text), findsWidgets);
    }
    expect(inside('review-flights', 'Other'), findsNothing);
    expect(inside('review-itinerary', 'Example Air · EA 101'), findsNothing);
    expect(inside('review-visas', 'Requirement'), findsOneWidget);
    expect(
      inside('review-visas', 'Visa required before travel.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'commercial indicator displays notice only and provenance exposes no IDs',
    (tester) async {
      await show(tester);
      expect(
        find.textContaining('Commercial information was detected'),
        findsOneWidget,
      );
      expect(find.text('Source: Page 1'), findsWidgets);
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join('\n');
      for (final forbidden in [
        'package-1',
        'file-1',
        'trip-1',
        'extraction-1',
        'agent-1',
        'staged-service-1',
        'supplier_extraction_snapshot_v1',
        'gs://',
        'Firestore',
        'Gemini',
        'INR',
        'USD',
        'Markup',
        'Currency',
        'Payment terms',
      ]) {
        expect(text, isNot(contains(forbidden)));
      }
      expect(text, isNot(contains('%')));
    },
  );

  testWidgets(
    'empty issues and chronology show compact truthful empty states',
    (tester) async {
      h.snapshots.value = _emptySnapshot();
      await show(tester);
      expect(
        find.text('No review issues were flagged in this extraction.'),
        findsOneWidget,
      );
      expect(find.textContaining('No day-by-day chronology'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-unassigned')), findsNothing);
      expect(find.byKey(const ValueKey('review-flights')), findsNothing);
      expect(
        find.byKey(const ValueKey('review-commercial-notice')),
        findsNothing,
      );
    },
  );

  testWidgets('sparse fields produce no invented dates or empty labels', (
    tester,
  ) async {
    final service = supplierExtractionService(
      id: 'staged-service-1',
      order: 1,
      scope: {'kind': 'unassigned'},
      serviceType: null,
      title: 'Unclassified service',
    );
    for (final field in [
      'description',
      'startTime',
      'endTime',
      'location',
      'city',
      'notes',
    ]) {
      service[field] = null;
    }
    service['inclusions'] = <Object?>[];
    service['exclusions'] = <Object?>[];
    service['conditions'] = <Object?>[];
    h.snapshots.value = _emptySnapshot(
      facts: [supplierExtractionChild(service, 1)],
      unassigned: 1,
    );
    await show(tester);
    expect(find.text('Unclassified service'), findsOneWidget);
    expect(find.text('Type needs review'), findsOneWidget);
    for (final label in [
      'Start time',
      'End time',
      'City',
      'Location',
      'Check-in',
      'Room type',
      'null',
    ]) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets(
    'Start Review executes once, disables duplicate taps and keeps content visible',
    (tester) async {
      final pending = Completer<SupplierImportResolutionMutationOutcome>();
      h.mutations.onExecute = (_) => pending.future;
      await show(tester);
      await tap(tester, 'start-supplier-review', settle: false);
      expect(h.mutations.requests, hasLength(1));
      expect(
        h.mutations.requests.single.mutation,
        isA<SupplierImportStartReviewCommand>(),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('start-supplier-review')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Starting review…'), findsOneWidget);
      expect(find.text('Japan Discovery'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start-supplier-review')));
      expect(h.mutations.requests, hasLength(1));
      h.resolutions.value = reviewResolution();
      pending.complete(reviewOutcome('applied', revision: 1));
      await tester.pumpAndSettle();
      expect(find.text('Review in progress'), findsOneWidget);
      expect(find.text('Start review'), findsNothing);
    },
  );

  for (final finalized in [false, true]) {
    testWidgets(
      '${finalized ? "finalized" : "active"} resolution is read-only with history',
      (tester) async {
        h.resolutions.value = reviewResolution(
          revision: 2,
          finalized: finalized,
        );
        await show(tester);
        expect(
          find.text(finalized ? 'Finalized' : 'Review in progress'),
          findsOneWidget,
        );
        if (finalized) {
          expect(find.text('Finalized · Read-only'), findsOneWidget);
        }
        expect(find.text('Start review'), findsNothing);
        expect(find.byKey(const ValueKey('review-history')), findsOneWidget);
        await tap(tester, 'review-history-events');
        expect(find.text('Open review'), findsOneWidget);
        expect(h.mutations.requests, isEmpty);
      },
    );
  }

  testWidgets('Refresh reuses Snapshot and retains content during read', (
    tester,
  ) async {
    await show(tester);
    final read = Completer<SupplierImportResolutionReadResult>();
    h.resolutions.onRead = () => read.future;
    await tap(tester, 'refresh-supplier-review', settle: false);
    expect(find.text('Refreshing…'), findsOneWidget);
    expect(find.text('Japan Discovery'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-itinerary')), findsOneWidget);
    read.complete(reviewResolution());
    await tester.pumpAndSettle();
    expect(h.snapshots.readCount, 1);
    expect(h.resolutions.readCount, 2);
    expect(h.mutations.requests, isEmpty);
  });

  testWidgets(
    'recorded decisions and additions remain separate from the immutable Snapshot',
    (tester) async {
      h.resolutions.value = SupplierImportResolutionLoaded(
        SupplierImportResolutionAggregate.fromStoredDocuments(
          expectedTripId: 'trip-1',
          expectedExtractionId: 'extraction-1',
          rootDocumentId: 'extraction-1',
          rootData: supplierImportResolutionRoot(),
          decisionDocuments: [
            (documentId: 'title', data: supplierImportTitleDecision()),
          ],
          manualItemDocuments: [
            (documentId: 'consultant-day-1', data: supplierImportManualDay()),
          ],
          eventDocuments: [
            (documentId: 'command-1', data: supplierImportAuditEvent()),
          ],
        ),
      );
      await show(tester);
      expect(inside('review-history', 'Itinerary title'), findsOneWidget);
      expect(inside('review-history', 'Accept'), findsOneWidget);
      expect(inside('review-history', 'Consultant day'), findsOneWidget);
      expect(inside('review-itinerary', 'Consultant day'), findsNothing);
      expect(
        find.text('1 recorded decisions · 1 consultant additions'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('review-count-Days')))
            .data,
        '2',
      );
      expect(h.mutations.requests, isEmpty);
    },
  );

  for (final kind in SupplierImportResolutionRepositoryFailureKind.values) {
    testWidgets(
      'resolution $kind displays safe recoverable error without mutation',
      (tester) async {
        h.resolutions.error = SupplierImportResolutionRepositoryFailure(
          kind,
          'SECRET Firebase gs://private/path',
        );
        await show(tester);
        expect(find.text('Review unavailable'), findsOneWidget);
        if (kind ==
            SupplierImportResolutionRepositoryFailureKind.permissionDenied) {
          expect(find.textContaining('do not have access'), findsOneWidget);
        }
        expect(find.textContaining('SECRET'), findsNothing);
        expect(find.text('Start review'), findsNothing);
        h.resolutions.error = null;
        await tap(tester, 'reload-review');
        expect(find.text('Japan Discovery'), findsOneWidget);
        expect(h.snapshots.readCount, 1);
        expect(h.mutations.requests, isEmpty);
      },
    );
  }

  testWidgets(
    'ambiguous retry sends the exact same request and never another Start Review',
    (tester) async {
      h.mutations.error = const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.unavailable,
      );
      await show(tester);
      await tap(tester, 'start-supplier-review');
      final original = h.mutations.requests.single;
      expect(find.text('Retry same request'), findsOneWidget);
      expect(find.text('Start review'), findsNothing);
      h.mutations.error = null;
      h.mutations.outcome = reviewOutcome('already_applied', revision: 1);
      h.resolutions.value = reviewResolution();
      await tap(tester, 'retry-review-request');
      expect(h.mutations.requests, hasLength(2));
      expect(h.mutations.requests.last, same(original));
      expect(find.text('Review in progress'), findsOneWidget);
      expect(find.text(original.commandId), findsNothing);
    },
  );

  testWidgets('conflict shows reloaded notice with no automatic replay', (
    tester,
  ) async {
    await show(tester);
    h.resolutions.value = reviewResolution(revision: 3);
    h.mutations.outcome = reviewOutcome('resolution_conflict', revision: 3);
    await tap(tester, 'start-supplier-review');
    expect(
      find.text(
        'This review changed elsewhere. The latest version has been reloaded.',
      ),
      findsOneWidget,
    );
    expect(find.text('Review in progress'), findsOneWidget);
    expect(find.text('Retry same request'), findsNothing);
    expect(h.mutations.requests, hasLength(1));
  });

  for (final kind in SupplierExtractionRepositoryFailureKind.values) {
    testWidgets('safe $kind loading failure offers reload without raw text', (
      tester,
    ) async {
      h.snapshots.error = SupplierExtractionRepositoryFailure(
        kind,
        'SECRET gs://private/path Firebase stack',
      );
      await show(tester);
      expect(find.text('Review unavailable'), findsOneWidget);
      expect(find.text('Reload review'), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      h.snapshots.error = null;
      await tap(tester, 'reload-review');
      expect(find.text('Japan Discovery'), findsOneWidget);
      expect(h.mutations.requests, isEmpty);
    });
  }

  testWidgets('mount owns one controller and disposal ignores a late read', (
    tester,
  ) async {
    final pending = Completer<SupplierExtractionSnapshot>();
    h.snapshots.onRead = () => pending.future;
    await show(tester, settle: false);
    await tester.pump();
    expect(h.snapshots.readCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(h.snapshots.value);
    await tester.pumpAndSettle();
    expect(h.resolutions.readCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Back delegates to workspace context and no decision/finalization controls exist',
    (tester) async {
      var backs = 0;
      await show(tester, onBack: () => backs++);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(DropdownButton), findsNothing);
      final buttons = find.byWidgetPredicate(
        (widget) => widget is ButtonStyleButton,
      );
      final labels = tester
          .widgetList<ButtonStyleButton>(buttons)
          .map((button) => button.toString())
          .join();
      expect(labels, isNot(contains('Finalize')));
      for (final label in [
        'Finalize',
        'Approve import',
        'Create itinerary',
        'Convert to draft',
        'Assign',
        'Move',
        'Exclude',
        'Accept',
        'Add day',
        'Add service',
      ]) {
        expect(
          find.descendant(of: buttons, matching: find.text(label)),
          findsNothing,
        );
      }
      await tap(tester, 'back-to-trip-workspace');
      expect(backs, 1);
      expect(h.mutations.requests, isEmpty);
    },
  );

  for (final width in <double>[375, 390, 430, 768, 1024, 1280, 1440, 1920]) {
    testWidgets(
      '${width.toInt()}px complete review has no overflow or clipping',
      (tester) async {
        await show(tester, width: width);
        for (final key in [
          'review-summary',
          'review-issues',
          'review-day-staged-day-1',
          'review-unassigned',
          'review-package-inclusions',
          'review-flights',
          'review-visas',
          'review-commercial-notice',
        ]) {
          await tester.ensureVisible(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(rect.left, greaterThanOrEqualTo(19));
          expect(rect.right, lessThanOrEqualTo(width - 19));
        }
      },
    );
  }

  testWidgets('390px enlarged text and long supplier content wrap', (
    tester,
  ) async {
    final root = supplierExtractionRoot();
    (root['title'] as Map<String, Object?>)['text'] =
        'An extended supplier itinerary title with additional operational context for a consultant';
    h.snapshots.value = SupplierExtractionSnapshot.fromStoredDocuments(
      expectedTripId: 'trip-1',
      expectedExtractionId: 'extraction-1',
      root: root,
      dayDocuments: supplierExtractionDayDocuments(),
      factDocuments: supplierExtractionFactDocuments(),
      reviewIssueDocuments: supplierExtractionReviewIssueDocuments(),
      trustedSourceFileIds: const ['file-1'],
    );
    await show(tester, width: 390, textScale: 1.5);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('review-flights')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('buttons have labelled touch targets and keyboard traversal', (
    tester,
  ) async {
    await show(tester, width: 390);
    final semantics = tester.ensureSemantics();
    for (final key in [
      'start-supplier-review',
      'refresh-supplier-review',
      'back-to-trip-workspace',
    ]) {
      final finder = find.byKey(ValueKey(key));
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
    }
    await tester.ensureVisible(find.byKey(const ValueKey('review-count-Days')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'Days: 2')), findsWidgets);
    await tester.ensureVisible(
      find.byKey(const ValueKey('review-issue-review-2')),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'Blocker')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('keyboard can focus and activate Back without any mutation', (
    tester,
  ) async {
    var backs = 0;
    await show(tester, onBack: () => backs++);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(backs, 1);
    expect(h.mutations.requests, isEmpty);
  });

  test('page delegates review actions and has no direct Firebase writes', () {
    final page = File(
      'lib/features/itineraries/presentation/pages/supplier_import_review_page.dart',
    ).readAsStringSync();
    for (final forbidden in [
      'FirebaseFirestore',
      'FirebaseFunctions',
      'upsertManualItem(',
      'removeManualItem(',
      'finalize(',
    ]) {
      expect(page, isNot(contains(forbidden)));
    }
    expect(page, contains('_controller.startReview'));
    expect(page, contains('_controller.refresh'));
    expect(page, contains('_controller.retryPendingMutation'));
    expect(page, contains('controller.setDecision(decision)'));
    expect(page, contains('controller.removeDecision(decisionId)'));
    expect(page, contains('..dispose()'));
  });
}

SupplierExtractionSnapshot _emptySnapshot({
  List<SupplierExtractionStoredDocument> facts = const [],
  int unassigned = 0,
}) => SupplierExtractionSnapshot.fromStoredDocuments(
  expectedTripId: 'trip-1',
  expectedExtractionId: 'extraction-1',
  root: supplierExtractionRoot(
    counts: supplierExtractionCounts(
      days: 0,
      assignedServices: 0,
      unassignedServices: unassigned,
      packageFacts: 0,
      ancillaryFlights: 0,
      ancillaryVisas: 0,
      commercialIndicators: 0,
      reviewIssues: 0,
    ),
  ),
  dayDocuments: const [],
  factDocuments: facts,
  reviewIssueDocuments: const [],
  trustedSourceFileIds: const ['file-1'],
);
