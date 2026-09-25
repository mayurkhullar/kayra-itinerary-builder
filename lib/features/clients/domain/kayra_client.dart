import '../../../shared/validation/contact_validation.dart';

/// Existing Client form API delegates to the shared contact validators.
abstract final class ClientValidation {
  static String? requiredTextError(String? value, {required String label}) =>
      ContactValidation.requiredTextError(value, label: label);

  static String? mobileNumberError(String? value) =>
      ContactValidation.mobileNumberError(value);

  static String? emailError(String? value) =>
      ContactValidation.emailError(value);
}

/// Validated, immutable profile fields. Contains no identity or audit metadata.
final class ClientDetails {
  ClientDetails({
    required String firstName,
    required String lastName,
    required String mobileNumber,
    String? email,
    String? city,
    String? company,
  }) : firstName = _requiredText(firstName, 'First name'),
       lastName = _requiredText(lastName, 'Last name'),
       mobileNumber = _validatedMobile(mobileNumber),
       email = _validatedEmail(email),
       city = _optionalText(city),
       company = _optionalText(company);

  final String firstName;
  final String lastName;
  final String mobileNumber;
  final String? email;
  final String? city;
  final String? company;

  String get displayName => '$firstName $lastName';

  /// Null optional values explicitly clear those fields during an update.
  Map<String, Object?> toMap() => {
    'firstName': firstName,
    'lastName': lastName,
    'mobileNumber': mobileNumber,
    'email': email,
    'city': city,
    'company': company,
  };

  static String _requiredText(String value, String label) {
    final error = ClientValidation.requiredTextError(value, label: label);
    if (error != null) throw FormatException(error);
    return value.trim();
  }

  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _validatedMobile(String value) {
    final error = ClientValidation.mobileNumberError(value);
    if (error != null) throw FormatException(error);
    return value.trim();
  }

  static String? _validatedEmail(String? value) {
    final error = ClientValidation.emailError(value);
    if (error != null) throw FormatException(error);
    return _optionalText(value)?.toLowerCase();
  }
}

/// A persisted client/contact, separate from a traveller or trip.
final class KayraClient {
  KayraClient({
    required this.id,
    required this.details,
    required this.createdByUid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (!isValidId(id) || !isValidId(createdByUid)) {
      throw const FormatException('Invalid client identity or creator.');
    }
  }

  /// The data layer converts Firestore timestamps before domain parsing.
  factory KayraClient.fromMap(
    Map<String, Object?> data, {
    required String documentId,
  }) {
    const fields = {
      'firstName',
      'lastName',
      'mobileNumber',
      'email',
      'city',
      'company',
      'createdByUid',
      'createdAt',
      'updatedAt',
    };
    if (!fields.containsAll(data.keys)) {
      throw const FormatException('Unsupported client fields.');
    }
    return KayraClient(
      id: documentId,
      details: ClientDetails(
        firstName: _requiredString(data['firstName'], 'firstName'),
        lastName: _requiredString(data['lastName'], 'lastName'),
        mobileNumber: _requiredString(data['mobileNumber'], 'mobileNumber'),
        email: _optionalString(data['email'], 'email'),
        city: _optionalString(data['city'], 'city'),
        company: _optionalString(data['company'], 'company'),
      ),
      createdByUid: _requiredString(data['createdByUid'], 'createdByUid'),
      createdAt: _dateTime(data['createdAt']),
      updatedAt: _dateTime(data['updatedAt']),
    );
  }

  final String id;
  final ClientDetails details;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get firstName => details.firstName;
  String get lastName => details.lastName;
  String get mobileNumber => details.mobileNumber;
  String? get email => details.email;
  String? get city => details.city;
  String? get company => details.company;
  String get displayName => details.displayName;

  static bool isValidId(String value) =>
      value.isNotEmpty &&
      value.trim() == value &&
      !value.contains('/') &&
      value != '.' &&
      value != '..';

  static String _requiredString(Object? value, String field) => switch (value) {
    String value => value,
    _ => throw FormatException('Invalid client $field.'),
  };

  static String? _optionalString(Object? value, String field) =>
      switch (value) {
        null => null,
        String value => value,
        _ => throw FormatException('Invalid client $field.'),
      };

  static DateTime _dateTime(Object? value) => switch (value) {
    DateTime value => value,
    _ => throw const FormatException('Invalid client timestamp.'),
  };
}
