import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:kayra_crm_v1/features/suppliers/domain/kayra_supplier.dart';
import 'package:kayra_crm_v1/features/suppliers/presentation/pages/suppliers_page.dart';
import 'package:kayra_crm_v1/features/suppliers/presentation/widgets/supplier_form.dart';
import 'package:kayra_crm_v1/features/suppliers/presentation/widgets/supplier_contact_editor.dart';
import 'package:kayra_crm_v1/features/users/domain/kayra_user.dart';
import 'package:kayra_crm_v1/shared/widgets/kayra_app_header.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_client_repository.dart';
import 'support/fake_supplier_repository.dart';
import 'support/fake_trip_repository.dart';
import 'support/fake_user_profile_repository.dart';

final _agent = testProfile(TestUser());
final _admin = testProfile(TestUser(), role: KayraUserRole.admin);
KayraSupplier _supplier({
  String id = 'one',
  String name = 'Atlas DMC',
  SupplierStatus status = SupplierStatus.active,
}) => KayraSupplier(
  id: id,
  details: SupplierDetails(
    name: name,
    contacts: [
      SupplierContact(
        name: 'Priya Shah',
        phone: '+91 98765 43210',
        email: 'priya@example.com',
      ),
      SupplierContact(name: 'Daniel Lee', email: 'daniel@example.com'),
    ],
    destinationCoverage: ['Dubai', 'Abu Dhabi', 'Thailand', 'Singapore'],
    serviceCategories: [
      SupplierServiceCategory.dmc,
      SupplierServiceCategory.hotels,
      SupplierServiceCategory.transfers,
    ],
  ),
  status: status,
  createdByUid: 'another-agent',
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 25, 9, 35),
);

const _captureKey = ValueKey('supplier-capture');
void _viewport(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _page(
  WidgetTester tester,
  FakeSupplierRepository repository, {
  KayraUser? user,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          body: SuppliersPage(
            currentUser: user ?? _agent,
            repository: repository,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openCreate(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'New Supplier'));
  await tester.pumpAndSettle();
  expect(find.byType(SupplierForm), findsOneWidget);
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester) async {
  await _enter(tester, 'supplier-name', '  Coastal DMC  ');
  await _enter(tester, 'supplier-contact-0-Name', ' Asha ');
  await _enter(tester, 'supplier-contact-0-Phone', ' +44 (20) 1234-5678 ');
}

// Optional local render captures; normal tests never write images or load fonts.
Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['KAYRA_SUPPLIER_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final directory = Platform.environment['KAYRA_TEST_FONT_DIR'];
    if (directory != null) {
      final loader = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        loader.addFont(
          File(
            '$directory/Roboto-$weight.ttf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '$directory/MaterialIcons-Regular.otf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await icons.load();
    }
  });

  for (final user in [_agent, _admin]) {
    for (final width in <double>[390, 1280, 1440]) {
      testWidgets(
        '${user.role.name} Suppliers navigation at $width loads shared records',
        (tester) async {
          _viewport(tester, width);
          final repository = FakeSupplierRepository()
            ..suppliers.add(_supplier());
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              home: DashboardPage(
                user: user,
                onSignOut: () {},
                userProfileRepository: FakeUserProfileRepository(),
                clientRepository: FakeClientRepository(),
                tripRepository: FakeTripRepository(),
                supplierRepository: repository,
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (find.byTooltip('Menu').evaluate().isNotEmpty) {
            await tester.tap(find.byTooltip('Menu'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Suppliers').last);
          } else {
            await tester.tap(
              find.descendant(
                of: find.byType(KayraAppHeader),
                matching: find.text('Suppliers'),
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(find.byType(SuppliersPage), findsOneWidget);
          expect(find.text('Atlas DMC'), findsOneWidget);
          expect(repository.listCalls, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'empty state and name validation; valid create refreshes without browser reload',
    (tester) async {
      final repository = FakeSupplierRepository();
      await _page(tester, repository);
      expect(find.text('No suppliers yet'), findsOneWidget);
      expect(
        find.text(
          'Add your first supplier to start building Kayra’s shared network.',
        ),
        findsOneWidget,
      );
      await _openCreate(tester);
      await _tap(tester, find.text('Create Supplier'));
      expect(find.text('Supplier name is required.'), findsOneWidget);
      expect(repository.creations, isEmpty);
      await _fill(tester);
      await _tap(tester, find.text('Create Supplier'));
      expect(find.byType(SupplierForm), findsNothing);
      expect(find.text('Coastal DMC'), findsOneWidget);
      expect(repository.creations.single.uid, _agent.uid);
      expect(
        repository.creations.single.details.contacts.single.isPrimary,
        isTrue,
      );
      expect(repository.suppliers.single.status, SupplierStatus.active);
      expect(repository.listCalls, 2);
    },
  );
  testWidgets(
    'multiple contacts can select one primary and remove a row without losing other edits',
    (tester) async {
      final repository = FakeSupplierRepository();
      await _page(tester, repository);
      await _openCreate(tester);
      await _fill(tester);
      await _tap(tester, find.text('Add Contact'));
      await _enter(tester, 'supplier-contact-1-Name', 'Sam');
      await _enter(tester, 'supplier-contact-1-Email', ' SAM@EXAMPLE.COM ');
      await _tap(tester, find.byKey(const ValueKey('supplier-primary-1')));
      expect(
        tester
            .widget<RadioListTile<SupplierContactDraft>>(
              find.byKey(const ValueKey('supplier-primary-0')),
            )
            .value
            .isPrimary,
        isFalse,
      );
      expect(
        tester
            .widget<RadioListTile<SupplierContactDraft>>(
              find.byKey(const ValueKey('supplier-primary-1')),
            )
            .value
            .isPrimary,
        isTrue,
      );
      await _tap(tester, find.text('Add Contact'));
      await _tap(tester, find.byKey(const ValueKey('supplier-remove-2')));
      await _tap(tester, find.text('Create Supplier'));
      final contacts = repository.creations.single.details.contacts;
      expect(contacts.map((c) => c.name), ['Asha', 'Sam']);
      expect(contacts.map((c) => c.isPrimary), [false, true]);
      expect(contacts.last.email, 'sam@example.com');
    },
  );
  testWidgets(
    'removing primary selects first remaining contact and preserves draft values',
    (tester) async {
      final repository = FakeSupplierRepository()..suppliers.add(_supplier());
      await _page(tester, repository);
      await _tap(tester, find.text('Atlas DMC'));
      await _tap(tester, find.byKey(const ValueKey('supplier-remove-0')));
      expect(
        tester
            .widget<RadioListTile<SupplierContactDraft>>(
              find.byKey(const ValueKey('supplier-primary-0')),
            )
            .value
            .isPrimary,
        isTrue,
      );
      await _tap(tester, find.text('Save Changes'));
      expect(
        repository.updates.single.details.contacts.single.name,
        'Daniel Lee',
      );
      expect(
        repository.updates.single.details.contacts.single.isPrimary,
        isTrue,
      );
    },
  );
  for (final invalid in [
    (phone: '', email: '', error: 'A contact needs a phone number or email.'),
    (phone: '123', email: '', error: 'Enter a valid mobile number.'),
    (phone: '', email: 'invalid@', error: 'Enter a valid email address.'),
  ]) {
    testWidgets('rejects contact: ${invalid.error}', (tester) async {
      final repository = FakeSupplierRepository();
      await _page(tester, repository);
      await _openCreate(tester);
      await _fill(tester);
      await _enter(tester, 'supplier-contact-0-Phone', invalid.phone);
      await _enter(tester, 'supplier-contact-0-Email', invalid.email);
      await _tap(tester, find.text('Create Supplier'));
      expect(find.text(invalid.error), findsOneWidget);
      expect(repository.creations, isEmpty);
    });
  }
  testWidgets(
    'destinations preserve order, deduplicate, remove; multiple enum services selectable',
    (tester) async {
      final repository = FakeSupplierRepository();
      await _page(tester, repository);
      await _openCreate(tester);
      await _fill(tester);
      for (final destination in [' Dubai ', 'Thailand', 'dubai', 'Singapore']) {
        await _enter(tester, 'supplier-destination', destination);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      expect(
        tester
            .widgetList<InputChip>(find.byType(InputChip))
            .map((c) => (c.label as Text).data),
        ['Dubai', 'Thailand', 'Singapore'],
      );
      await _tap(tester, find.byTooltip('Remove Thailand'));
      for (final label in ['DMC', 'Hotels']) {
        await _tap(tester, find.widgetWithText(FilterChip, label));
      }
      await _enter(tester, 'supplier-destination', 'Abu Dhabi');
      await _tap(tester, find.text('Create Supplier'));
      expect(repository.creations.single.details.destinationCoverage, [
        'Dubai',
        'Singapore',
        'Abu Dhabi',
      ]);
      expect(repository.creations.single.details.serviceCategories, [
        SupplierServiceCategory.dmc,
        SupplierServiceCategory.hotels,
      ]);
    },
  );
  testWidgets(
    'create failure is safe; saving prevents double submit and cancellation',
    (tester) async {
      final pending = Completer<void>();
      final repository = FakeSupplierRepository()
        ..beforeSave = () => pending.future;
      await _page(tester, repository);
      await _openCreate(tester);
      await _fill(tester);
      await tester.tap(find.text('Create Supplier'));
      await tester.pump();
      expect(repository.creations, hasLength(1));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
      pending.completeError(StateError('secret Firebase path'));
      await tester.pumpAndSettle();
      expect(
        find.text('Supplier couldn’t be created. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('secret Firebase'), findsNothing);
      repository.beforeSave = null;
      await _tap(tester, find.text('Create Supplier'));
      expect(find.byType(SupplierForm), findsNothing);
    },
  );
  testWidgets(
    'edit loads existing values and preserves inactive status and creation metadata',
    (tester) async {
      final original = _supplier(status: SupplierStatus.inactive);
      final repository = FakeSupplierRepository()..suppliers.add(original);
      await _page(tester, repository);
      await _tap(tester, find.text('Atlas DMC'));
      expect(find.text('Edit Supplier'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('supplier-name')))
            .controller!
            .text,
        'Atlas DMC',
      );
      expect(
        find.descendant(
          of: find.byType(SupplierForm),
          matching: find.text('Priya Shah'),
        ),
        findsOneWidget,
      );
      expect(find.text('Daniel Lee'), findsOneWidget);
      expect(find.byType(InputChip), findsNWidgets(4));
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Hotels'))
            .selected,
        isTrue,
      );
      expect(find.text('Status: Inactive'), findsOneWidget);
      expect(find.text('Deactivate'), findsNothing);
      expect(find.text('Activate'), findsNothing);
      await _enter(tester, 'supplier-name', 'Renamed Supplier');
      await _tap(tester, find.text('Save Changes'));
      expect(find.text('Renamed Supplier'), findsOneWidget);
      expect(repository.listCalls, 2);
      expect(repository.suppliers.single.status, original.status);
      expect(repository.suppliers.single.createdAt, original.createdAt);
      expect(repository.suppliers.single.createdByUid, original.createdByUid);
    },
  );
  testWidgets('edit failure displays safe error and retains entered values', (
    tester,
  ) async {
    final repository = FakeSupplierRepository()
      ..suppliers.add(_supplier())
      ..beforeSave = () async => throw StateError('private');
    await _page(tester, repository);
    await _tap(tester, find.text('Atlas DMC'));
    await _enter(tester, 'supplier-name', 'Unsaved name');
    await _tap(tester, find.text('Save Changes'));
    expect(
      find.text('Supplier couldn’t be updated. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Unsaved name'), findsOneWidget);
    expect(find.text('private'), findsNothing);
  });
  for (final query in [
    'ATLAS',
    'priya',
    'DANIEL',
    '98765',
    'daniel@example',
    'DUBAI',
    'transfers',
  ]) {
    testWidgets('local search matches $query without querying again', (
      tester,
    ) async {
      final repository = FakeSupplierRepository()..suppliers.add(_supplier());
      await _page(tester, repository);
      await _enter(tester, 'supplier-search', query);
      expect(find.text('Atlas DMC'), findsOneWidget);
      expect(repository.listCalls, 1);
      await _enter(tester, 'supplier-search', 'not present');
      expect(find.text('No matching suppliers'), findsOneWidget);
    });
  }
  testWidgets('presentation sorts active first then case-insensitive name', (
    tester,
  ) async {
    final repository = FakeSupplierRepository()
      ..suppliers.addAll([
        _supplier(
          id: 'inactive',
          name: 'A Inactive',
          status: SupplierStatus.inactive,
        ),
        _supplier(id: 'z', name: 'Zulu'),
        _supplier(id: 'a', name: 'alpha'),
      ]);
    await _page(tester, repository);
    expect(
      tester.getTopLeft(find.text('alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Zulu')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Zulu')).dy,
      lessThan(tester.getTopLeft(find.text('A Inactive')).dy),
    );
  });
  testWidgets('loading and safe load error can retry', (tester) async {
    final pending = Completer<void>();
    final repository = FakeSupplierRepository()
      ..beforeLoad = () => pending.future;
    await _page(tester, repository);
    expect(find.text('Loading suppliers…'), findsOneWidget);
    pending.completeError(StateError('private'));
    await tester.pumpAndSettle();
    expect(find.text('Supplier data couldn’t be loaded.'), findsOneWidget);
    expect(find.text('private'), findsNothing);
    repository.beforeLoad = null;
    await _tap(tester, find.text('Try again'));
    expect(find.text('No suppliers yet'), findsOneWidget);
  });
  testWidgets('session change dismisses form and blocks stale saves', (
    tester,
  ) async {
    final repository = FakeSupplierRepository()..suppliers.add(_supplier());
    await _page(tester, repository);
    await _openCreate(tester);
    final form = tester.widget<SupplierForm>(find.byType(SupplierForm));
    final inactive = testProfile(TestUser(), status: KayraUserStatus.inactive);
    await _page(tester, repository, user: inactive);
    await tester.pumpAndSettle();
    expect(find.byType(SupplierForm), findsNothing);
    await expectLater(
      form.onSave(SupplierDetails(name: 'Stale')),
      throwsStateError,
    );
    expect(repository.creations, isEmpty);
    expect(find.text('Supplier access is unavailable.'), findsOneWidget);
  });
  for (final width in <double>[375, 390, 430, 768, 1024, 1440, 1920]) {
    testWidgets('Supplier directory and form fit $width px', (tester) async {
      _viewport(tester, width);
      final repository = FakeSupplierRepository()
        ..suppliers.addAll([
          _supplier(),
          _supplier(
            id: 'two',
            name: 'Meridian Travel',
            status: SupplierStatus.inactive,
          ),
        ]);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: DashboardPage(
              user: _admin,
              onSignOut: () {},
              userProfileRepository: FakeUserProfileRepository(),
              clientRepository: FakeClientRepository(),
              tripRepository: FakeTripRepository(),
              supplierRepository: repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (find.byTooltip('Menu').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Suppliers').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, 'directory-${width.toInt()}');
      await _tap(tester, find.text('Atlas DMC'));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'form-${width.toInt()}');
      await _tap(tester, find.widgetWithText(FilterChip, 'Other'));
      await _capture(tester, 'form-lower-${width.toInt()}');
      await _tap(tester, find.text('Save Changes'));
      expect(repository.updates, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in <double>[390, 1440]) {
    for (final count in [1, 3]) {
      testWidgets(
        'contact polish $count contacts at $width keeps header and footer fixed',
        (tester) async {
          _viewport(tester, width);
          final original = _supplier();
          final supplier = KayraSupplier(
            id: original.id,
            details: SupplierDetails(
              name: original.name,
              contacts: List.generate(
                count,
                (index) => SupplierContact(
                  name: ['Priya Shah', 'Daniel Lee', 'Asha Rao'][index],
                  phone: '+91 98765 43210',
                  email: 'contact${index + 1}@example.com',
                ),
              ),
              destinationCoverage: original.destinationCoverage,
              serviceCategories: original.serviceCategories,
            ),
            createdByUid: original.createdByUid,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt,
          );
          final repository = FakeSupplierRepository()..suppliers.add(supplier);
          await _page(tester, repository);
          await _tap(tester, find.text('Atlas DMC'));
          final header = tester.getRect(find.text('Edit Supplier'));
          final save = tester.getRect(find.text('Save Changes'));
          final cancel = tester.getRect(find.text('Cancel'));
          final dialog = tester.getSize(
            find.byKey(const ValueKey('supplier-dialog-content')),
          );
          if (width == 1440) {
            expect(dialog.width, 736);
            expect(dialog.height, lessThanOrEqualTo(900 * 0.85));
          }
          expect(find.byTooltip('Remove contact'), findsNWidgets(count));
          expect(
            find.byIcon(Icons.delete_outline_rounded),
            findsNWidgets(count),
          );
          expect(find.byType(CheckboxListTile), findsNothing);
          expect(
            find.byType(RadioListTile<SupplierContactDraft>),
            findsNWidgets(count),
          );
          await _capture(tester, 'polish-$count-${width.toInt()}-top');
          await _tap(tester, find.widgetWithText(FilterChip, 'Other'));
          expect(tester.getRect(find.text('Edit Supplier')), header);
          expect(tester.getRect(find.text('Save Changes')), save);
          expect(tester.getRect(find.text('Cancel')), cancel);
          expect(find.text('Save Changes').hitTestable(), findsOneWidget);
          expect(find.text('Destination Coverage'), findsOneWidget);
          await _capture(tester, 'polish-$count-${width.toInt()}-bottom');
          expect(tester.takeException(), isNull);
          await _tap(tester, find.text('Save Changes'));
          expect(repository.updates.single.details.contacts, hasLength(count));
        },
      );
    }
  }

  testWidgets(
    'mobile form with keyboard and large text keeps actions reachable',
    (tester) async {
      _viewport(tester, 390);
      final repository = FakeSupplierRepository();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
              viewInsets: const EdgeInsets.only(bottom: 280),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SuppliersPage(currentUser: _agent, repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openCreate(tester);
      await _fill(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Create Supplier').hitTestable(), findsOneWidget);
      await _tap(tester, find.text('Create Supplier'));
      expect(repository.creations, hasLength(1));
    },
  );
}
