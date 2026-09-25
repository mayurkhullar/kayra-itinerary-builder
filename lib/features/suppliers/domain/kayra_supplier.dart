import '../../../shared/validation/contact_validation.dart';

enum SupplierStatus {
  active('active'),
  inactive('inactive');

  const SupplierStatus(this.value);
  final String value;

  static SupplierStatus parse(Object? value) => values.firstWhere(
    (status) => status.value == value,
    orElse: () => throw const FormatException('Invalid supplier status.'),
  );
}

enum SupplierServiceCategory {
  dmc('dmc', 'DMC'),
  hotels('hotels', 'Hotels'),
  transfers('transfers', 'Transfers'),
  activities('activities', 'Activities'),
  visa('visa', 'Visa'),
  flights('flights', 'Flights'),
  other('other', 'Other');

  const SupplierServiceCategory(this.value, this.label);
  final String value;
  final String label;

  static SupplierServiceCategory parse(Object? value) => values.firstWhere(
    (category) => category.value == value,
    orElse: () =>
        throw const FormatException('Invalid supplier service category.'),
  );
}

abstract final class SupplierValidation {
  static String requiredText(String value, String label) {
    final error = ContactValidation.requiredTextError(value, label: label);
    if (error != null) throw FormatException(error);
    return value.trim();
  }

  static String id(String value) {
    if (value.isEmpty ||
        value.trim() != value ||
        value.contains('/') ||
        value == '.' ||
        value == '..') {
      throw const FormatException('Invalid supplier or creator identity.');
    }
    return value;
  }

  static List<String> destinations(List<String> values) {
    final seen = <String>{};
    return List.unmodifiable(
      values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty && seen.add(value.toLowerCase())),
    );
  }

  static List<SupplierContact> contacts(List<SupplierContact> values) {
    if (values.where((contact) => contact.isPrimary).length > 1) {
      throw const FormatException('Only one supplier contact may be primary.');
    }
    if (values.isEmpty || values.any((contact) => contact.isPrimary)) {
      return List.unmodifiable(values);
    }
    final first = values.first;
    return List.unmodifiable([
      SupplierContact(
        name: first.name,
        phone: first.phone,
        email: first.email,
        isPrimary: true,
      ),
      ...values.skip(1),
    ]);
  }
}

final class SupplierContact {
  SupplierContact({
    required String name,
    String? phone,
    String? email,
    this.isPrimary = false,
  }) : name = SupplierValidation.requiredText(name, 'Contact name'),
       phone = _phone(phone),
       email = _email(email) {
    if (this.phone == null && this.email == null) {
      throw const FormatException('A contact needs a phone number or email.');
    }
  }

  factory SupplierContact.fromMap(Map<String, Object?> data) {
    _fields(data, {'name', 'isPrimary'}, {'phone', 'email'});
    if (data['isPrimary'] is! bool) {
      throw const FormatException('Invalid primary contact flag.');
    }
    return SupplierContact(
      name: _string(data['name']),
      phone: _nullableString(data['phone']),
      email: _nullableString(data['email']),
      isPrimary: data['isPrimary'] as bool,
    );
  }

  final String name;
  final String? phone;
  final String? email;
  final bool isPrimary;

  Map<String, Object?> toMap() => {
    'name': name,
    'phone': phone,
    'email': email,
    'isPrimary': isPrimary,
  };

  static String? _phone(String? value) {
    final phone = _optionalText(value);
    if (phone == null) return null;
    final error = ContactValidation.mobileNumberError(phone);
    if (error != null) throw FormatException(error);
    return phone;
  }

  static String? _email(String? value) {
    final error = ContactValidation.emailError(value);
    if (error != null) throw FormatException(error);
    return _optionalText(value)?.toLowerCase();
  }
}

/// Editable shared-master profile, without status or audit fields.
final class SupplierDetails {
  SupplierDetails({
    required String name,
    List<SupplierContact> contacts = const [],
    List<String> destinationCoverage = const [],
    List<SupplierServiceCategory> serviceCategories = const [],
  }) : name = SupplierValidation.requiredText(name, 'Supplier name'),
       contacts = SupplierValidation.contacts(contacts),
       destinationCoverage = SupplierValidation.destinations(
         destinationCoverage,
       ),
       serviceCategories = List.unmodifiable(serviceCategories.toSet());

  final String name;
  final List<SupplierContact> contacts;
  final List<String> destinationCoverage;
  final List<SupplierServiceCategory> serviceCategories;

  String get normalizedName => name.toLowerCase();

  Map<String, Object?> toMap() => {
    'name': name,
    'contacts': contacts.map((contact) => contact.toMap()).toList(),
    'destinationCoverage': destinationCoverage.toList(),
    'serviceCategories': serviceCategories
        .map((category) => category.value)
        .toList(),
  };
}

/// Company-wide supplier master. createdByUid is audit data, not ownership.
final class KayraSupplier {
  KayraSupplier({
    required String id,
    required this.details,
    this.status = SupplierStatus.active,
    required String createdByUid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : id = SupplierValidation.id(id),
       createdByUid = SupplierValidation.id(createdByUid),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  /// The repository converts Firestore Timestamp values before parsing.
  factory KayraSupplier.fromMap(
    Map<String, Object?> data, {
    required String documentId,
  }) {
    _fields(data, {
      'name',
      'contacts',
      'destinationCoverage',
      'serviceCategories',
      'status',
      'createdByUid',
      'createdAt',
      'updatedAt',
    });
    return KayraSupplier(
      id: documentId,
      details: SupplierDetails(
        name: _string(data['name']),
        contacts: _list(data['contacts']).map((value) {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Invalid supplier contact.');
          }
          return SupplierContact.fromMap(value);
        }).toList(),
        destinationCoverage: _list(
          data['destinationCoverage'],
        ).map(_string).toList(),
        serviceCategories: _list(
          data['serviceCategories'],
        ).map(SupplierServiceCategory.parse).toList(),
      ),
      status: SupplierStatus.parse(data['status']),
      createdByUid: _string(data['createdByUid']),
      createdAt: _dateTime(data['createdAt']),
      updatedAt: _dateTime(data['updatedAt']),
    );
  }

  final String id;
  final SupplierDetails details;
  final SupplierStatus status;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get name => details.name;
  String get normalizedName => details.normalizedName;
  List<SupplierContact> get contacts => details.contacts;
  List<String> get destinationCoverage => details.destinationCoverage;
  List<SupplierServiceCategory> get serviceCategories =>
      details.serviceCategories;

  /// Domain serialization; repository writes only editable fields and server time.
  Map<String, Object?> toMap() => {
    ...details.toMap(),
    'status': status.value,
    'createdByUid': createdByUid,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

void _fields(
  Map<String, Object?> data,
  Set<String> required, [
  Set<String> optional = const {},
]) {
  if (!required.every(data.containsKey) ||
      !required.union(optional).containsAll(data.keys)) {
    throw const FormatException('Incomplete or unsupported supplier fields.');
  }
}

String _string(Object? value) => switch (value) {
  String value => value,
  _ => throw const FormatException('Invalid supplier text field.'),
};
String? _nullableString(Object? value) => value == null ? null : _string(value);
String? _optionalText(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

List<Object?> _list(Object? value) => switch (value) {
  List value => List<Object?>.from(value),
  _ => throw const FormatException('Invalid supplier list field.'),
};
DateTime _dateTime(Object? value) => switch (value) {
  DateTime value => value,
  _ => throw const FormatException('Invalid supplier timestamp.'),
};
