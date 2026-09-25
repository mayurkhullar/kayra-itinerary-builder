import 'support/fake_trip_repository.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/app/app.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/clients/domain/kayra_client.dart';
import 'package:kayra_crm_v1/features/clients/presentation/pages/clients_page.dart';
import 'package:kayra_crm_v1/features/clients/presentation/widgets/client_directory.dart';
import 'package:kayra_crm_v1/features/clients/presentation/widgets/client_form.dart';
import 'package:kayra_crm_v1/features/users/domain/kayra_user.dart';
import 'package:kayra_crm_v1/shared/widgets/kayra_app_header.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_client_repository.dart';
import 'support/fake_user_profile_repository.dart';

final _agent = testProfile(TestUser());
final _admin = testProfile(TestUser(), role: KayraUserRole.admin);
KayraClient _client({
  String id = 'one',
  String? owner,
  String firstName = 'Priya',
}) => KayraClient(
  id: id,
  details: ClientDetails(
    firstName: firstName,
    lastName: 'Shah',
    mobileNumber: '+91 09876-543210',
    email: 'priya@example.com',
    city: 'Mumbai',
    company: 'Atlas Travel',
  ),
  createdByUid: owner ?? _agent.uid,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 9, 25),
);

void main() {
  void viewport(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> showPage(
    WidgetTester tester,
    FakeClientRepository repository, {
    KayraUser? user,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ClientsPage(
            currentUser: user ?? _agent,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openCreate(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'New Client'));
    await tester.pumpAndSettle();
    expect(find.byType(ClientForm), findsOneWidget);
  }

  Future<void> enter(WidgetTester tester, String field, String value) async {
    final target = find.byKey(ValueKey('client-$field'));
    await tester.ensureVisible(target);
    await tester.enterText(target, value);
    await tester.pump();
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await enter(tester, 'First Name', '  Asha ');
    await enter(tester, 'Last Name', ' Rao  ');
    await enter(tester, 'Mobile Number', ' +44 (0)20 1234 5678 ');
  }

  for (final user in [_agent, _admin]) {
    for (final width in <double>[390, 1440]) {
      testWidgets(
        '${user.role.name} Clients navigation and authorized loading at $width',
        (tester) async {
          viewport(tester, width);
          final repository = FakeClientRepository()
            ..clients.addAll([
              _client(),
              _client(id: 'other', owner: 'another-agent', firstName: 'Other'),
            ]);
          final auth = FakeAuthService(user: TestUser());
          addTearDown(auth.dispose);
          final profiles = FakeUserProfileRepository()
            ..onBootstrap = (_) async => user;
          await tester.pumpWidget(
            KayraApp(
              tripRepository: FakeTripRepository(),
              authService: auth,
              userProfileRepository: profiles,
              clientRepository: repository,
            ),
          );
          await tester.pumpAndSettle();
          if (width < 1280) {
            await tester.tap(find.byTooltip('Menu'));
            await tester.pumpAndSettle();
            expect(
              find.text('Admin'),
              user.isActiveAdmin ? findsOneWidget : findsNothing,
            );
            await tester.tap(find.text('Clients'));
          } else {
            final header = find.byType(KayraAppHeader);
            final labels = find
                .descendant(of: header, matching: find.byType(TextButton))
                .evaluate()
                .map(
                  (element) =>
                      ((element.widget as TextButton).child as Text).data,
                )
                .toList();
            expect(labels, [
              'My Trips',
              'Clients',
              'Suppliers',
              'Reusable Itineraries',
              if (user.isActiveAdmin) 'Admin',
            ]);
            await tester.tap(find.widgetWithText(TextButton, 'Clients'));
          }
          await tester.pumpAndSettle();
          expect(find.byType(ClientsPage), findsOneWidget);
          expect(
            repository.ownerQueries,
            user.isActiveAdmin ? isEmpty : [_agent.uid],
          );
          expect(repository.adminQueries, user.isActiveAdmin ? 1 : 0);
          expect(
            find.text('Other Shah'),
            user.isActiveAdmin ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final width in <double>[375, 390, 430, 768, 1024, 1440, 1920]) {
    testWidgets('directory and create form fit $width px', (tester) async {
      viewport(tester, width);
      final repository = FakeClientRepository()..clients.add(_client());
      await showPage(tester, repository);
      await tester.pumpAndSettle();
      expect(
        find.byType(DataTable),
        width >= 1440 ? findsOneWidget : findsNothing,
      );
      expect(find.text('Priya Shah'), findsOneWidget);
      expect(find.text('+91 09876-543210'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await openCreate(tester);
      await enter(tester, 'Company', '');
      expect(find.byType(TextFormField), findsNWidgets(6));
      expect(find.text('createdByUid'), findsNothing);
      for (final field in find.byType(TextFormField).evaluate()) {
        final rect = tester.getRect(find.byWidget(field.widget));
        expect(rect.left, greaterThanOrEqualTo(20));
        expect(rect.right, lessThanOrEqualTo(width - 20));
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.creations, isEmpty);
    });
  }

  testWidgets(
    'required validation and optional empty fields use the domain rules',
    (tester) async {
      viewport(tester, 390);
      final repository = FakeClientRepository();
      await showPage(tester, repository);
      expect(find.text('No clients yet'), findsOneWidget);
      expect(
        find.text('Create your first client to start building journeys.'),
        findsOneWidget,
      );
      await openCreate(tester);
      await tester.tap(find.text('Create Client'));
      await tester.pumpAndSettle();
      for (final field in ['First Name', 'Last Name', 'Mobile Number']) {
        expect(find.text('$field is required.'), findsOneWidget);
      }
      expect(repository.creations, isEmpty);
      await fillRequired(tester);
      await tester.tap(find.text('Create Client'));
      await tester.pumpAndSettle();
      expect(find.byType(ClientForm), findsNothing);
      expect(find.text('Asha Rao'), findsOneWidget);
      final created = repository.creations.single;
      expect(created.uid, _agent.uid);
      expect(created.details.mobileNumber, '+44 (0)20 1234 5678');
      expect(created.details.company, isNull);
      expect(created.details.email, isNull);
      expect(created.details.city, isNull);
      expect(repository.ownerQueries, [_agent.uid, _agent.uid]);
    },
  );

  testWidgets(
    'create normalizes optional values and clears an existing search',
    (tester) async {
      final repository = FakeClientRepository()..clients.add(_client());
      await showPage(tester, repository);
      await tester.enterText(find.byType(TextField), 'no match');
      await openCreate(tester);
      await fillRequired(tester);
      await enter(tester, 'Email', ' ASHA@EXAMPLE.COM ');
      await enter(tester, 'City', ' Delhi ');
      await enter(tester, 'Company', ' Travel Co ');
      await tester.tap(find.text('Create Client'));
      await tester.pumpAndSettle();
      expect(repository.creations.single.details.email, 'asha@example.com');
      expect(repository.creations.single.details.city, 'Delhi');
      expect(repository.creations.single.details.company, 'Travel Co');
      expect(find.text('Asha Rao'), findsOneWidget);
    },
  );

  for (final editing in [false, true]) {
    testWidgets(
      '${editing ? 'edit' : 'create'} failure shows safe error and permits retry',
      (tester) async {
        final repository = FakeClientRepository()
          ..clients.add(_client())
          ..beforeSave = () async =>
              throw StateError('private Firebase details');
        await showPage(tester, repository);
        if (editing) {
          await tester.tap(find.text('Priya Shah'));
          await tester.pumpAndSettle();
        } else {
          await openCreate(tester);
          await fillRequired(tester);
        }
        final label = editing ? 'Save Changes' : 'Create Client';
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(
          find.text(
            editing
                ? 'Client couldn’t be updated. Please try again.'
                : 'Client couldn’t be created. Please try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('private Firebase'), findsNothing);
        expect(repository.ownerQueries, [_agent.uid]);
        repository.beforeSave = null;
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(ClientForm), findsNothing);
        expect(repository.ownerQueries, [_agent.uid, _agent.uid]);
      },
    );
  }

  testWidgets(
    'Admin edits another Agent client without transferring ownership',
    (tester) async {
      viewport(tester, 1440);
      final original = _client(owner: 'other-agent');
      final repository = FakeClientRepository()..clients.add(original);
      await showPage(tester, repository, user: _admin);
      await tester.tap(find.text('Priya Shah'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Client'), findsOneWidget);
      for (final entry in {
        'First Name': 'Priya',
        'Last Name': 'Shah',
        'Mobile Number': '+91 09876-543210',
        'Email': 'priya@example.com',
        'City': 'Mumbai',
        'Company': 'Atlas Travel',
      }.entries) {
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(ValueKey('client-${entry.key}')),
              )
              .controller!
              .text,
          entry.value,
        );
      }
      expect(find.byType(TextFormField), findsNWidgets(6));
      expect(find.text('other-agent'), findsNothing);
      await enter(tester, 'First Name', 'Revised');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(find.text('Revised Shah'), findsOneWidget);
      expect(repository.updates.single.id, original.id);
      expect(repository.clients.single.createdByUid, 'other-agent');
      expect(repository.clients.single.createdAt, original.createdAt);
      expect(repository.adminQueries, 2);
      expect(repository.ownerQueries, isEmpty);
    },
  );

  testWidgets(
    'save prevents duplicate submissions and dismissal while pending',
    (tester) async {
      final pending = Completer<void>();
      final repository = FakeClientRepository()
        ..beforeSave = () => pending.future;
      await showPage(tester, repository);
      await openCreate(tester);
      await fillRequired(tester);
      final save = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create Client'),
          )
          .onPressed!;
      save();
      save();
      await tester.pump();
      expect(repository.creations, hasLength(1));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await Navigator.of(tester.element(find.byType(ClientForm))).maybePop();
      await tester.pump();
      expect(find.byType(ClientForm), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ClientForm), findsNothing);
    },
  );

  testWidgets('search matches name, mobile, email and company locally', (
    tester,
  ) async {
    final repository = FakeClientRepository()..clients.add(_client());
    await showPage(tester, repository);
    for (final query in [
      'pRiYa',
      'SHAH',
      'priya shah',
      '09876',
      'PRIYA@EXAMPLE',
      'ATLAS',
    ]) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
      expect(find.text('Priya Shah'), findsOneWidget);
    }
    await tester.enterText(find.byType(TextField), 'unmatched');
    await tester.pump();
    expect(find.text('No matching clients'), findsOneWidget);
    expect(repository.ownerQueries, [_agent.uid]);
    expect(repository.adminQueries, 0);
  });

  testWidgets('loading and safe load error support retry', (tester) async {
    final pending = Completer<void>();
    final repository = FakeClientRepository()
      ..beforeLoad = () => pending.future;
    await showPage(tester, repository);
    expect(find.text('Loading clients…'), findsOneWidget);
    pending.completeError(StateError('private Firestore error'));
    await tester.pumpAndSettle();
    expect(find.text('Client data couldn’t be loaded.'), findsOneWidget);
    expect(find.textContaining('private Firestore'), findsNothing);
    repository.beforeLoad = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No clients yet'), findsOneWidget);
  });

  testWidgets('mobile form remains scrollable above the keyboard', (
    tester,
  ) async {
    viewport(tester, 390);
    final repository = FakeClientRepository();
    await showPage(tester, repository);
    await openCreate(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await enter(tester, 'Company', 'Company');
    expect(
      tester.getRect(find.byKey(const ValueKey('client-Company'))).bottom,
      lessThanOrEqualTo(580),
    );
    expect(
      tester.getRect(find.text('Create Client')).bottom,
      lessThanOrEqualTo(580),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('session changes discard pending data and close an open form', (
    tester,
  ) async {
    final repository = FakeClientRepository()..clients.add(_client());
    await showPage(tester, repository);
    await openCreate(tester);
    final inactive = testProfile(TestUser(), status: KayraUserStatus.inactive);
    await showPage(tester, repository, user: inactive);
    await tester.pumpAndSettle();
    expect(find.byType(ClientForm), findsNothing);
    expect(find.text('Client access is unavailable.'), findsOneWidget);
    expect(repository.creations, isEmpty);
    expect(repository.ownerQueries, [_agent.uid]);
  });

  testWidgets('late Admin list is discarded after switching to Agent scope', (
    tester,
  ) async {
    final pending = Completer<void>();
    final repository = FakeClientRepository()
      ..clients.add(_client(owner: 'other-agent'));
    repository.beforeLoad = () => pending.future;
    await showPage(tester, repository, user: _admin);
    repository.beforeLoad = null;
    await showPage(tester, repository, user: _agent);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Priya Shah'), findsNothing);
    expect(find.text('No clients yet'), findsOneWidget);
  });

  for (final width in <double>[390, 1440]) {
    testWidgets('long client text and enlarged text fit $width px', (
      tester,
    ) async {
      viewport(tester, width);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = FakeClientRepository()
        ..clients.add(
          _client(firstName: 'Alexandertheodore Verylongname Consultant'),
        );
      await showPage(tester, repository);
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsNothing);
      expect(tester.takeException(), isNull);
      await openCreate(tester);
      await enter(tester, 'Company', 'A long company name');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'disposing Client page removes its form and prevents stale saves',
    (tester) async {
      final repository = FakeClientRepository();
      await showPage(tester, repository);
      await openCreate(tester);
      final save = tester.widget<ClientForm>(find.byType(ClientForm)).onSave;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Text('Signed out')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ClientForm), findsNothing);
      await expectLater(
        save(
          ClientDetails(firstName: 'A', lastName: 'B', mobileNumber: '1234567'),
        ),
        throwsStateError,
      );
      expect(repository.creations, isEmpty);
    },
  );

  for (final editing in [false, true]) {
    for (final width in <double>[390, 1440]) {
      testWidgets(
        '${editing ? 'edit' : 'create'} shares domain validation at $width',
        (tester) async {
          viewport(tester, width);
          final repository = FakeClientRepository()..clients.add(_client());
          await showPage(tester, repository);
          if (editing) {
            await tester.tap(find.text('Priya Shah'));
            await tester.pumpAndSettle();
          } else {
            await openCreate(tester);
          }
          expect(find.text('Enter a valid mobile number.'), findsNothing);
          expect(find.text('Enter a valid email address.'), findsNothing);
          expect(find.text('First Name is required.'), findsNothing);
          for (final label in ['First Name', 'Last Name', 'Mobile Number']) {
            expect(
              tester
                  .widget<TextField>(
                    find.descendant(
                      of: find.byKey(ValueKey('client-$label')),
                      matching: find.byType(TextField),
                    ),
                  )
                  .decoration!
                  .labelText,
              '$label *',
            );
          }
          await fillRequired(tester);
          await enter(tester, 'Mobile Number', 'abc12345');
          await enter(tester, 'Email', 'abc@example');
          final action = editing ? 'Save Changes' : 'Create Client';
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
          expect(find.text('Enter a valid mobile number.'), findsOneWidget);
          expect(find.text('Enter a valid email address.'), findsOneWidget);
          expect(repository.creations, isEmpty);
          expect(repository.updates, isEmpty);
          expect(find.byType(ClientForm), findsOneWidget);
          expect(tester.takeException(), isNull);
          await enter(tester, 'Mobile Number', '(415) 555-2671');
          await enter(tester, 'Email', ' TRAVEL+CLIENT@EXAMPLE.CO.UK ');
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
          expect(find.byType(ClientForm), findsNothing);
          final details = editing
              ? repository.updates.single.details
              : repository.creations.single.details;
          expect(details.email, 'travel+client@example.co.uk');
          expect(details.mobileNumber, '(415) 555-2671');
        },
      );
    }
  }

  for (final width in <double>[390, 1440]) {
    testWidgets('responsive form field alignment at $width', (tester) async {
      viewport(tester, width);
      await showPage(tester, FakeClientRepository());
      await openCreate(tester);
      Rect field(String label) =>
          tester.getRect(find.byKey(ValueKey('client-$label')));
      final first = field('First Name');
      final last = field('Last Name');
      final city = field('City');
      final company = field('Company');
      if (width == 1440) {
        expect(first.top, last.top);
        expect(city.top, company.top);
        expect(first.right, lessThan(last.left));
        expect(field('Mobile Number').width, greaterThan(first.width));
        expect(
          tester
              .getSize(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Material && widget.type == MaterialType.card,
                  ),
                ),
              )
              .width,
          inInclusiveRange(560, 640),
        );
      } else {
        expect(first.bottom, lessThan(last.top));
        expect(city.bottom, lessThan(company.top));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'editing one field does not invalidate untouched required fields',
    (tester) async {
      await showPage(tester, FakeClientRepository());
      await openCreate(tester);
      await enter(tester, 'First Name', 'Asha');
      expect(find.text('Last Name is required.'), findsNothing);
      expect(find.text('Mobile Number is required.'), findsNothing);
    },
  );

  testWidgets('desktop rows expose restrained hover color and pointer cursor', (
    tester,
  ) async {
    viewport(tester, 1440);
    await showPage(tester, FakeClientRepository()..clients.add(_client()));
    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(
      table.rows.single.mouseCursor!.resolve({WidgetState.hovered}),
      SystemMouseCursors.click,
    );
    expect(table.dataRowColor!.resolve({WidgetState.hovered}), isNotNull);
    expect(table.dataRowColor!.resolve({}), isNull);
    await tester.tap(find.text('Priya Shah'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Client'), findsOneWidget);
  });

  test('updated date formatting uses local time and handles noon', () {
    expect(
      formatClientUpdated(DateTime(2026, 9, 25, 12, 5)),
      '25 Sep 2026, 12:05 PM',
    );
  });
}
