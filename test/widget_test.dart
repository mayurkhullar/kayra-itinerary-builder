import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/app/app.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_user_profile_repository.dart';

void main() {
  const widths = <double>[375, 390, 430, 768, 1024, 1280, 1440, 1920];

  for (final width in widths) {
    testWidgets('Foundation fits a ${width.toInt()}px viewport', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = FakeAuthService(user: TestUser());
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        KayraApp(
          authService: auth,
          userProfileRepository: FakeUserProfileRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Good to see you.'), findsOneWidget);
      expect(find.text('KAYRA WORKSPACE'), findsOneWidget);
      expect(find.text('Workspace preview'), findsOneWidget);
      expect(find.text('Find anything quickly'), findsOneWidget);
      expect(
        find.text(
          'Everything you need to build, review and manage remarkable journeys.',
        ),
        findsOneWidget,
      );
      expect(find.text('Kayra Design Foundation'), findsNothing);
      final logo = tester.widget<Image>(find.byType(Image));
      expect(
        (logo.image as AssetImage).assetName,
        'assets/brand/kayra_logo.png',
      );
      expect(logo.fit, BoxFit.contain);

      for (final control in [
        find.byType(FilledButton),
        find.byType(OutlinedButton),
        find.byType(TextField),
      ]) {
        final rect = tester.getRect(control);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      if (width < 1024) {
        expect(find.text('Reusable Itineraries'), findsNothing);
        expect(find.byTooltip('Menu preview'), findsOneWidget);
      } else {
        expect(find.text('My Trips'), findsOneWidget);
        expect(find.text('Reusable Itineraries'), findsOneWidget);
      }
      if (width >= 1440) {
        final search = tester.getRect(find.byType(TextField));
        final actions = tester.getRect(find.byType(OutlinedButton));
        expect(search.left, greaterThanOrEqualTo((width - 1200) / 2));
        expect(actions.right, lessThanOrEqualTo((width + 1200) / 2));
      }
    });
  }

  testWidgets('Preview controls provide feedback without feature navigation', (
    tester,
  ) async {
    final auth = FakeAuthService(user: TestUser());
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      KayraApp(
        authService: auth,
        userProfileRepository: FakeUserProfileRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sample text');
    expect(find.text('Sample text'), findsOneWidget);

    await tester.ensureVisible(find.text('Create New Itinerary'));
    await tester.tap(find.text('Create New Itinerary'));
    await tester.pumpAndSettle();
    expect(find.text('This is a design preview.'), findsOneWidget);
    expect(find.text('Good to see you.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Small screen supports larger accessible text and scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 667);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final auth = FakeAuthService(user: TestUser());
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      KayraApp(
        authService: auth,
        userProfileRepository: FakeUserProfileRepository(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Browse Reusable Itineraries'));
    await tester.pumpAndSettle();
    expect(
      find.text('Browse Reusable Itineraries').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
