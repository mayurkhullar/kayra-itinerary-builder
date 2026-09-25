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
      for (final phone in ['0012345', '+44 (0)20 1234 5678', '012-3456']) {
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

  for (final phone in [
    '9876543210',
    '+91 98765 43210',
    '+44 20 7946 0958',
    '(415) 555-2671',
    '415-555-2671',
    '123 4567',
    '1234567',
    '+123456789012345',
    '  +91 98765 43210  ',
  ]) {
    test(
      'accepts international display phone $phone and preserves its string',
      () {
        expect(ClientValidation.mobileNumberError(phone), isNull);
        final details = ClientDetails(
          firstName: 'A',
          lastName: 'B',
          mobileNumber: phone,
        );
        expect(details.mobileNumber, phone.trim());
        expect(details.toMap()['mobileNumber'], isA<String>());
      },
    );
  }

  for (final phone in [
    '',
    '  ',
    '123',
    '123456',
    '1234567890123456',
    '12345678901234567890',
    'abc12345',
    '+91 phone',
    '++++919876543210',
    '++1234567',
    '123+4567',
    '1234567+',
    '123/4567',
    '123.4567',
    '123\t4567',
    '123\n4567',
    '+ ( ) --',
  ]) {
    test(
      'rejects invalid phone $phone in both shared validator and domain',
      () {
        expect(
          ClientValidation.mobileNumberError(phone),
          phone.trim().isEmpty
              ? 'Mobile Number is required.'
              : 'Enter a valid mobile number.',
        );
        expect(
          () =>
              ClientDetails(firstName: 'A', lastName: 'B', mobileNumber: phone),
          throwsFormatException,
        );
      },
    );
  }

  for (final email in <String?>[
    null,
    '',
    '  ',
    'name@example.com',
    'mayur.khullar@kholidaymaps.com',
    'travel+client@example.co.uk',
    '  NAME@EXAMPLE.COM  ',
    'name@travel-company.com',
  ]) {
    test('accepts optional email $email and normalizes it', () {
      expect(ClientValidation.emailError(email), isNull);
      final details = ClientDetails(
        firstName: 'A',
        lastName: 'B',
        mobileNumber: '1234567',
        email: email,
      );
      expect(
        details.email,
        email == null || email.trim().isEmpty
            ? null
            : email.trim().toLowerCase(),
      );
    });
  }

  for (final email in [
    'abc',
    'abc@',
    '@example.com',
    'abc@example',
    'abc example@example.com',
    'abc@exam ple.com',
    'abc@@example.com',
    'abc..name@example.com',
    '.abc@example.com',
    'abc.@example.com',
    'abc@example..com',
    'abc@-example.com',
    'abc@example-.com',
    'abc@example.com.',
    'abc\nname@example.com',
    'abc\n@example.com',
    'abc@example\n.com',
    'abc@example.c',
  ]) {
    test(
      'rejects malformed optional email $email in shared and domain validation',
      () {
        expect(
          ClientValidation.emailError(email),
          'Enter a valid email address.',
        );
        expect(
          () => ClientDetails(
            firstName: 'A',
            lastName: 'B',
            mobileNumber: '1234567',
            email: email,
          ),
          throwsFormatException,
        );
        expect(
          () => KayraClient.fromMap({
            ..._record(),
            'email': email,
          }, documentId: 'client-1'),
          throwsFormatException,
        );
      },
    );
  }

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
