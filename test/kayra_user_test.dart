import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/users/domain/kayra_user.dart';

void main() {
  test('parses the immutable application identity and UTC timestamps', () {
    final profile = KayraUser.fromMap(_profile(), documentId: 'agent-1');

    expect(profile.uid, 'agent-1');
    expect(profile.email, 'agent@kholidaymaps.com');
    expect(profile.displayName, 'Kayra Agent');
    expect(profile.photoUrl, 'https://example.com/avatar.png');
    expect(profile.role, KayraUserRole.agent);
    expect(profile.role.label, 'Agent');
    expect(profile.isActive, isTrue);
    expect(profile.createdAt, DateTime.utc(2026, 9, 1));
    expect(profile.lastLoginAt, DateTime.utc(2026, 9, 24));
    expect(profile.createdAt.isUtc, isTrue);
    expect(profile.lastLoginAt.isUtc, isTrue);
  });

  test('retains admin and inactive values without authorizing the user', () {
    final profile = KayraUser.fromMap({
      ..._profile(),
      'role': 'admin',
      'status': 'inactive',
      'displayName': null,
      'photoUrl': null,
    }, documentId: 'agent-1');

    expect(profile.role, KayraUserRole.admin);
    expect(profile.role.label, 'Admin');
    expect(profile.status, KayraUserStatus.inactive);
    expect(profile.isActive, isFalse);
    expect(profile.displayName, isNull);
    expect(profile.photoUrl, isNull);
  });

  final invalidFields = <String, List<Object?>>{
    'uid': ['', 'another-user', '../agent-1', null, 1],
    'email': [
      'agent@gmail.com',
      'agent@team.kholidaymaps.com',
      'agent@kholidaymaps.com.example.com',
      '@kholidaymaps.com',
      'other@agent@kholidaymaps.com',
      'AGENT@KHOLIDAYMAPS.COM',
      ' agent@kholidaymaps.com ',
      'agent name@kholidaymaps.com',
      null,
    ],
    'displayName': [false, 5],
    'photoUrl': [false, 5],
    'role': ['owner', 'Admin', null, 1],
    'status': ['pending', 'Active', null, true],
    'createdAt': [null, '2026-09-01', 1],
    'lastLoginAt': [null, '2026-09-24', 1],
  };

  for (final field in invalidFields.entries) {
    for (final value in field.value) {
      test('rejects invalid ${field.key}: $value', () {
        expect(
          () => KayraUser.fromMap({
            ..._profile(),
            field.key: value,
          }, documentId: 'agent-1'),
          throwsFormatException,
        );
      });
    }
  }

  test('rejects a stored UID that does not match its document', () {
    expect(
      () => KayraUser.fromMap(_profile(), documentId: 'other-user'),
      throwsFormatException,
    );
  });

  for (final field in _profile().keys) {
    test('requires the $field field, including nullable identity fields', () {
      final data = _profile()..remove(field);
      expect(
        () => KayraUser.fromMap(data, documentId: 'agent-1'),
        throwsFormatException,
      );
    });
  }

  test(
    'rejects unsupported fields rather than accepting an unknown schema',
    () {
      expect(
        () => KayraUser.fromMap({
          ..._profile(),
          'permissions': ['manage-users'],
        }, documentId: 'agent-1'),
        throwsFormatException,
      );
    },
  );
}

Map<String, Object?> _profile() => {
  'uid': 'agent-1',
  'email': 'agent@kholidaymaps.com',
  'displayName': 'Kayra Agent',
  'photoUrl': 'https://example.com/avatar.png',
  'role': 'agent',
  'status': 'active',
  'createdAt': DateTime.utc(2026, 9, 1),
  'lastLoginAt': DateTime.utc(2026, 9, 24),
};
