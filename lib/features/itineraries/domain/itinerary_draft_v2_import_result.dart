part of 'itinerary_draft_v2.dart';

final class ItineraryDraftV2ImportResult {
  ItineraryDraftV2ImportResult._(
    this.extractionId,
    this.resolutionId,
    this.evaluatedRevision,
    this.sourcePackageId,
    this.finalizationId,
  );
  factory ItineraryDraftV2ImportResult._parse(Object? input) {
    final m = _V2.record(input, {
      'extractionId',
      'resolutionId',
      'evaluatedRevision',
      'sourcePackageId',
      'finalizationId',
      'policyVersion',
    });
    final extraction = _V2.id(m['extractionId']),
        resolution = _V2.id(m['resolutionId']);
    final finalization = _V2.id(m['finalizationId']);
    if (extraction != resolution ||
        finalization.length > 128 ||
        m['policyVersion'] != itineraryDraftV2ImportPolicy) {
      _V2.invalid();
    }
    return ItineraryDraftV2ImportResult._(
      extraction,
      resolution,
      _V2.positive(m['evaluatedRevision']),
      _V2.id(m['sourcePackageId']),
      finalization,
    );
  }
  final String extractionId, resolutionId, sourcePackageId, finalizationId;
  final int evaluatedRevision;
  String get policyVersion => itineraryDraftV2ImportPolicy;
}
