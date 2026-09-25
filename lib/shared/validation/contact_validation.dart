/// Pragmatic contact validation shared across domain models and forms.
abstract final class ContactValidation {
  static String? requiredTextError(String? value, {required String label}) =>
      value == null || value.trim().isEmpty ? '$label is required.' : null;

  static String? mobileNumberError(String? value) {
    final required = requiredTextError(value, label: 'Mobile Number');
    if (required != null) return required;
    final phone = value!.trim();
    final digits = RegExp(r'[0-9]').allMatches(phone).length;
    if (!RegExp(r'^\+?[0-9 ()-]+$').hasMatch(phone) ||
        digits < 7 ||
        digits > 15) {
      return 'Enter a valid mobile number.';
    }
    return null;
  }

  static String? emailError(String? value) {
    final email = value?.trim().toLowerCase();
    if (email == null || email.isEmpty) return null;
    final parts = email.split('@');
    if (parts.length != 2 || RegExp(r'\s').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    final local = parts.first;
    final domain = parts.last.split('.');
    final validLocal =
        RegExp(r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(local) &&
        !local.startsWith('.') &&
        !local.endsWith('.') &&
        !local.contains('..');
    final validDomain =
        domain.length >= 2 &&
        domain.every(
          (label) =>
              RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
        ) &&
        RegExp(r'^[a-z]{2,}$').hasMatch(domain.last);
    return validLocal && validDomain ? null : 'Enter a valid email address.';
  }
}
