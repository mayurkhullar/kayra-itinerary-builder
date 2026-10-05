import 'dart:math';

import 'supplier_import_resolution_decision.dart';
import 'supplier_import_resolution_manual_item.dart';
import 'supplier_import_resolution_parsing.dart';

sealed class SupplierImportResolutionMutationCommand {
  const SupplierImportResolutionMutationCommand();
  String get action;
  Map<String, Object?> toMap();
}

final class SupplierImportStartReviewCommand
    extends SupplierImportResolutionMutationCommand {
  const SupplierImportStartReviewCommand();
  @override
  String get action => 'start_review';
  @override
  Map<String, Object?> toMap() => {'action': action};
}

final class SupplierImportSetDecisionCommand
    extends SupplierImportResolutionMutationCommand {
  const SupplierImportSetDecisionCommand(this.decision);
  final SupplierImportDecisionPayload decision;
  @override
  String get action => 'set_decision';
  @override
  Map<String, Object?> toMap() => {
    'action': action,
    'decision': decision.toMutationMap(),
  };
}

final class SupplierImportRemoveDecisionCommand
    extends SupplierImportResolutionMutationCommand {
  SupplierImportRemoveDecisionCommand(String decisionId)
    : decisionId = SupplierImportResolutionParsing.id(decisionId, 'Decision');
  final String decisionId;
  @override
  String get action => 'remove_decision';
  @override
  Map<String, Object?> toMap() => {'action': action, 'decisionId': decisionId};
}

final class SupplierImportUpsertManualItemCommand
    extends SupplierImportResolutionMutationCommand {
  const SupplierImportUpsertManualItemCommand(this.item);
  final SupplierImportManualItemPayload item;
  @override
  String get action => 'upsert_manual_item';
  @override
  Map<String, Object?> toMap() => {
    'action': action,
    'item': item.toMutationMap(),
  };
}

final class SupplierImportRemoveManualItemCommand
    extends SupplierImportResolutionMutationCommand {
  SupplierImportRemoveManualItemCommand(String manualItemId)
    : manualItemId = SupplierImportResolutionParsing.id(
        manualItemId,
        'Manual item',
      );
  final String manualItemId;
  @override
  String get action => 'remove_manual_item';
  @override
  Map<String, Object?> toMap() => {
    'action': action,
    'manualItemId': manualItemId,
  };
}

final class SupplierImportResolutionMutationRequest {
  SupplierImportResolutionMutationRequest({
    required String tripId,
    required String extractionId,
    required this.expectedRevision,
    required String commandId,
    required this.mutation,
  }) : tripId = SupplierImportResolutionParsing.id(tripId, 'Trip'),
       extractionId = SupplierImportResolutionParsing.id(
         extractionId,
         'Extraction',
       ),
       commandId = _commandId(commandId) {
    if (expectedRevision < 0) {
      throw const FormatException('Expected revision cannot be negative.');
    }
  }

  factory SupplierImportResolutionMutationRequest.create({
    required String tripId,
    required String extractionId,
    required int expectedRevision,
    required SupplierImportResolutionMutationCommand mutation,
    SupplierImportCommandIdGenerator? commandIds,
  }) => SupplierImportResolutionMutationRequest(
    tripId: tripId,
    extractionId: extractionId,
    expectedRevision: expectedRevision,
    commandId: (commandIds ?? SupplierImportCommandIdGenerator()).generate(),
    mutation: mutation,
  );

  final String tripId;
  final String extractionId;
  final int expectedRevision;
  final String commandId;
  final SupplierImportResolutionMutationCommand mutation;

  Map<String, Object?> toMap() => {
    'tripId': tripId,
    'extractionId': extractionId,
    'expectedRevision': expectedRevision,
    'commandId': commandId,
    'mutation': mutation.toMap(),
  };
}

final class SupplierImportCommandIdGenerator {
  SupplierImportCommandIdGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;
  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  String generate() => List.generate(
    24,
    (_) => _alphabet[_random.nextInt(_alphabet.length)],
    growable: false,
  ).join();
}

sealed class SupplierImportResolutionMutationOutcome {
  const SupplierImportResolutionMutationOutcome({required this.resolutionId});
  final String resolutionId;

  factory SupplierImportResolutionMutationOutcome.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.record(
      input,
      'Resolution mutation response',
    );
    return switch (data['outcome']) {
      'applied' => SupplierImportMutationApplied.fromMap(data),
      'already_applied' => SupplierImportMutationAlreadyApplied.fromMap(data),
      'resolution_conflict' => SupplierImportMutationConflict.fromMap(data),
      'resolution_not_started' => SupplierImportMutationNotStarted.fromMap(
        data,
      ),
      'resolution_finalized' => SupplierImportMutationFinalized.fromMap(data),
      _ => throw const FormatException('Mutation outcome is unsupported.'),
    };
  }
}

final class SupplierImportMutationApplied
    extends SupplierImportResolutionMutationOutcome {
  SupplierImportMutationApplied._({
    required super.resolutionId,
    required this.revision,
    required this.canFinalize,
    required this.blockerCount,
    required this.warningCount,
  });

  factory SupplierImportMutationApplied.fromMap(Map<String, Object?> input) {
    final data = SupplierImportResolutionParsing.exact(input, const {
      'outcome',
      'resolutionId',
      'revision',
      'status',
      'canFinalize',
      'blockerCount',
      'warningCount',
    }, 'Applied mutation response');
    if (data['status'] != 'active') {
      throw const FormatException('Applied mutation status is invalid.');
    }
    return SupplierImportMutationApplied._(
      resolutionId: SupplierImportResolutionParsing.id(
        data['resolutionId'],
        'Resolution',
      ),
      revision: SupplierImportResolutionParsing.positiveInt(
        data['revision'],
        'Resolution revision',
      ),
      canFinalize: SupplierImportResolutionParsing.boolean(
        data['canFinalize'],
        'Finalization readiness',
      ),
      blockerCount: SupplierImportResolutionParsing.nonNegativeInt(
        data['blockerCount'],
        'Blocker count',
      ),
      warningCount: SupplierImportResolutionParsing.nonNegativeInt(
        data['warningCount'],
        'Warning count',
      ),
    );
  }

  final int revision;
  final bool canFinalize;
  final int blockerCount;
  final int warningCount;
}

final class SupplierImportMutationAlreadyApplied
    extends SupplierImportResolutionMutationOutcome {
  SupplierImportMutationAlreadyApplied._({
    required super.resolutionId,
    required this.revision,
  });

  factory SupplierImportMutationAlreadyApplied.fromMap(
    Map<String, Object?> input,
  ) {
    final data = _revisionOutcome(input, 'already_applied');
    return SupplierImportMutationAlreadyApplied._(
      resolutionId: data.resolutionId,
      revision: data.revision,
    );
  }
  final int revision;
}

final class SupplierImportMutationNotStarted
    extends SupplierImportResolutionMutationOutcome {
  SupplierImportMutationNotStarted._({
    required super.resolutionId,
    required this.revision,
  });
  factory SupplierImportMutationNotStarted.fromMap(Map<String, Object?> input) {
    final data = _revisionOutcome(
      input,
      'resolution_not_started',
      allowZero: true,
    );
    return SupplierImportMutationNotStarted._(
      resolutionId: data.resolutionId,
      revision: data.revision,
    );
  }
  final int revision;
}

final class SupplierImportMutationFinalized
    extends SupplierImportResolutionMutationOutcome {
  SupplierImportMutationFinalized._({
    required super.resolutionId,
    required this.revision,
  });
  factory SupplierImportMutationFinalized.fromMap(Map<String, Object?> input) {
    final data = _revisionOutcome(input, 'resolution_finalized');
    return SupplierImportMutationFinalized._(
      resolutionId: data.resolutionId,
      revision: data.revision,
    );
  }
  final int revision;
}

final class SupplierImportMutationConflict
    extends SupplierImportResolutionMutationOutcome {
  SupplierImportMutationConflict._({
    required super.resolutionId,
    required this.currentRevision,
  });
  factory SupplierImportMutationConflict.fromMap(Map<String, Object?> input) {
    final data = SupplierImportResolutionParsing.exact(input, const {
      'outcome',
      'resolutionId',
      'currentRevision',
    }, 'Conflict mutation response');
    return SupplierImportMutationConflict._(
      resolutionId: SupplierImportResolutionParsing.id(
        data['resolutionId'],
        'Resolution',
      ),
      currentRevision: SupplierImportResolutionParsing.nonNegativeInt(
        data['currentRevision'],
        'Current revision',
      ),
    );
  }
  final int currentRevision;
}

({String resolutionId, int revision}) _revisionOutcome(
  Map<String, Object?> input,
  String outcome, {
  bool allowZero = false,
}) {
  final data = SupplierImportResolutionParsing.exact(input, const {
    'outcome',
    'resolutionId',
    'revision',
  }, 'Mutation response');
  if (data['outcome'] != outcome) {
    throw const FormatException('Mutation response outcome is invalid.');
  }
  return (
    resolutionId: SupplierImportResolutionParsing.id(
      data['resolutionId'],
      'Resolution',
    ),
    revision: allowZero
        ? SupplierImportResolutionParsing.nonNegativeInt(
            data['revision'],
            'Resolution revision',
          )
        : SupplierImportResolutionParsing.positiveInt(
            data['revision'],
            'Resolution revision',
          ),
  );
}

String _commandId(String value) {
  final id = SupplierImportResolutionParsing.id(value, 'Command');
  if (id.length > 128) {
    throw const FormatException('Command identity is too long.');
  }
  return id;
}
