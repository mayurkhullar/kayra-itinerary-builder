import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/clients/domain/kayra_client.dart';
import 'package:kayra_crm_v1/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:kayra_crm_v1/features/trips/domain/kayra_trip.dart';
import 'package:kayra_crm_v1/features/trips/presentation/widgets/create_trip_form.dart';
import 'package:kayra_crm_v1/features/trips/presentation/widgets/my_trips_list.dart';
import 'package:kayra_crm_v1/features/users/domain/kayra_user.dart';
import 'support/fake_auth_service.dart';
import 'support/fake_client_repository.dart';
import 'support/fake_trip_repository.dart';
import 'support/fake_user_profile_repository.dart';

KayraClient _client({
  String id = 'client-1',
  String uid = 'test-user',
  String? company,
  String first = 'Asha',
}) => KayraClient(
  id: id,
  details: ClientDetails(
    firstName: first,
    lastName: 'Rao',
    mobileNumber: '+91 98765 43210',
    email: '$id@example.com',
    company: company,
  ),
  createdByUid: uid,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
KayraTrip _trip({
  String id = 'trip-1',
  String uid = 'test-user',
  DateTime? date,
  String destination = 'Dubai',
}) => KayraTrip.create(
  id: id,
  clientId: 'client-1',
  clientFirstName: 'Asha',
  clientLastName: 'Rao',
  clientCompany: null,
  brief: TripBrief(
    destinations: [destination],
    travelStartDate: date ?? DateTime.utc(2027, 12, 1),
    numberOfNights: 4,
    adults: 2,
    children: 1,
    infants: 0,
    hotelCategory: HotelCategory.fiveStar,
    tripType: TripType.fit,
  ),
  currentUserUid: uid,
  createdAt: DateTime.utc(2026, 9, 25),
);

void main() {
  late FakeClientRepository clients;
  late FakeTripRepository trips;
  setUp(() {
    clients = FakeClientRepository()..clients.add(_client());
    trips = FakeTripRepository(clients: clients);
  });
  void viewport(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> show(
    WidgetTester tester, {
    KayraUserRole role = KayraUserRole.agent,
    String uid = 'test-user',
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DashboardPage(
          user: testProfile(TestUser(uid: uid), role: role),
          onSignOut: () {},
          userProfileRepository: FakeUserProfileRepository(),
          clientRepository: clients,
          tripRepository: trips,
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> open(
    WidgetTester tester, {
    bool emptyAction = false,
    bool settle = true,
  }) async {
    final action = emptyAction
        ? find.text('Create New Itinerary').last
        : find.text('Create New Itinerary').first;
    await tester.ensureVisible(action);
    await tester.tap(action);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  Future<void> destination(WidgetTester tester, String text) async {
    await enter(tester, 'trip-destination', text);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String key, String label) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> valid(
    WidgetTester tester, {
    String type = 'FIT',
    String hotel = '4 Star',
  }) async {
    await tester.tap(find.byKey(const ValueKey('trip-client-search')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('select-client-client-1')),
    );
    await tester.tap(find.byKey(const ValueKey('select-client-client-1')));
    await tester.pumpAndSettle();
    await destination(tester, ' Dubai ');
    final date = find.byKey(const ValueKey('trip-date'));
    await tester.ensureVisible(date);
    await tester.tap(date);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await choose(tester, 'trip-hotel', hotel);
    await choose(tester, 'trip-type', type);
  }

  Future<void> save(WidgetTester tester, {bool settle = true}) async {
    await tester.tap(find.text('Create Itinerary'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  for (final role in KayraUserRole.values) {
    testWidgets('${role.name} uses scoped Trip and Client repository paths', (
      tester,
    ) async {
      viewport(tester, 1440);
      trips.trips.addAll([
        _trip(),
        _trip(id: 'other', uid: 'other', destination: 'Paris'),
      ]);
      clients.clients.add(_client(id: 'other', uid: 'other', first: 'Other'));
      await show(tester, role: role);
      expect(
        trips.ownerQueries,
        role == KayraUserRole.agent ? ['test-user'] : isEmpty,
      );
      expect(trips.adminQueries, role == KayraUserRole.admin ? 1 : 0);
      expect(
        find.text(
          _trip(id: 'other', uid: 'other', destination: 'Paris').tripName,
        ),
        role == KayraUserRole.admin ? findsOneWidget : findsNothing,
      );
      await open(tester);
      expect(
        clients.ownerQueries,
        role == KayraUserRole.agent ? ['test-user'] : isEmpty,
      );
      expect(clients.adminQueries, role == KayraUserRole.admin ? 1 : 0);
      await tester.tap(find.byKey(const ValueKey('trip-client-search')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('select-client-other')),
        role == KayraUserRole.admin ? findsOneWidget : findsNothing,
      );
    });
  }
  testWidgets('empty state and both entry points share one creation form', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('No trips yet'), findsOneWidget);
    await open(tester);
    expect(find.byType(CreateTripForm), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await open(tester, emptyAction: true);
    expect(find.byType(CreateTripForm), findsOneWidget);
    expect(trips.creations, isEmpty);
  });
  testWidgets('loading, safe Trip error and retry', (tester) async {
    final load = Completer<void>();
    trips.beforeLoad = () => load.future;
    await show(tester, settle: false);
    expect(find.text('Loading trips…'), findsOneWidget);
    load.completeError(StateError('private Firebase details'));
    await tester.pumpAndSettle();
    expect(find.text('Trip data couldn’t be loaded.'), findsOneWidget);
    expect(find.textContaining('private Firebase'), findsNothing);
    trips.beforeLoad = null;
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No trips yet'), findsOneWidget);
  });
  testWidgets('Client loading, safe failure and retry', (tester) async {
    await show(tester);
    final load = Completer<void>();
    clients.beforeLoad = () => load.future;
    await open(tester, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    load.completeError(StateError('private'));
    await tester.pumpAndSettle();
    expect(find.text('Client data couldn’t be loaded.'), findsOneWidget);
    clients.beforeLoad = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trip-client-search')));
    await tester.pumpAndSettle();
    expect(find.text('Asha Rao'), findsOneWidget);
  });
  testWidgets('no Clients blocks creation and links to existing Clients page', (
    tester,
  ) async {
    clients.clients.clear();
    await show(tester);
    await open(tester);
    expect(find.text('No clients available'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create Itinerary'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Go to Clients'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateTripForm), findsNothing);
    expect(find.text('No clients yet'), findsOneWidget);
  });
  for (final query in ['asha rao', '98765', 'client-1@example', 'Horizon']) {
    testWidgets('Client selector searches $query', (tester) async {
      clients.clients[0] = _client(company: 'Horizon');
      clients.clients.add(_client(id: 'second', first: 'Second'));
      await show(tester);
      await open(tester);
      await enter(tester, 'trip-client-search', query);
      expect(
        find.byKey(const ValueKey('select-client-client-1')),
        findsOneWidget,
      );
      if (query != '98765') {
        expect(
          find.byKey(const ValueKey('select-client-second')),
          findsNothing,
        );
      }
      await enter(tester, 'trip-client-search', 'no match');
      expect(find.text('No matching clients'), findsOneWidget);
    });
  }
  testWidgets('Client results appear only while selector is active', (
    tester,
  ) async {
    await show(tester);
    await open(tester);
    final search = find.byKey(const ValueKey('trip-client-search'));
    final result = find.byKey(const ValueKey('select-client-client-1'));
    expect(result, findsNothing);
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(result, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trip-destination')));
    await tester.pumpAndSettle();
    expect(result, findsNothing);
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(result, findsOneWidget);
  });

  testWidgets('Client results and Change support keyboard navigation', (
    tester,
  ) async {
    await show(tester);
    await open(tester);
    final search = find.byKey(const ValueKey('trip-client-search'));
    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('select-client-client-1')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trip-selected-client')), findsOneWidget);
    expect(search, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(search, findsOneWidget);
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    expect(
      find.byKey(const ValueKey('select-client-client-1')),
      findsOneWidget,
    );
  });

  for (final width in <double>[390, 1440]) {
    testWidgets(
      'compact selected Client fits $width and Change preserves brief',
      (tester) async {
        viewport(tester, width);
        clients.clients.add(_client(id: 'second', first: 'Another Client'));
        await show(tester);
        await open(tester);
        await valid(tester, hotel: 'Luxury', type: 'Business');
        await enter(tester, 'trip-Number of Nights', '5');
        await enter(tester, 'trip-Adults', '2');
        await enter(tester, 'trip-Children', '1');
        await destination(tester, 'Abu Dhabi');
        final selected = find.byKey(const ValueKey('trip-selected-client'));
        await tester.ensureVisible(selected);
        await tester.pumpAndSettle();
        final rect = tester.getRect(selected);
        expect(rect.left, greaterThanOrEqualTo(20));
        expect(rect.right, lessThanOrEqualTo(width - 20));
        expect(rect.height, lessThanOrEqualTo(80));
        expect(
          tester.getSize(find.widgetWithText(TextButton, 'Change')).height,
          greaterThanOrEqualTo(48),
        );
        expect(find.byKey(const ValueKey('trip-client-search')), findsNothing);
        expect(
          find.byKey(const ValueKey('select-client-second')),
          findsNothing,
        );
        final date = tester
            .widget<TextField>(find.byKey(const ValueKey('trip-date')))
            .controller!
            .text;
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('trip-client-search')),
              )
              .focusNode!
              .hasFocus,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('select-client-second')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('trip-date')))
              .controller!
              .text,
          date,
        );
        await save(tester);
        final creation = trips.creations.single;
        expect(creation.clientId, 'second');
        expect(creation.brief.destinations, ['Dubai', 'Abu Dhabi']);
        expect(creation.brief.numberOfNights, 5);
        expect(creation.brief.adults, 2);
        expect(creation.brief.children, 1);
        expect(creation.brief.infants, 0);
        expect(creation.brief.hotelCategory, HotelCategory.luxury);
        expect(creation.brief.tripType, TripType.business);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('required fields show inline errors only after submit', (
    tester,
  ) async {
    await show(tester);
    await open(tester);
    expect(find.text('Select a Client.'), findsNothing);
    await save(tester);
    for (final message in [
      'Select a Client.',
      'At least one destination is required.',
      'Select a travel date.',
      'Select a hotel category.',
      'Select a trip type.',
    ]) {
      expect(find.text(message), findsOneWidget);
    }
    expect(trips.creations, isEmpty);
    expect(find.byType(CreateTripForm), findsOneWidget);
  });
  for (final entry in {
    'Number of Nights': '0',
    'Adults': '0',
    'Children': '-1',
    'Infants': '-1',
  }.entries) {
    testWidgets('rejects invalid ${entry.key} inline without writes', (
      tester,
    ) async {
      await show(tester);
      await open(tester);
      await valid(tester);
      await enter(tester, 'trip-${entry.key}', entry.value);
      await save(tester);
      expect(
        find.textContaining('${entry.key} must be at least'),
        findsOneWidget,
      );
      expect(trips.creations, isEmpty);
    });
  }
  testWidgets('rejects fractional and blank counts', (tester) async {
    await show(tester);
    await open(tester);
    await valid(tester);
    for (final input in ['1.5', '']) {
      await enter(tester, 'trip-Adults', input);
      await save(tester);
      expect(find.text('Enter a whole number.'), findsOneWidget);
      expect(trips.creations, isEmpty);
    }
  });
  for (final type in ['Corporate', 'Groups']) {
    testWidgets('$type without Client company is rejected by shared rule', (
      tester,
    ) async {
      await show(tester);
      await open(tester);
      await valid(tester, type: type);
      await save(tester);
      expect(
        find.text('Add a company to this Client before creating a $type trip.'),
        findsOneWidget,
      );
      expect(trips.creations, isEmpty);
    });
  }
  for (final type in TripType.values) {
    testWidgets(
      '${type.label} creates Draft with typed values and refreshes My Trips',
      (tester) async {
        if (type == TripType.corporate || type == TripType.groups) {
          clients.clients[0] = _client(company: 'Horizon');
        }
        await show(tester);
        await open(tester);
        await valid(
          tester,
          type: type.label,
          hotel: HotelCategory.values[type.index].label,
        );
        await destination(tester, 'Abu Dhabi');
        final preview = tester
            .widget<Text>(find.byKey(const ValueKey('trip-name-preview')))
            .data;
        await save(tester);
        expect(find.byType(CreateTripForm), findsNothing);
        expect(trips.creations, hasLength(1));
        final created = trips.trips.single;
        expect(created.destinations, ['Dubai', 'Abu Dhabi']);
        expect(created.status, TripStatus.draft);
        expect(created.ownerUid, 'test-user');
        expect(created.createdByUid, 'test-user');
        expect(created.hotelCategory, HotelCategory.values[type.index]);
        expect(created.tripType, type);
        expect(preview, created.brief.tripNameFor('Asha', 'Rao'));
        expect(find.text(created.tripName), findsOneWidget);
        expect(trips.ownerQueries, ['test-user', 'test-user']);
      },
    );
  }
  testWidgets('destination chips remove entries and Enter preserves order', (
    tester,
  ) async {
    await show(tester);
    await open(tester);
    await valid(tester);
    await destination(tester, 'Remove me');
    final chip = tester.widget<InputChip>(
      find.widgetWithText(InputChip, 'Remove me'),
    );
    chip.onDeleted!();
    await tester.pumpAndSettle();
    await enter(tester, 'trip-destination', 'Paris');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await save(tester);
    expect(trips.trips.single.destinations, ['Dubai', 'Paris']);
  });
  testWidgets('create failure retains entered data and allows safe retry', (
    tester,
  ) async {
    trips.beforeSave = () async => throw StateError('private Firebase details');
    await show(tester);
    await open(tester);
    await valid(tester);
    await save(tester);
    expect(
      find.text('Itinerary couldn’t be created. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private Firebase'), findsNothing);
    expect(find.widgetWithText(InputChip, 'Dubai'), findsOneWidget);
    trips.beforeSave = null;
    await save(tester);
    expect(find.byType(CreateTripForm), findsNothing);
    expect(trips.trips, hasLength(1));
  });
  testWidgets(
    'duplicate submissions and dismissal are blocked during creation',
    (tester) async {
      final pending = Completer<void>();
      trips.beforeSave = () => pending.future;
      await show(tester);
      await open(tester);
      await valid(tester);
      final submit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create Itinerary'),
          )
          .onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(trips.creations, hasLength(1));
      final state = tester.state(find.byType(CreateTripForm));
      await Navigator.of(state.context).maybePop();
      await tester.pump();
      expect(find.byType(CreateTripForm), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(trips.creations, hasLength(1));
      expect(find.byType(CreateTripForm), findsNothing);
    },
  );
  testWidgets(
    'reload failure after acknowledged create does not invite duplicate writes',
    (tester) async {
      await show(tester);
      await open(tester);
      await valid(tester);
      trips.beforeLoad = () async => throw StateError('read failed');
      await save(tester);
      expect(find.byType(CreateTripForm), findsNothing);
      expect(find.text('Trip data couldn’t be loaded.'), findsOneWidget);
      expect(trips.creations, hasLength(1));
    },
  );
  testWidgets('session change closes form and discards prior-user Trips', (
    tester,
  ) async {
    trips.trips.add(_trip());
    await show(tester);
    await open(tester);
    await show(tester, uid: 'other');
    expect(find.byType(CreateTripForm), findsNothing);
    expect(find.byKey(const ValueKey('trip-trip-1')), findsNothing);
    expect(trips.ownerQueries, ['test-user', 'other']);
  });
  testWidgets('late Admin results cannot enter an Agent session', (
    tester,
  ) async {
    final pending = Completer<void>();
    trips.beforeLoad = () => pending.future;
    trips.trips.add(_trip(uid: 'other'));
    await show(tester, role: KayraUserRole.admin, settle: false);
    trips.beforeLoad = null;
    await show(tester);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trip-trip-1')), findsNothing);
    expect(find.text('No trips yet'), findsOneWidget);
  });
  testWidgets('sorting puts upcoming first then nearest dates', (tester) async {
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    trips.trips.addAll([
      _trip(id: 'past', date: today.subtract(const Duration(days: 1))),
      _trip(id: 'later', date: today.add(const Duration(days: 10))),
      _trip(id: 'soon', date: today),
    ]);
    await show(tester);
    final list = tester.widget<MyTripsList>(find.byType(MyTripsList));
    expect(list.trips!.map((trip) => trip.id), ['soon', 'later', 'past']);
  });
  for (final width in <double>[375, 390, 430, 768, 1440, 1920]) {
    testWidgets('form and real Trip list fit $width px', (tester) async {
      viewport(tester, width);
      trips.trips.add(
        _trip(destination: 'Abu Dhabi and surrounding cultural destinations'),
      );
      await show(tester);
      expect(tester.takeException(), isNull);
      await open(tester);
      await valid(tester);
      expect(tester.takeException(), isNull);
      final date = tester.getRect(find.byKey(const ValueKey('trip-date')));
      final nights = tester.getRect(
        find.byKey(const ValueKey('trip-Number of Nights')),
      );
      if (width >= 768) {
        expect(date.top, nights.top);
      } else {
        expect(date.bottom, lessThan(nights.top));
      }
      await save(tester);
      expect(tester.takeException(), isNull);
      expect(trips.trips, hasLength(2));
    });
  }
  testWidgets('name preview appears before category and type are selected', (
    tester,
  ) async {
    await show(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('trip-client-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-client-client-1')));
    await tester.pumpAndSettle();
    await destination(tester, 'Dubai');
    await tester.ensureVisible(find.byKey(const ValueKey('trip-date')));
    await tester.tap(find.byKey(const ValueKey('trip-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final preview = tester
        .widget<Text>(find.byKey(const ValueKey('trip-name-preview')))
        .data;
    expect(
      preview,
      TripBrief.generateName(
        firstName: 'Asha',
        lastName: 'Rao',
        destinations: ['Dubai'],
        travelStartDate: DateTime.now(),
      ),
    );
    expect(trips.creations, isEmpty);
  });

  testWidgets(
    'session change dismisses nested date picker and blocks stale callback',
    (tester) async {
      await show(tester);
      await open(tester);
      final form = tester.widget<CreateTripForm>(find.byType(CreateTripForm));
      await tester.ensureVisible(find.byKey(const ValueKey('trip-date')));
      await tester.tap(find.byKey(const ValueKey('trip-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await show(tester, uid: 'other');
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(CreateTripForm), findsNothing);
      await expectLater(
        form.onCreate(_client(), _trip().brief),
        throwsStateError,
      );
      expect(trips.creations, isEmpty);
    },
  );

  testWidgets('large text and long destinations fit mobile form', (
    tester,
  ) async {
    viewport(tester, 390);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    trips.trips.add(
      _trip(destination: 'Abu Dhabi and surrounding cultural destinations'),
    );
    await show(tester);
    expect(tester.takeException(), isNull);
    await open(tester);
    await destination(
      tester,
      'A very long destination name with several regional stops',
    );
    await save(tester);
    expect(tester.takeException(), isNull);
    expect(trips.creations, isEmpty);
  });

  testWidgets('mobile form remains scrollable above keyboard', (tester) async {
    viewport(tester, 390);
    await show(tester);
    await open(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await valid(tester);
    await save(tester);
    expect(tester.takeException(), isNull);
    expect(trips.trips, hasLength(1));
  });
}
