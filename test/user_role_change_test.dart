import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/admin/presentation/pages/user_management_page.dart';
import 'package:kayra_crm_v1/features/admin/presentation/widgets/change_role_dialog.dart';
import 'package:kayra_crm_v1/features/admin/presentation/widgets/user_directory.dart';
import 'package:kayra_crm_v1/features/users/domain/kayra_user.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_user_profile_repository.dart';

final _admin = testProfile(TestUser(), role: KayraUserRole.admin);
KayraUser _other(KayraUserRole role) => testProfile(
  TestUser(
    uid: 'other',
    displayName: 'Priya Shah',
    email: 'priya@kholidaymaps.com',
  ),
  role: role,
);

void main() {
  Future<void> showPage(
    WidgetTester tester,
    FakeUserProfileRepository repository, {
    KayraUser? currentUser,
    double width = 1440,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: UserManagementPage(
            currentUser: currentUser ?? _admin,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    final action = find.byKey(const ValueKey('change-role-other'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  Future<void> selectRole(WidgetTester tester, KayraUserRole role) async {
    await tester.tap(find.byType(DropdownButtonFormField<KayraUserRole>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(role.label).last);
    await tester.pumpAndSettle();
  }

  for (final width in <double>[390, 1440]) {
    for (final original in KayraUserRole.values) {
      final next = original == KayraUserRole.agent
          ? KayraUserRole.admin
          : KayraUserRole.agent;
      testWidgets(
        '${original.name} to ${next.name} refreshes role at ${width.toInt()}px',
        (tester) async {
          var user = _other(original);
          final repository = FakeUserProfileRepository()
            ..onListUsers = (() async => [_admin, user])
            ..onUpdateUserRole = (uid, role) async {
              user = _other(role);
            };
          await showPage(tester, repository, width: width);
          expect(
            find.byKey(ValueKey('change-role-${_admin.uid}')),
            findsNothing,
          );
          expect(find.text('You'), findsOneWidget);
          expect(
            find.text('Actions'),
            width == 1440 ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(DropdownButtonFormField<KayraUserStatus>),
            findsNothing,
          );
          expect(find.text('Deactivate'), findsNothing);
          expect(find.text('Reactivate'), findsNothing);
          await openDialog(tester);
          expect(find.text('Current role: ${original.label}'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Update role'),
                )
                .onPressed,
            isNull,
          );
          final selector = tester
              .widget<DropdownButtonFormField<KayraUserRole>>(
                find.byType(DropdownButtonFormField<KayraUserRole>),
              );
          // The controlled selector exposes precisely the two supported roles.
          expect(selector.initialValue, original);
          expect(
            tester
                .widget<DropdownButton<KayraUserRole>>(
                  find.byType(DropdownButton<KayraUserRole>),
                )
                .items!
                .map((item) => item.value),
            KayraUserRole.values,
          );
          await selectRole(tester, next);
          expect(
            find.text(
              next == KayraUserRole.admin
                  ? 'Admins can view and manage Kayra users.'
                  : 'This user will lose Admin access.',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          for (final element
              in find
                  .descendant(
                    of: find.byType(AlertDialog),
                    matching: find.byType(Text),
                  )
                  .evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
          await tester.tap(find.text('Update role'));
          await tester.pumpAndSettle();
          expect(repository.roleUpdates, [(userId: 'other', role: next)]);
          expect(repository.listUsersCalls, 2);
          expect(find.byType(ChangeRoleDialog), findsNothing);
          final directory = tester.widget<UserDirectory>(
            find.byType(UserDirectory),
          );
          expect(directory.users.last.role, next);
          expect(directory.users.last.status, KayraUserStatus.active);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('page callback rejects self editing even when invoked directly', (
    tester,
  ) async {
    final repository = FakeUserProfileRepository()
      ..onListUsers = () async => [_admin];
    await showPage(tester, repository);
    tester
        .widget<UserDirectory>(find.byType(UserDirectory))
        .onChangeRole(_admin);
    await tester.pumpAndSettle();
    expect(find.byType(ChangeRoleDialog), findsNothing);
    expect(repository.roleUpdates, isEmpty);
  });

  testWidgets(
    'pending save disables duplicate submissions, cancellation and selection',
    (tester) async {
      final pending = Completer<void>();
      final repository = FakeUserProfileRepository()
        ..onListUsers = (() async => [_admin, _other(KayraUserRole.agent)])
        ..onUpdateUserRole = (_, _) => pending.future;
      await showPage(tester, repository);
      await openDialog(tester);
      await selectRole(tester, KayraUserRole.admin);
      // Invoke the same captured callback twice, before a rebuild.
      final save = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Update role'),
          )
          .onPressed!;
      save();
      save();
      await tester.pump();
      expect(repository.roleUpdates, hasLength(1));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<KayraUserRole>>(
              find.byType(DropdownButtonFormField<KayraUserRole>),
            )
            .onChanged,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final dialogContext = tester.element(find.byType(ChangeRoleDialog));
      await Navigator.of(dialogContext).maybePop();
      await tester.pump();
      expect(find.byType(ChangeRoleDialog), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ChangeRoleDialog), findsNothing);
    },
  );

  testWidgets('failed save shows safe inline text and supports retry', (
    tester,
  ) async {
    final repository = FakeUserProfileRepository()
      ..onListUsers = (() async => [_other(KayraUserRole.agent)])
      ..onUpdateUserRole = (_, _) async =>
          throw StateError('private Firebase error');
    await showPage(tester, repository);
    await openDialog(tester);
    await selectRole(tester, KayraUserRole.admin);
    await tester.tap(find.text('Update role'));
    await tester.pumpAndSettle();
    expect(
      find.text('Role couldn’t be updated. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private Firebase'), findsNothing);
    expect(repository.listUsersCalls, 1);
    repository.onUpdateUserRole = (_, _) async {};
    await tester.tap(find.text('Update role'));
    await tester.pumpAndSettle();
    expect(repository.roleUpdates, hasLength(2));
    expect(repository.listUsersCalls, 2);
    expect(find.byType(ChangeRoleDialog), findsNothing);
  });

  testWidgets('cancel and selecting the original role never write', (
    tester,
  ) async {
    final repository = FakeUserProfileRepository()
      ..onListUsers = () async => [_other(KayraUserRole.agent)];
    await showPage(tester, repository);
    await openDialog(tester);
    await selectRole(tester, KayraUserRole.admin);
    await selectRole(tester, KayraUserRole.agent);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Update role'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.roleUpdates, isEmpty);
    expect(repository.listUsersCalls, 1);
  });

  testWidgets('losing Admin access while dialog is open blocks submission', (
    tester,
  ) async {
    final repository = FakeUserProfileRepository()
      ..onListUsers = () async => [_other(KayraUserRole.agent)];
    await showPage(tester, repository);
    await openDialog(tester);
    await selectRole(tester, KayraUserRole.admin);
    await showPage(tester, repository, currentUser: testProfile(TestUser()));
    await tester.tap(find.text('Update role'));
    await tester.pumpAndSettle();
    expect(repository.roleUpdates, isEmpty);
    expect(
      find.text('Role couldn’t be updated. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Access denied.'), findsOneWidget);
  });
}
