import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/app/app.dart';
import 'package:kayra_crm_v1/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:kayra_crm_v1/features/dashboard/presentation/widgets/dashboard_sections.dart';
import 'package:kayra_crm_v1/shared/widgets/kayra_app_header.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_user_profile_repository.dart';

void main() {
  Future<void> showDashboard(WidgetTester tester, {TestUser? user}) async {
    final auth = FakeAuthService(user: user ?? TestUser());
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      KayraApp(
        authService: auth,
        userProfileRepository: FakeUserProfileRepository(),
      ),
    );
    await tester.pumpAndSettle();
  }

  const widths = <double>[375, 390, 430, 768, 1024, 1280, 1440, 1920];
  for (final width in widths) {
    testWidgets('Agent dashboard fits a ${width.toInt()}px viewport', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showDashboard(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.text('Good to see you, Maya.'), findsOneWidget);
      expect(find.text('Needs Attention'), findsOneWidget);
      expect(find.byType(MyTripsSection), findsOneWidget);
      expect(find.byType(ReusableItinerariesPanel), findsOneWidget);
      expect(find.text('Nothing needs your attention'), findsOneWidget);
      expect(find.text('You’re all caught up for now.'), findsOneWidget);
      expect(find.text('No trips yet'), findsOneWidget);
      expect(
        find.text('Create your first itinerary to start building a journey.'),
        findsOneWidget,
      );
      expect(find.text('Workspace preview'), findsNothing);
      expect(find.text('KAYRA WORKSPACE'), findsNothing);
      final header = tester.widget<KayraAppHeader>(find.byType(KayraAppHeader));
      expect(header.roleLabel, 'Agent');

      final logo = tester.widget<Image>(find.byType(Image));
      expect(
        (logo.image as AssetImage).assetName,
        'assets/brand/kayra_logo.png',
      );
      expect(logo.fit, BoxFit.contain);

      for (final type in [FilledButton, OutlinedButton, TextField]) {
        for (final control in find.byType(type).evaluate()) {
          final rect = tester.getRect(find.byWidget(control.widget));
          expect(rect.left, greaterThanOrEqualTo(20));
          expect(rect.right, lessThanOrEqualTo(width - 20));
          expect(rect.height, greaterThanOrEqualTo(48));
        }
      }
      if (width >= 1440) {
        final section = tester.getRect(find.byType(MyTripsSection));
        expect(section.width, lessThanOrEqualTo(1320));
        expect(section.center.dx, closeTo(width / 2, 1));
        expect(
          tester.getSize(find.byType(TextField)).width,
          lessThanOrEqualTo(680),
        );
      }
      await tester.ensureVisible(find.text('Browse Library'));
      await tester.pumpAndSettle();
      expect(find.text('Browse Library').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final name in <String?>[
    null,
    '',
    '   ',
    '  Mayur   Khullar  ',
    'Priya',
  ]) {
    testWidgets('Greeting handles display name "$name" safely', (tester) async {
      await showDashboard(tester, user: TestUser(displayName: name));
      final expected = switch (name) {
        '  Mayur   Khullar  ' => 'Good to see you, Mayur.',
        'Priya' => 'Good to see you, Priya.',
        _ => 'Good to see you.',
      };
      expect(find.text(expected), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Shell actions give feedback without feature navigation', (
    tester,
  ) async {
    await showDashboard(tester);
    await tester.enterText(find.byType(TextField), 'Sample text');
    expect(find.text('Sample text'), findsOneWidget);
    for (final action in [
      find.text('Create New Itinerary').first,
      find.text('Browse Reusable Itineraries'),
      find.text('Browse Library'),
    ]) {
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('This feature is not available yet.'), findsOneWidget);
      expect(find.byType(DashboardPage), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[375, 768, 1440]) {
    testWidgets('Dashboard supports large text at ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await showDashboard(
        tester,
        user: TestUser(displayName: 'Alexandertheodore Verylongsurname'),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Browse Library'));
      await tester.pumpAndSettle();
      expect(find.text('Browse Library').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
