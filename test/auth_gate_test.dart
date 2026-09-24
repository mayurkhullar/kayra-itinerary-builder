import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/app/app.dart';
import 'package:kayra_crm_v1/features/auth/data/auth_service.dart';
import 'package:kayra_crm_v1/features/auth/presentation/pages/sign_in_page.dart';

import 'support/fake_auth_service.dart';

void main() {
  Future<void> showApp(WidgetTester tester, FakeAuthService auth) async {
    addTearDown(auth.dispose);
    await tester.pumpWidget(KayraApp(authService: auth));
    await tester.pump();
  }

  testWidgets('Waits for restored auth state without flashing workspace', (
    tester,
  ) async {
    final auth = FakeAuthService(emitInitialState: false);
    await showApp(tester, auth);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SignInPage), findsNothing);
    expect(find.text('Good to see you.'), findsNothing);

    auth.emit(null);
    await tester.pumpAndSettle();
    expect(find.byType(SignInPage), findsOneWidget);
  });

  testWidgets('Signed-out session shows sign-in screen', (tester) async {
    await showApp(tester, FakeAuthService());
    await tester.pumpAndSettle();
    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Good to see you.'), findsNothing);
  });

  testWidgets('Valid restored session shows workspace and account menu', (
    tester,
  ) async {
    final auth = FakeAuthService(
      user: TestUser(email: 'MAYA@KHOLIDAYMAPS.COM'),
    );
    await showApp(tester, auth);
    await tester.pumpAndSettle();
    expect(find.text('Good to see you.'), findsOneWidget);
    expect(find.byType(SignInPage), findsNothing);
    expect(find.text('MAYA@KHOLIDAYMAPS.COM'), findsNothing);
    await tester.tap(find.byTooltip('Account menu'));
    await tester.pumpAndSettle();
    expect(find.text('MAYA@KHOLIDAYMAPS.COM'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.text('Good to see you.'), findsNothing);
  });

  testWidgets('Rejects restored external account before rendering workspace', (
    tester,
  ) async {
    final cleanup = Completer<void>();
    final auth = FakeAuthService(user: TestUser(email: 'maya@example.com'));
    auth.onSignOut = () => cleanup.future;
    await showApp(tester, auth);
    expect(find.text('Good to see you.'), findsNothing);
    expect(find.text(AuthService.domainError), findsOneWidget);
    expect(auth.signOutCalls, 1);
    auth.emit(null);
    cleanup.complete();
    await tester.pumpAndSettle();
    expect(find.text(AuthService.domainError), findsOneWidget);
    expect(find.byType(SignInPage), findsOneWidget);
  });

  testWidgets('Invalid account stays blocked when forced sign-out fails', (
    tester,
  ) async {
    final auth = FakeAuthService(
      user: TestUser(email: 'maya@kholidaymaps.com.evil.test'),
    );
    auth.onSignOut = () async => throw Exception('private SDK detail');
    await showApp(tester, auth);
    await tester.pumpAndSettle();
    expect(find.text('Good to see you.'), findsNothing);
    expect(find.text(AuthService.domainError), findsOneWidget);
    expect(find.textContaining('private SDK detail'), findsNothing);
  });

  testWidgets('Blocks duplicate submissions and waits for popup completion', (
    tester,
  ) async {
    final popup = Completer<void>();
    final auth = FakeAuthService();
    auth.onGoogleSignIn = () => popup.future;
    await showApp(tester, auth);
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);
    await tester.tap(find.byType(OutlinedButton));
    expect(auth.signInCalls, 1);
    auth.emit(TestUser());
    await tester.pump();
    expect(find.text('Good to see you.'), findsNothing);
    popup.complete();
    await tester.pumpAndSettle();
    expect(find.text('Good to see you.'), findsOneWidget);
  });

  testWidgets(
    'Rejects an invalid auth event during popup and keeps the reason',
    (tester) async {
      final auth = FakeAuthService();
      auth.onGoogleSignIn = () async {
        auth.emit(TestUser(email: 'maya@gmail.com'));
        throw const AuthFailure(AuthService.domainError);
      };
      await showApp(tester, auth);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(auth.signOutCalls, 1);
      expect(find.text('Good to see you.'), findsNothing);
      expect(find.text(AuthService.domainError), findsOneWidget);
    },
  );

  testWidgets('Displays friendly sign-in errors and allows a retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    const message =
        'Your browser blocked the sign-in window. Allow popups for Kayra and try again.';
    auth.onGoogleSignIn = () async => throw const AuthFailure(message);
    await showApp(tester, auth);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    auth.onGoogleSignIn = () async => auth.emit(TestUser());
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Good to see you.'), findsOneWidget);
  });

  testWidgets('Session errors never expose technical details or workspace', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await showApp(tester, auth);
    auth.emitError(Exception('Firebase private diagnostic'));
    await tester.pumpAndSettle();
    expect(
      find.text('We couldn’t check your session. Please sign in again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Firebase private diagnostic'), findsNothing);
    expect(find.text('Good to see you.'), findsNothing);
  });

  for (final width in <double>[375, 390, 430, 768, 1440, 1920]) {
    testWidgets('Sign-in page fits ${width.toInt()}px including domain error', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = FakeAuthService(user: TestUser(email: 'maya@example.com'));
      await showApp(tester, auth);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.text(AuthService.domainError), findsOneWidget);
      final button = tester.getRect(find.byType(OutlinedButton));
      expect(button.left, greaterThanOrEqualTo(20));
      expect(button.right, lessThanOrEqualTo(width - 20));
      expect(button.height, greaterThanOrEqualTo(48));
      if (width >= 1024) expect(button.width, lessThanOrEqualTo(440));
      final logo = tester.widget<Image>(find.byType(Image));
      expect(
        (logo.image as AssetImage).assetName,
        'assets/brand/kayra_logo.png',
      );
      expect(logo.fit, BoxFit.contain);
    });
  }

  testWidgets('Sign-in controls remain reachable with large mobile text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 667);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await showApp(tester, FakeAuthService(user: TestUser(email: null)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.byType(OutlinedButton).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
