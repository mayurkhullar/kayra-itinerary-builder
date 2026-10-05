import 'package:cloud_functions/cloud_functions.dart';

import '../domain/supplier_import_resolution_mutation.dart';

enum SupplierImportMutationFailureKind {
  sessionExpired,
  permissionDenied,
  invalidMutation,
  invalidState,
  internal,
  unavailable,
}

final class SupplierImportMutationFailure implements Exception {
  const SupplierImportMutationFailure(this.kind);

  final SupplierImportMutationFailureKind kind;

  String get userMessage => switch (kind) {
    SupplierImportMutationFailureKind.sessionExpired =>
      'Your session has expired. Please sign in again.',
    SupplierImportMutationFailureKind.permissionDenied =>
      'You do not have access to update this Supplier Import review.',
    SupplierImportMutationFailureKind.invalidMutation =>
      'This Supplier Import review change is invalid.',
    SupplierImportMutationFailureKind.invalidState =>
      'This Supplier Import review cannot be changed in its current state.',
    SupplierImportMutationFailureKind.internal =>
      'The Supplier Import review could not be updated.',
    SupplierImportMutationFailureKind.unavailable =>
      'The change could not be confirmed. You can safely retry the same change.',
  };

  @override
  String toString() => userMessage;
}

abstract interface class SupplierImportResolutionMutationClient {
  Future<SupplierImportResolutionMutationOutcome> execute(
    SupplierImportResolutionMutationRequest request,
  );
}

final class CallableSupplierImportResolutionMutationClient
    implements SupplierImportResolutionMutationClient {
  CallableSupplierImportResolutionMutationClient({
    FirebaseFunctions? functions,
    FirebaseFunctions Function(String region)? functionsForRegion,
  }) : _functions =
           functions ??
           functionsForRegion?.call(region) ??
           FirebaseFunctions.instanceFor(region: region);

  static const region = 'asia-south2';
  static const functionName = 'applySupplierImportResolutionMutation';

  final FirebaseFunctions _functions;

  @override
  Future<SupplierImportResolutionMutationOutcome> execute(
    SupplierImportResolutionMutationRequest request,
  ) async {
    try {
      final response = await _functions
          .httpsCallable(functionName)
          .call<Object?>(request.toMap());
      return SupplierImportResolutionMutationOutcome.fromMap(response.data);
    } on FirebaseFunctionsException catch (error) {
      throw SupplierImportMutationFailure(_failureKind(error.code));
    } on SupplierImportMutationFailure {
      rethrow;
    } catch (_) {
      throw const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.unavailable,
      );
    }
  }
}

SupplierImportMutationFailureKind _failureKind(String code) => switch (code) {
  'unauthenticated' => SupplierImportMutationFailureKind.sessionExpired,
  'permission-denied' => SupplierImportMutationFailureKind.permissionDenied,
  'invalid-argument' => SupplierImportMutationFailureKind.invalidMutation,
  'failed-precondition' => SupplierImportMutationFailureKind.invalidState,
  'internal' => SupplierImportMutationFailureKind.internal,
  'unavailable' ||
  'deadline-exceeded' => SupplierImportMutationFailureKind.unavailable,
  _ => SupplierImportMutationFailureKind.unavailable,
};
