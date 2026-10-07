/// Labels only: never evaluates readiness or exposes backend/source text.
String finalizationFindingLabel(String code) => switch (code) {
  'resolution_already_finalized' => 'This itinerary is already finalized.',
  'missing_day_title' => 'A day needs a title.',
  'duplicate_day_order' => 'Days need a distinct order.',
  'unresolved_unassigned_service' ||
  'missing_service_day' => 'A service needs a day assignment.',
  'missing_service_order' || 'duplicate_service_order' =>
    'Services need a distinct order within their day.',
  'missing_service_type' => 'A service needs a type.',
  'missing_service_title' => 'A service needs a title.',
  'missing_required_service_details' => 'A service needs more details.',
  'unsupported_service_content' => 'A service needs a review decision.',
  'unresolved_package_accommodation' => 'Hotel information needs review.',
  'incomplete_package_accommodation' => 'Hotel information is incomplete.',
  'unsupported_package_accommodation_content' =>
    'Hotel information needs a review decision.',
  'package_level_destination_unavailable' || 'unsupported_package_mapping' =>
    'Package information cannot yet be included safely.',
  'unresolved_package_fact' => 'A package detail needs review.',
  'unresolved_ancillary_fact' =>
    'An additional travel item needs a review decision.',
  'unresolved_review_issue' ||
  'structural_review_issue_unresolved' => 'A review issue needs attention.',
  'invalid_snapshot' => 'The extracted content could not be used safely.',
  'invalid_resolution' => 'The review could not be used safely.',
  'invalid_assembly_context' || 'canonical_validation_failed' =>
    'The itinerary could not be finalized safely.',
  'package_record_limit_exceeded' =>
    'There is too much package information to finalize safely.',
  'snapshot_warning_open' => 'An extraction warning remains open.',
  'snapshot_warning_acknowledged' =>
    'An extraction warning was previously reviewed.',
  'review_issue_overridden' => 'A review issue has an override.',
  _ => 'This item needs review before finalizing.',
};
