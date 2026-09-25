import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/clients/domain/kayra_client.dart';

void main() {
  test(
    'valid client normalizes profile fields and derives its display name',
    () {
      final client = KayraClient.fromMap({
        ..._record(),
        'firstName': '  Priya ',
        'lastName': ' Shah  ',
        'mobileNumber': ' +91 09876-543210 ',
        'email': ' PRIYA@EXAMPLE.COM ',
        'city': ' Mumbai ',
        'company': ' Kayra Partner ',
      }, documentId: 'generated-id');
      expect(client.id, 'generated-id');
      expect(client.firstName, 'Priya');
      expect(client.lastName, 'Shah');
      expect(client.displayName, 'Priya Shah');
      expect(client.mobileNumber, '+91 09876-543210');
      expect(client.email, 'priya@example.com');
      expect(client.city, 'Mumbai');
      expect(client.company, 'Kayra Partner');
      expect(client.createdByUid, 'agent-1');
      expect(client.createdAt, DateTime.utc(2026, 9, 1));
      expect(client.updatedAt, DateTime.utc(2026, 9, 25));
      expect(client.createdAt.isUtc, isTrue);
      expect(client.updatedAt.isUtc, isTrue);
      expect(client.details.toMap().containsKey('displayName'), isFalse);
    },
  );

  test('optional absent, null and blank values normalize to null', () {
    for (final value in [null, '', ' \t ']) {
      final client = KayraClient.fromMap({
        ..._record(),
        'email': value,
        'city': value,
        'company': value,
      }, documentId: 'client-1');
      expect(client.email, isNull);
      expect(client.city, isNull);
      expect(client.company, isNull);
    }
    final client = KayraClient.fromMap(_record(), documentId: 'client-1');
    expect(client.company, isNull);
    expect(client.email, isNull);
    expect(client.city, isNull);
  });

  test(
    'phone strings preserve leading zeroes, plus and supplied formatting',
    () {
      for (final phone in ['0012345', '+44 (0)20 1234 5678', '012-345']) {
        final details = ClientDetails(
          firstName: 'A',
          lastName: 'B',
          mobileNumber: phone,
        );
        expect(details.toMap()['mobileNumber'], isA<String>());
        expect(details.mobileNumber, phone);
      }
    },
  );

  test('required validation can be reused by a form', () {
    for (final value in [null, '', ' \t\n']) {
      expect(
        ClientValidation.requiredTextError(value, label: 'First name'),
        'First name is required.',
      );
    }
    expect(
      ClientValidation.requiredTextError(' Priya ', label: 'First name'),
      isNull,
    );
  });

  for (final field in ['firstName', 'lastName', 'mobileNumber']) {
    for (final value in ['', ' \n ', null, 123, false]) {
      test('rejects malformed required $field: $value', () {
        expect(
          () => KayraClient.fromMap({
            ..._record(),
            field: value,
          }, documentId: 'client-1'),
          throwsFormatException,
        );
      });
    }
  }

  test('direct profile construction enforces all required fields', () {
    expect(
      () => ClientDetails(firstName: ' ', lastName: 'Shah', mobileNumber: '1'),
      throwsFormatException,
    );
    expect(
      () =>
          ClientDetails(firstName: 'Priya', lastName: '\t', mobileNumber: '1'),
      throwsFormatException,
    );
    expect(
      () =>
          ClientDetails(firstName: 'Priya', lastName: 'Shah', mobileNumber: ''),
      throwsFormatException,
    );
  });

  for (final field in _record().keys) {
    test('does not fabricate missing $field', () {
      expect(
        () => KayraClient.fromMap(
          _record()..remove(field),
          documentId: 'client-1',
        ),
        throwsFormatException,
      );
    });
  }

  for (final field in ['email', 'city', 'company']) {
    test('rejects a non-string optional $field', () {
      expect(
        () => KayraClient.fromMap({
          ..._record(),
          field: 123,
        }, documentId: 'client-1'),
        throwsFormatException,
      );
    });
  }

  for (final id in ['', ' ', ' client ', 'clients/one', '.', '..']) {
    test('rejects invalid document ID or creator $id', () {
      expect(
        () => KayraClient.fromMap(_record(), documentId: id),
        throwsFormatException,
      );
      expect(
        () => KayraClient.fromMap({
          ..._record(),
          'createdByUid': id,
        }, documentId: 'client-1'),
        throwsFormatException,
      );
    });
  }

  test('invalid dates and creator types are rejected', () {
    for (final field in ['createdAt', 'updatedAt', 'createdByUid']) {
      for (final value in [null, 123, false]) {
        expect(
          () => KayraClient.fromMap({
            ..._record(),
            field: value,
          }, documentId: 'client-1'),
          throwsFormatException,
        );
      }
    }
  });

  test(
    'domain dates are UTC and profile serialization cannot mutate the model',
    () {
      final client = KayraClient.fromMap({
        ..._record(),
        'createdAt': DateTime(2026, 9, 1),
        'updatedAt': DateTime(2026, 9, 25),
      }, documentId: 'client-1');
      expect(client.createdAt, DateTime(2026, 9, 1).toUtc());
      expect(client.updatedAt.isUtc, isTrue);
      client.details.toMap()['firstName'] = 'Changed';
      expect(client.firstName, 'Priya');
    },
  );

  test('unsupported duplicated identity is not silently accepted', () {
    expect(
      () => KayraClient.fromMap({
        ..._record(),
        'id': 'other',
      }, documentId: 'client-1'),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _record() => {
  'firstName': 'Priya',
  'lastName': 'Shah',
  'mobileNumber': '09876543210',
  'createdByUid': 'agent-1',
  'createdAt': DateTime.utc(2026, 9, 1),
  'updatedAt': DateTime.utc(2026, 9, 25),
};
