import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/suppliers/domain/kayra_supplier.dart';

SupplierContact _contact({bool primary = false}) => SupplierContact(
  name: ' Jane ',
  phone: ' +44 (20) 1234-5678 ',
  isPrimary: primary,
);

Map<String, Object?> _record() => {
  'name': ' Example DMC ',
  'contacts': [_contact().toMap()],
  'destinationCoverage': [' Dubai ', 'dubai', '', 'Thailand'],
  'serviceCategories': ['dmc', 'hotels'],
  'status': 'active',
  'createdByUid': 'agent-1',
  'createdAt': DateTime.utc(2026, 9, 1),
  'updatedAt': DateTime.utc(2026, 9, 25),
};

void main() {
  test(
    'valid supplier round trips with normalized immutable profile and audit data',
    () {
      final supplier = KayraSupplier.fromMap(
        _record(),
        documentId: 'supplier-1',
      );
      expect(supplier.id, 'supplier-1');
      expect(supplier.name, 'Example DMC');
      expect(supplier.normalizedName, 'example dmc');
      expect(supplier.createdByUid, 'agent-1');
      expect(supplier.createdAt, DateTime.utc(2026, 9, 1));
      expect(supplier.updatedAt, DateTime.utc(2026, 9, 25));
      expect(supplier.status, SupplierStatus.active);
      expect(supplier.contacts.single.name, 'Jane');
      expect(supplier.contacts.single.phone, '+44 (20) 1234-5678');
      expect(supplier.contacts.single.isPrimary, isTrue);
      expect(supplier.destinationCoverage, ['Dubai', 'Thailand']);
      expect(supplier.serviceCategories, [
        SupplierServiceCategory.dmc,
        SupplierServiceCategory.hotels,
      ]);
      expect(
        KayraSupplier.fromMap(
          supplier.toMap(),
          documentId: supplier.id,
        ).toMap(),
        supplier.toMap(),
      );
      expect(supplier.toMap().containsKey('id'), isFalse);
    },
  );

  test('constructor defaults to active and converts dates to UTC', () {
    final date = DateTime(2026, 9, 1);
    final supplier = KayraSupplier(
      id: 'one',
      details: SupplierDetails(name: 'ABC'),
      createdByUid: 'agent',
      createdAt: date,
      updatedAt: date,
    );
    expect(supplier.status, SupplierStatus.active);
    expect(supplier.createdAt, date.toUtc());
    expect(supplier.updatedAt.isUtc, isTrue);
  });

  for (final name in ['', '  ', '\n']) {
    test('supplier and contact names reject blank: ${name.codeUnits}', () {
      expect(() => SupplierDetails(name: name), throwsFormatException);
      expect(
        () => SupplierContact(name: name, email: 'a@example.com'),
        throwsFormatException,
      );
    });
  }

  test('multiple contacts retain explicit primary without reordering', () {
    final details = SupplierDetails(
      name: 'ABC',
      contacts: [
        _contact(),
        SupplierContact(
          name: ' Sam ',
          email: ' SAM@EXAMPLE.COM ',
          isPrimary: true,
        ),
      ],
    );
    expect(details.contacts.map((c) => c.name), ['Jane', 'Sam']);
    expect(details.contacts.map((c) => c.isPrimary), [false, true]);
    expect(details.contacts.last.email, 'sam@example.com');
    expect(details.contacts.last.phone, isNull);
  });
  test(
    'first contact becomes primary deterministically without mutating input',
    () {
      final first = _contact();
      final details = SupplierDetails(
        name: 'ABC',
        contacts: [first, _contact()],
      );
      expect(details.contacts.map((c) => c.isPrimary), [true, false]);
      expect(first.isPrimary, isFalse);
      expect(SupplierDetails(name: 'ABC').contacts, isEmpty);
    },
  );
  test('multiple primary contacts are rejected', () {
    expect(
      () => SupplierDetails(
        name: 'ABC',
        contacts: [_contact(primary: true), _contact(primary: true)],
      ),
      throwsFormatException,
    );
  });
  test(
    'contact requires phone or email, blank optional fields become null',
    () {
      expect(() => SupplierContact(name: 'Jane'), throwsFormatException);
      expect(
        () => SupplierContact(name: 'Jane', phone: ' ', email: '\n'),
        throwsFormatException,
      );
      final contact = SupplierContact(
        name: 'Jane',
        phone: ' ',
        email: 'A@EXAMPLE.COM',
      );
      expect(contact.phone, isNull);
      expect(contact.email, 'a@example.com');
      expect(_contact().email, isNull);
    },
  );
  for (final phone in [
    '1234567',
    '+123456789012345',
    '+91 98765-43210',
    '(020) 1234 5678',
  ]) {
    test('accepts international phone $phone', () {
      expect(SupplierContact(name: 'Jane', phone: phone).phone, phone);
    });
  }
  for (final phone in [
    '123456',
    '1234567890123456',
    'call me',
    '12+3456789',
    '++12345678',
    '123.456.7890',
  ]) {
    test('rejects phone $phone even with a valid email', () {
      expect(
        () =>
            SupplierContact(name: 'Jane', phone: phone, email: 'a@example.com'),
        throwsFormatException,
      );
    });
  }
  test('valid email is trimmed and lowercased', () {
    expect(
      SupplierContact(name: 'Jane', email: ' SALES+UK@EXAMPLE.CO.UK ').email,
      'sales+uk@example.co.uk',
    );
  });
  for (final email in [
    'bad',
    'a@localhost',
    'a..b@example.com',
    '.a@example.com',
    'a@-example.com',
    'a b@example.com',
    'a@@example.com',
  ]) {
    test('rejects email $email even with a valid phone', () {
      expect(
        () => SupplierContact(name: 'Jane', phone: '1234567', email: email),
        throwsFormatException,
      );
    });
  }
  test(
    'destinations trim, remove blanks and deduplicate case-insensitively in order',
    () {
      final details = SupplierDetails(
        name: ' ABC Travels ',
        destinationCoverage: [
          ' ',
          ' Dubai ',
          'dubai',
          'Abu Dhabi',
          'DUBAI',
          ' Thailand ',
          '\n',
        ],
      );
      expect(details.name, 'ABC Travels');
      expect(details.destinationCoverage, ['Dubai', 'Abu Dhabi', 'Thailand']);
      expect(SupplierDetails(name: 'ABC').destinationCoverage, isEmpty);
    },
  );
  test('service categories persist stable values independently of labels', () {
    final details = SupplierDetails(
      name: 'ABC',
      serviceCategories: [
        ...SupplierServiceCategory.values,
        SupplierServiceCategory.dmc,
      ],
    );
    expect(details.toMap()['serviceCategories'], [
      'dmc',
      'hotels',
      'transfers',
      'activities',
      'visa',
      'flights',
      'other',
    ]);
    expect(SupplierServiceCategory.dmc.label, 'DMC');
    for (final category in SupplierServiceCategory.values) {
      expect(SupplierServiceCategory.parse(category.value), category);
    }
  });
  test(
    'collections are defensively copied and serialization cannot mutate model',
    () {
      final contacts = [_contact()];
      final destinations = ['Dubai'];
      final categories = [SupplierServiceCategory.dmc];
      final details = SupplierDetails(
        name: 'ABC',
        contacts: contacts,
        destinationCoverage: destinations,
        serviceCategories: categories,
      );
      contacts.clear();
      destinations.clear();
      categories.clear();
      expect(details.contacts, hasLength(1));
      expect(details.destinationCoverage, ['Dubai']);
      expect(details.serviceCategories, [SupplierServiceCategory.dmc]);
      expect(() => details.contacts.clear(), throwsUnsupportedError);
      expect(() => details.destinationCoverage.clear(), throwsUnsupportedError);
      expect(() => details.serviceCategories.clear(), throwsUnsupportedError);
      final map = details.toMap();
      (map['destinationCoverage'] as List).clear();
      ((map['contacts'] as List).first as Map)['name'] = 'Changed';
      expect(details.destinationCoverage, ['Dubai']);
      expect(details.contacts.single.name, 'Jane');
    },
  );
  test('inactive is parsed without being changed to the creation default', () {
    expect(
      KayraSupplier.fromMap({
        ..._record(),
        'status': 'inactive',
      }, documentId: 'one').status,
      SupplierStatus.inactive,
    );
  });
  for (final field in _record().keys) {
    test('rejects missing required record field $field', () {
      expect(
        () =>
            KayraSupplier.fromMap(_record()..remove(field), documentId: 'one'),
        throwsFormatException,
      );
    });
  }
  test('rejects malformed types, status, categories and unexpected fields', () {
    for (final patch in <Map<String, Object?>>[
      {'name': 1},
      {'status': 'unknown'},
      {'status': null},
      {
        'serviceCategories': ['DMC'],
      },
      {
        'serviceCategories': [1],
      },
      {'serviceCategories': 'dmc'},
      {
        'destinationCoverage': [1],
      },
      {'destinationCoverage': null},
      {'contacts': 'bad'},
      {
        'contacts': [1],
      },
      {
        'contacts': [
          {'name': 'Jane', 'email': 'a@example.com', 'isPrimary': 'true'},
        ],
      },
      {
        'contacts': [
          {'name': 'Jane', 'phone': 1234567, 'isPrimary': false},
        ],
      },
      {
        'contacts': [
          {'name': 'Jane', 'email': 'a@example.com'},
        ],
      },
      {'createdAt': 'yesterday'},
      {'updatedAt': null},
      {'createdByUid': ''},
      {'unknown': true},
    ]) {
      expect(
        () =>
            KayraSupplier.fromMap({..._record(), ...patch}, documentId: 'one'),
        throwsFormatException,
        reason: '$patch',
      );
    }
  });
  for (final id in ['', ' ', ' a', 'a/b', '.', '..']) {
    test('rejects invalid document identity and creator $id', () {
      expect(
        () => KayraSupplier.fromMap(_record(), documentId: id),
        throwsFormatException,
      );
      expect(
        () => KayraSupplier.fromMap({
          ..._record(),
          'createdByUid': id,
        }, documentId: 'one'),
        throwsFormatException,
      );
    });
  }
}
