import 'package:cloud_functions/cloud_functions.dart';

import '../domain/supplier_import_finalization.dart';

enum SupplierImportFinalizationFailureKind {
  sessionExpired,
  permissionDenied,
  invalidRequest,
  invalidState,
  internal,
  unavailable,
}

final class SupplierImportFinalizationFailure implements Exception {
  const SupplierImportFinalizationFailure(this.kind);

  final SupplierImportFinalizationFailureKind kind;

  String get userMessage => switch (kind) {
    SupplierImportFinalizationFailureKind.sessionExpired =>
      'Your session has expired. Please sign in again.',
    SupplierImportFinalizationFailureKind.permissionDenied =>
      'You do not have access to finalize this Supplier Import review.',
    SupplierImportFinalizationFailureKind.invalidRequest =>
      'This Supplier Import finalization request is invalid.',
    SupplierImportFinalizationFailureKind.invalidState =>
      'This Supplier Import review cannot be finalized in its current state.',
    SupplierImportFinalizationFailureKind.internal =>
      'The Supplier Import review could not be finalized.',
    SupplierImportFinalizationFailureKind.unavailable =>
      'The change could not be confirmed. You can safely retry the same change.',
  };

  bool get isAmbiguous =>
      kind == SupplierImportFinalizationFailureKind.unavailable ||
      kind == SupplierImportFinalizationFailureKind.internal;

  @override
  String toString() => userMessage;
}

abstract interface class SupplierImportFinalizationClient {
  Future<SupplierImportFinalizationOutcome> execute(
    SupplierImportFinalizationRequest request,
  );
}

final class CallableSupplierImportFinalizationClient
    implements SupplierImportFinalizationClient {
  CallableSupplierImportFinalizationClient({
    FirebaseFunctions? functions,
    FirebaseFunctions Function(String region)? functionsForRegion,
  }) : _functions =
           functions ??
           functionsForRegion?.call(region) ??
           FirebaseFunctions.instanceFor(region: region);

  static const region = 'asia-south2';
  static const functionName = 'finalizeSupplierImport';

  final FirebaseFunctions _functions;

  @override
  Future<SupplierImportFinalizationOutcome> execute(
    SupplierImportFinalizationRequest request,
  ) async {
    try {
      final response = await _functions
          .httpsCallable(functionName)
          .call<Object?>(request.toMap());
      return SupplierImportFinalizationOutcome.fromMap(response.data);
    } on FirebaseFunctionsException catch (error) {
      throw SupplierImportFinalizationFailure(_failureKind(error.code));
    } on SupplierImportFinalizationFailure {
      rethrow;
    } catch (_) {
      throw const SupplierImportFinalizationFailure(
        SupplierImportFinalizationFailureKind.unavailable,
      );
    }
  }
}

SupplierImportFinalizationFailureKind _failureKind(
  String code,
) => switch (code) {
  'unauthenticated' => SupplierImportFinalizationFailureKind.sessionExpired,
  'permission-denied' => SupplierImportFinalizationFailureKind.permissionDenied,
  'invalid-argument' => SupplierImportFinalizationFailureKind.invalidRequest,
  'failed-precondition' => SupplierImportFinalizationFailureKind.invalidState,
  'internal' => SupplierImportFinalizationFailureKind.internal,
  'unavailable' ||
  'deadline-exceeded' => SupplierImportFinalizationFailureKind.unavailable,
  _ => SupplierImportFinalizationFailureKind.unavailable,
};
