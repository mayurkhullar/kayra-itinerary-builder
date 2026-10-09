import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_draft_v2_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/itinerary_draft_v2.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/pages/supplier_import_review_page.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/canonical/finalized_canonical_view.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/canonical/canonical_service.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/review_components.dart';
import 'support/finalized_canonical_fixture.dart';
import 'support/itinerary_draft_v2_fixture.dart';
import 'support/supplier_import_finalization_fixture.dart';

void main() {
  late FinalizationHarness h;
  setUp(() => h = FinalizationHarness());
  tearDown(() => h.dispose());

  Future<void> show(
    WidgetTester t, {
    Map<String, dynamic>? data,
    bool page = false,
    double width = 1440,
    double scale = 1,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 900);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: page
              ? SupplierImportReviewPage(
                  tripId: 'trip-1',
                  extractionId: 'extraction-1',
                  onBack: () {},
                  dependencies: SupplierImportReviewDependencies(
                    snapshots: h.snapshots,
                    resolutions: h.resolutions,
                    mutations: h.mutations,
                    finalizations: h.finalizations,
                    drafts: h.drafts,
                  ),
                )
              : FinalizedCanonicalView(
                  draft: finalizedCanonicalDraft(
                    data ?? finalizedCanonicalMap(),
                  ),
                  onBack: () {},
                  onRefresh: () {},
                ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  String text(WidgetTester t) =>
      t.widgetList<Text>(find.byType(Text)).map((v) => v.data ?? '').join('\n');
  void canonicalOnly() {
    expect(find.byType(FinalizedCanonicalView), findsOneWidget);
    expect(find.text('Itinerary finalized'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-snapshot-title')), findsNothing);
    for (final label in [
      'Finalize itinerary',
      'Review day',
      'Review service',
      'Edit',
      'Change',
      'Revert',
      'Schedule',
      'Exclude',
      'Use reviewed itinerary',
      'Recorded review',
    ]) {
      expect(find.text(label), findsNothing);
    }
  }

  testWidgets('active Resolution retains the existing review workspace', (
    t,
  ) async {
    await show(t, page: true);
    expect(find.byKey(const ValueKey('review-snapshot-title')), findsOneWidget);
    expect(find.byType(FinalizedCanonicalView), findsNothing);
    expect(find.text('Finalize itinerary'), findsOneWidget);
    expect(h.finalizations.requests, isEmpty);
  });
  for (final outcome in [
    'applied',
    'already_applied',
    'resolution_finalized',
  ]) {
    testWidgets(
      '$outcome immediately hands off to verified canonical content',
      (t) async {
        h.finalizations.onExecute = (request) {
          h.seal();
          h.drafts.value = finalizedCanonicalDraft(
            finalizedCanonicalMap(commandId: request.commandId),
          );
          return finalizationOutcome(outcome);
        };
        await show(t, page: true);
        await t.tap(find.text('Finalize itinerary'));
        await t.pumpAndSettle();
        canonicalOnly();
        expect(find.text('Reviewed coastal journey'), findsOneWidget);
        expect(h.finalizations.requests, hasLength(1));
        expect(h.mutations.requests, isEmpty);
        expect(
          t.getTopLeft(find.text('Itinerary finalized')).dy,
          lessThan(900),
        );
      },
    );
  }
  testWidgets(
    'pre-existing finalized Resolution loads canonical content without a command',
    (t) async {
      h.seal();
      h.drafts.value = finalizedCanonicalDraft(finalizedCanonicalMap());
      await show(t, page: true);
      canonicalOnly();
      expect(h.finalizations.requests, isEmpty);
      expect(h.calls.where((c) => c.startsWith('draft:')), hasLength(1));
    },
  );
  for (final afterSubmit in [false, true]) {
    testWidgets(
      'failed canonical load blocks fake content and refresh never refinalizes: $afterSubmit',
      (t) async {
        h.drafts.error = const ItineraryDraftV2RepositoryFailure(
          ItineraryDraftV2RepositoryFailureKind.readFailed,
        );
        if (afterSubmit) {
          h.finalizations.onExecute = (request) {
            h.seal();
            h.drafts.value = finalizedCanonicalDraft(
              finalizedCanonicalMap(commandId: request.commandId),
            );
            return finalizationOutcome('applied');
          };
        } else {
          h.seal();
        }
        await show(t, page: true);
        if (afterSubmit) {
          await t.tap(find.text('Finalize itinerary'));
          await t.pumpAndSettle();
        }
        expect(find.byType(FinalizedCanonicalView), findsNothing);
        expect(
          find.byKey(const ValueKey('review-snapshot-title')),
          findsNothing,
        );
        expect(find.text('Itinerary finalized'), findsNothing);
        expect(
          find.text(
            'The finalized itinerary could not be loaded safely. Please refresh.',
          ),
          findsOneWidget,
        );
        expect(find.text('Finalize itinerary'), findsNothing);
        await t.pump(const Duration(seconds: 5));
        expect(h.finalizations.requests, hasLength(afterSubmit ? 1 : 0));
        h.drafts.error = null;
        await t.tap(find.byKey(const ValueKey('refresh-supplier-review')));
        await t.pumpAndSettle();
        canonicalOnly();
        expect(h.finalizations.requests, hasLength(afterSubmit ? 1 : 0));
      },
    );
  }
  testWidgets(
    'handoff starts at the result header after scrolling through review',
    (t) async {
      h.finalizations.onExecute = (request) {
        h.seal();
        h.drafts.value = finalizedCanonicalDraft(
          finalizedCanonicalMap(commandId: request.commandId),
        );
        return finalizationOutcome('applied');
      };
      await show(t, page: true, width: 390);
      final scroll = t.state<ScrollableState>(find.byType(Scrollable).first);
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await t.pumpAndSettle();
      await t.tap(find.text('Finalize itinerary'));
      await t.pumpAndSettle();
      canonicalOnly();
      expect(
        t.getTopLeft(find.text('Itinerary finalized')).dy,
        inInclusiveRange(0, 899),
      );
    },
  );

  testWidgets(
    'failed refresh hides a previously loaded canonical result until verified again',
    (t) async {
      h.seal();
      await show(t, page: true);
      canonicalOnly();
      h.drafts.error = const ItineraryDraftV2RepositoryFailure(
        ItineraryDraftV2RepositoryFailureKind.readFailed,
      );
      await t.tap(find.byKey(const ValueKey('refresh-supplier-review')));
      await t.pumpAndSettle();
      expect(find.byType(FinalizedCanonicalView), findsNothing);
      expect(find.byKey(const ValueKey('review-snapshot-title')), findsNothing);
      expect(
        find.text(
          'The finalized itinerary could not be loaded safely. Please refresh.',
        ),
        findsOneWidget,
      );
      expect(h.finalizations.requests, isEmpty);
    },
  );

  testWidgets('mismatched canonical linkage fails closed', (t) async {
    h.seal();
    h.drafts.value = finalizationDraft(tripId: 'another-trip');
    await show(t, page: true);
    expect(find.byType(FinalizedCanonicalView), findsNothing);
    expect(find.text('Itinerary finalized'), findsNothing);
    expect(h.finalizations.requests, isEmpty);
  });
  testWidgets('does not hand off before the canonical read completes', (
    t,
  ) async {
    final pending = Completer<ItineraryDraftV2>();
    h.finalizations.onExecute = (request) {
      h.seal();
      h.drafts.onRead = () => pending.future;
      return finalizationOutcome('applied');
    };
    await show(t, page: true);
    await t.tap(find.text('Finalize itinerary'));
    await t.pump();
    expect(find.byType(FinalizedCanonicalView), findsNothing);
    pending.complete(
      finalizedCanonicalDraft(
        finalizedCanonicalMap(
          commandId: h.finalizations.requests.single.commandId,
        ),
      ),
    );
    await t.pumpAndSettle();
    canonicalOnly();
  });
  testWidgets(
    'private metadata, ancillary history and prices are not rendered',
    (t) async {
      await show(t);
      final rendered = text(t);
      for (final value in [
        'draft-1',
        'extraction-1',
        'intent-1',
        'package-1',
        'file-1',
        'agent-1',
        'Page 1',
        'Page 2',
        'service-hotel',
        'supplier_import',
        'importResult',
        'provenance',
        'Flights',
        'Visa',
        'Commercial information',
        'Cost',
        'Selling price',
        'Markup',
        'Margin',
        'Discount',
        'Package total',
      ]) {
        expect(rendered, isNot(contains(value)), reason: value);
      }
    },
  );
  for (final composition in [
    'one service',
    'several services',
    'package only',
    'days only',
    'days and services',
    'package and services',
    'all',
  ]) {
    testWidgets('renders $composition with no fabricated or empty sections', (
      t,
    ) async {
      final data = finalizedCanonicalMap();
      final days = [
        'days only',
        'days and services',
        'all',
      ].contains(composition);
      final services = !['package only', 'days only'].contains(composition);
      final package = [
        'package only',
        'package and services',
        'all',
      ].contains(composition);
      if (!days) data['days'] = [];
      if (!services) data.remove('unscheduledServices');
      if (composition == 'one service') {
        data['unscheduledServices'] = [
          canonicalServiceMap('only-service', 'Only walk'),
        ];
      }
      if (!package) {
        data['packageContent'] = {
          'accommodations': [],
          'inclusions': [],
          'exclusions': [],
          'conditions': [],
        };
      }
      await show(t, data: data);
      expect(
        find.text('Day-wise itinerary'),
        days ? findsOneWidget : findsNothing,
      );
      expect(find.text('Day 1'), days ? findsOneWidget : findsNothing);
      expect(
        find.text('Included Services'),
        services ? findsOneWidget : findsNothing,
      );
      for (final title in [
        'Package accommodation',
        'Inclusions',
        'Exclusions',
        'Package conditions',
      ]) {
        expect(find.text(title), package ? findsOneWidget : findsNothing);
      }
      for (final invalid in [
        'No itinerary available',
        'Missing days',
        'Day-wise itinerary required',
        'Unscheduled Services',
        'Unassigned Services',
        'Pending Services',
        'Needs Scheduling',
      ]) {
        expect(find.text(invalid), findsNothing);
      }
    });
  }
  testWidgets(
    'canonical day, service and unscheduled array order is preserved',
    (t) async {
      final data = finalizedCanonicalMap();
      (data['days'] as List).add({
        'dayNumber': 2,
        'date': null,
        'title': 'Second day',
        'summary': null,
        'notes': null,
        'services': [canonicalServiceMap('later-service', 'Second day stroll')],
      });
      await show(t, data: data);
      final rendered = text(t);
      final titles = [
        'Coastal arrival',
        'Harbour stay',
        'Arrival transfer',
        'Museum experience',
        'Second day',
        'Second day stroll',
        'Garden walk',
        'Old town visit',
        'Package accommodation',
      ];
      for (var i = 1; i < titles.length; i++) {
        expect(
          rendered.indexOf(titles[i]),
          greaterThan(rendered.indexOf(titles[i - 1])),
        );
      }
      expect(find.byType(CanonicalService), findsNWidgets(6));
    },
  );
  testWidgets('all service types use human-facing labels and one component', (
    t,
  ) async {
    final data = finalizedCanonicalMap()..['days'] = [];
    final types = [
      'hotel',
      'transfer',
      'activity',
      'meal',
      'sightseeing',
      'free_time',
      'other',
    ];
    data['unscheduledServices'] = [
      for (final type in types)
        canonicalServiceMap('type-$type', 'Known $type content', type: type),
    ];
    await show(t, data: data);
    expect(find.byType(CanonicalService), findsNWidgets(7));
    expect(find.text('Free time'), findsOneWidget);
    expect(find.text('free_time'), findsNothing);
  });
  testWidgets('hotel, dates, day content and service facts retain fidelity', (
    t,
  ) async {
    await show(t);
    for (final value in [
      'Hotel city',
      'Timeline Hotel or similar',
      '2',
      'Twin',
      'Breakfast',
      '10 Jan 2027',
      '12 Jan 2027',
      '14:00',
      '15:00',
      'Waterfront district',
      'Service city',
      'Explore the waterfront.',
      'Keep the afternoon flexible.',
      'A quiet base near the promenade.',
    ]) {
      expect(find.text(value), findsWidgets, reason: value);
    }
    expect(find.text('true'), findsNothing);
  });
  testWidgets('service conditions, notes and polarity remain distinct', (
    t,
  ) async {
    await show(t);
    final rendered = text(t);
    for (final pair in [
      ('Service inclusions', 'Welcome drink'),
      ('Service exclusions', 'Laundry'),
      ('Service conditions', 'Subject to availability'),
      ('Service notes', 'Bring identification.'),
      ('Inclusions', 'Lunches'),
      ('Exclusions', 'Dinners'),
      ('Package conditions', 'Shared basis'),
    ]) {
      expect(rendered, contains(pair.$1));
      expect(rendered, contains(pair.$2));
    }
    String section(String title) => t
        .widgetList<Text>(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) => widget is ReviewSection && widget.title == title,
            ),
            matching: find.byType(Text),
          ),
        )
        .map((value) => value.data ?? '')
        .join('\n');
    expect(section('Inclusions'), contains('Lunches'));
    expect(section('Inclusions'), isNot(contains('Dinners')));
    expect(section('Exclusions'), contains('Dinners'));
    expect(section('Exclusions'), isNot(contains('Lunches')));
    expect(section('Package conditions'), contains('Shared basis'));
    expect(
      section('Package conditions'),
      isNot(contains('Subject to availability')),
    );
  });
  testWidgets('transfer and activity render only supported typed values', (
    t,
  ) async {
    await show(t);
    for (final value in [
      'Airport',
      'Hotel',
      'Sedan',
      'Private',
      'Museum visit',
      '2 hours',
      'Guided',
    ]) {
      expect(find.text(value), findsWidgets);
    }
  });
  testWidgets(
    'sparse transfer does not invent endpoints, timing, dates or placeholders',
    (t) async {
      final data = finalizedCanonicalMap()..['days'] = [];
      data['packageContent'] = {
        'accommodations': [],
        'inclusions': [],
        'exclusions': [],
        'conditions': [],
      };
      data['unscheduledServices'] = [
        canonicalServiceMap(
          'sparse-transfer',
          'Transfer by coach',
          type: 'transfer',
        ),
      ];
      await show(t, data: data);
      for (final value in [
        'Pickup',
        'Drop-off',
        'Vehicle',
        'Start time',
        'End time',
        'Day 1',
        'Check-in',
        'Check-out',
        'Service conditions',
        'Service notes',
        'TBD',
        'null',
        'Not provided',
      ]) {
        expect(find.text(value), findsNothing);
      }
    },
  );
  testWidgets(
    'package alternatives preserve every option without selecting a stay',
    (t) async {
      final data = finalizedCanonicalMap()..['days'] = [];
      final stay = v2At(data, ['packageContent', 'accommodations', 0]);
      stay['selection'] = 'alternatives';
      final option = v2At(data, [
        'packageContent',
        'accommodations',
        0,
        'options',
        0,
      ]);
      (stay['options'] as List).add({
        ...option,
        'id': 'alternative-option',
        'order': 2,
        'details': {
          ...option['details'] as Map,
          'hotelName': 'Second Hotel',
          'orSimilar': false,
        },
      });
      await show(t, data: data);
      expect(
        find.text('Accommodation alternatives — one of the following'),
        findsOneWidget,
      );
      expect(find.text('Example Hotel or similar'), findsOneWidget);
      expect(find.text('Second Hotel'), findsOneWidget);
      expect(find.text('or'), findsOneWidget);
      expect(find.text('Day 1'), findsNothing);
      expect(find.text('Confirmed'), findsNothing);
    },
  );
  testWidgets(
    'unnamed package accommodation shows supplied attributes without an invented hotel',
    (t) async {
      final data = finalizedCanonicalMap()..['days'] = [];
      v2Hotel(data)['hotelName'] = null;
      await show(t, data: data);
      expect(find.text('Deluxe'), findsOneWidget);
      expect(find.text('or similar'), findsOneWidget);
      expect(find.text('Hotel TBD'), findsNothing);
    },
  );
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
      testWidgets(
        'canonical content fits $width at ${scale}x and scrolls to package conditions',
        (t) async {
          await show(t, width: width, scale: scale);
          expect(t.takeException(), isNull);
          await t.ensureVisible(find.text('Shared basis'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          final rect = t.getRect(find.text('Shared basis'));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(900));
          if (width >= 1280) {
            expect(
              t.getSize(find.byType(CanonicalService).first).width,
              lessThan(960),
            );
          }
        },
      );
    }
  }
  testWidgets(
    'semantic heading and normal keyboard scrolling remain available',
    (t) async {
      final semantics = t.ensureSemantics();

      await show(t);
      expect(
        t.getSemantics(find.text('Itinerary finalized')),
        matchesSemantics(
          isHeader: true,
          isLiveRegion: true,
          label: 'Itinerary finalized',
          textDirection: TextDirection.ltr,
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final scroll = t.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scroll.position.pixels, greaterThan(0));
      semantics.dispose();
    },
  );
  test(
    'canonical presentation contains no transports, repositories or mutation controls',
    () {
      for (final file in Directory(
        'lib/features/itineraries/presentation/widgets/canonical',
      ).listSync().whereType<File>()) {
        final source = file.readAsStringSync();
        for (final token in [
          'FirebaseFirestore',
          'FirebaseFunctions',
          'httpsCallable',
          'Repository',
          'setDecision',
          'TextFormField',
          'sourceReference.',
          'importResult.',
        ]) {
          expect(source, isNot(contains(token)));
        }
      }
    },
  );
}
