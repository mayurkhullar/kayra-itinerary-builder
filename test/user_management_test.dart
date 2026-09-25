import 'support/fake_trip_repository.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/app/app.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/admin/presentation/pages/user_management_page.dart';
import 'package:kayra_crm_v1/features/admin/presentation/widgets/user_directory.dart';
import 'package:kayra_crm_v1/features/users/domain/kayra_user.dart';
import 'package:kayra_crm_v1/shared/widgets/kayra_app_header.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_user_profile_repository.dart';

final _admin = testProfile(TestUser(), role: KayraUserRole.admin);
final _agent = testProfile(
  TestUser(
    uid: 'agent',
    email: 'priya@kholidaymaps.com',
    displayName: 'Priya Shah',
  ),
);
final _inactive = testProfile(
  TestUser(
    uid: 'inactive',
    email: 'inactive@kholidaymaps.com',
    displayName: 'Inactive Colleague',
  ),
  status: KayraUserStatus.inactive,
);

void main() {
  void viewport(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> showShell(
    WidgetTester tester,
    FakeUserProfileRepository repository, {
    KayraUser? user,
  }) async {
    final profile = user ?? _admin;
    final auth = FakeAuthService(
      user: TestUser(uid: profile.uid, email: profile.email),
    );
    repository.onBootstrap = (_) async => profile;
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      KayraApp(
        tripRepository: FakeTripRepository(),
        authService: auth,
        userProfileRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAdmin(WidgetTester tester, double width) async {
    if (width < 1280) {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin').last);
    } else {
      await tester.tap(find.widgetWithText(TextButton, 'Admin'));
    }
    await tester.pump();
  }

  Future<void> showPage(
    WidgetTester tester,
    FakeUserProfileRepository repository,
    KayraUser user,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: UserManagementPage(currentUser: user, repository: repository),
        ),
      ),
    );
    await tester.pump();
  }

  for (final width in <double>[375, 390, 430, 768, 1024, 1280, 1440, 1920]) {
    testWidgets('Admin navigation and directory fit ${width.toInt()}px', (
      tester,
    ) async {
      viewport(tester, width);
      final repository = FakeUserProfileRepository()
        ..onListUsers = () async => [_admin, _agent, _inactive];
      await showShell(tester, repository);
      expect(repository.listUsersCalls, 0);
      await openAdmin(tester, width);
      await tester.pumpAndSettle();
      expect(find.text('User Management'), findsOneWidget);
      expect(find.text('Priya Shah'), findsOneWidget);
      expect(find.text('priya@kholidaymaps.com'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Active'), findsNWidgets(2));
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Agent'), findsNWidgets(2));
      expect(repository.listUsersCalls, 1);
      expect(find.byType(Table), width >= 1280 ? findsOneWidget : findsNothing);
      expect(find.byType(KayraAppHeader), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Deactivate'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Inactive Colleague'));
      await tester.pumpAndSettle();
      expect(find.text('Inactive Colleague').hitTestable(), findsOneWidget);
      for (final element in find.byType(Text).evaluate()) {
        final rect = tester.getRect(
          find.byElementPredicate((candidate) => identical(candidate, element)),
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in <double>[390, 1440]) {
    testWidgets('Agent has no Admin navigation at ${width.toInt()}px', (
      tester,
    ) async {
      viewport(tester, width);
      final repository = FakeUserProfileRepository();
      await showShell(tester, repository, user: _agent);
      if (width < 1280) {
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Admin'), findsNothing);
      expect(repository.listUsersCalls, 0);
    });
  }

  testWidgets(
    'Admin can return to My Trips and sign out from the shared shell',
    (tester) async {
      viewport(tester, 1440);
      final repository = FakeUserProfileRepository();
      await showShell(tester, repository);
      await openAdmin(tester, 1440);
      await tester.pumpAndSettle();
      expect(find.text('No users found'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'My Trips'));
      await tester.pumpAndSettle();
      expect(find.text('Good to see you, Maya.'), findsOneWidget);
      await openAdmin(tester, 1440);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Account menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byType(UserManagementPage), findsNothing);
    },
  );

  for (final user in [
    _agent,
    testProfile(
      TestUser(),
      role: KayraUserRole.admin,
      status: KayraUserStatus.inactive,
    ),
  ]) {
    testWidgets(
      'Page denies ${user.role.name}/${user.status.name} without fetching users',
      (tester) async {
        final repository = FakeUserProfileRepository()
          ..onListUsers = () async => [_admin];
        await showPage(tester, repository, user);
        expect(repository.listUsersCalls, 0);
        expect(find.textContaining('Access denied.'), findsOneWidget);
        expect(find.byType(UserDirectory), findsNothing);
        expect(find.text('Maya Kapoor'), findsNothing);
      },
    );
  }

  testWidgets('Loading stays inside the authenticated shell', (tester) async {
    viewport(tester, 1440);
    final pending = Completer<List<KayraUser>>();
    final repository = FakeUserProfileRepository()
      ..onListUsers = () => pending.future;
    await showShell(tester, repository);
    await openAdmin(tester, 1440);
    expect(find.text('Loading users…'), findsOneWidget);
    expect(find.byType(KayraAppHeader), findsOneWidget);
    expect(tester.getSize(find.byType(CircularProgressIndicator)).width, 24);
    pending.complete([_agent]);
    await tester.pumpAndSettle();
    expect(find.text('Priya Shah'), findsOneWidget);
  });

  testWidgets('Error hides SDK details and retries only on request', (
    tester,
  ) async {
    final repository = FakeUserProfileRepository()
      ..onListUsers = () async =>
          throw StateError('private Firebase diagnostic');
    await showPage(tester, repository, _admin);
    await tester.pumpAndSettle();
    expect(find.text('User data couldn’t be loaded.'), findsOneWidget);
    expect(find.textContaining('private Firebase'), findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(repository.listUsersCalls, 1);
    repository.onListUsers = () async => [_agent];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repository.listUsersCalls, 2);
    expect(find.text('Priya Shah'), findsOneWidget);
  });

  testWidgets('Losing Admin access discards pending data', (tester) async {
    final pending = Completer<List<KayraUser>>();
    final repository = FakeUserProfileRepository()
      ..onListUsers = () => pending.future;
    await showPage(tester, repository, _admin);
    await showPage(tester, repository, _agent);
    pending.complete([_admin]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Access denied.'), findsOneWidget);
    expect(find.byType(UserDirectory), findsNothing);
    expect(repository.listUsersCalls, 1);
  });

  for (final width in <double>[390, 1440]) {
    testWidgets(
      'Directory handles long identities and large text at ${width.toInt()}px',
      (tester) async {
        viewport(tester, width);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final longUser = testProfile(
          TestUser(
            uid: 'long',
            displayName: 'Alexandertheodore Verylongname Consultant',
            email: 'averylongemailaddressfortheconsultant@kholidaymaps.com',
          ),
        );
        final repository = FakeUserProfileRepository()
          ..onListUsers = () async => [longUser];
        await showPage(tester, repository, _admin);
        await tester.pumpAndSettle();
        expect(find.byType(Table), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('Last login formatting handles unavailable, midnight and noon', () {
    expect(formatLastLogin(null), '—');
    expect(
      formatLastLogin(DateTime(2026, 9, 24, 0, 5)),
      '24 Sep 2026, 12:05 AM',
    );
    expect(formatLastLogin(DateTime(2026, 9, 24, 12)), '24 Sep 2026, 12:00 PM');
    expect(
      formatLastLogin(DateTime(2026, 9, 24, 17, 42)),
      '24 Sep 2026, 5:42 PM',
    );
  });

  testWidgets(
    'Missing name falls back to email and unavailable login shows a dash',
    (tester) async {
      final user = KayraUser(
        uid: 'unknown',
        email: 'unknown@kholidaymaps.com',
        role: KayraUserRole.agent,
        status: KayraUserStatus.active,
        createdAt: DateTime.utc(2026),
        lastLoginAt: null,
      );
      final repository = FakeUserProfileRepository()
        ..onListUsers = () async => [user];
      await showPage(tester, repository, _admin);
      expect(find.text('unknown@kholidaymaps.com'), findsNWidgets(2));
      expect(find.text('Last login · —'), findsOneWidget);
    },
  );
}
