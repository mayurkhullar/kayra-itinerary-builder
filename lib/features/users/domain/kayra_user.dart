enum KayraUserRole {
  agent,
  admin;

  String get label => switch (this) {
    agent => 'Agent',
    admin => 'Admin',
  };
}

enum KayraUserStatus { active, inactive }

/// The application profile, independent of the Firebase authentication user.
final class KayraUser {
  const KayraUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.lastLoginAt,
  });

  /// Parses a complete profile after the data layer converts its timestamps.
  /// Unknown access values never fall back to an active or privileged user.
  /// Only directory reads opt into missing login metadata; bootstrap is strict.
  factory KayraUser.fromMap(
    Map<String, Object?> data, {
    required String documentId,
    bool allowMissingLastLoginAt = false,
  }) {
    const fields = {
      'uid',
      'email',
      'displayName',
      'photoUrl',
      'role',
      'status',
      'createdAt',
      'lastLoginAt',
    };
    final requiredFields = allowMissingLastLoginAt
        ? fields.difference({'lastLoginAt'})
        : fields;
    if (!fields.containsAll(data.keys) ||
        !requiredFields.every(data.containsKey)) {
      throw const FormatException('Incomplete or unsupported user profile.');
    }

    final uid = data['uid'];
    final email = data['email'];
    if (uid is! String || !isValidUid(uid) || uid != documentId) {
      throw const FormatException('Invalid profile identity.');
    }
    if (email is! String || !isCompanyEmail(email)) {
      throw const FormatException('Invalid profile email.');
    }

    return KayraUser(
      uid: uid,
      email: email,
      displayName: _nullableString(data['displayName']),
      photoUrl: _nullableString(data['photoUrl']),
      role: switch (data['role']) {
        'agent' => KayraUserRole.agent,
        'admin' => KayraUserRole.admin,
        _ => throw const FormatException('Invalid profile role.'),
      },
      status: switch (data['status']) {
        'active' => KayraUserStatus.active,
        'inactive' => KayraUserStatus.inactive,
        _ => throw const FormatException('Invalid profile status.'),
      },
      createdAt: _dateTime(data['createdAt']),
      lastLoginAt: allowMissingLastLoginAt && data['lastLoginAt'] == null
          ? null
          : _dateTime(data['lastLoginAt']),
    );
  }

  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final KayraUserRole role;
  final KayraUserStatus status;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  bool get isActive => status == KayraUserStatus.active;
  bool get isActiveAdmin => isActive && role == KayraUserRole.admin;

  String get displayLabel {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? email : name;
  }

  static bool isValidUid(String uid) =>
      uid.isNotEmpty &&
      uid.trim() == uid &&
      !uid.contains('/') &&
      uid != '.' &&
      uid != '..';

  /// Expects the canonical lowercase value stored in a profile.
  static bool isCompanyEmail(String email) =>
      email == email.trim().toLowerCase() &&
      RegExp(r'^[^@\s]+@kholidaymaps\.com$').hasMatch(email);

  static String? _nullableString(Object? value) => switch (value) {
    null => null,
    String value => value,
    _ => throw const FormatException('Invalid profile identity field.'),
  };

  static DateTime _dateTime(Object? value) => switch (value) {
    DateTime value => value.toUtc(),
    _ => throw const FormatException('Invalid profile timestamp.'),
  };
}
