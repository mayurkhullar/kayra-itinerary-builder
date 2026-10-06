part of 'itinerary_draft_v2.dart';

const _hotelFields = {
  ItineraryDraftV2Field.hotelName,
  ItineraryDraftV2Field.city,
  ItineraryDraftV2Field.orSimilar,
  ItineraryDraftV2Field.checkInDate,
  ItineraryDraftV2Field.checkOutDate,
  ItineraryDraftV2Field.nightCount,
  ItineraryDraftV2Field.roomType,
  ItineraryDraftV2Field.mealPlan,
  ItineraryDraftV2Field.numberOfRooms,
  ItineraryDraftV2Field.supplierStarRating,
};
const _statementFields = {
  ItineraryDraftV2Field.category,
  ItineraryDraftV2Field.text,
  ItineraryDraftV2Field.quantity,
  ItineraryDraftV2Field.frequency,
  ItineraryDraftV2Field.appliesTo,
};
const _conditionFields = {
  ItineraryDraftV2Field.kind,
  ItineraryDraftV2Field.value,
  ItineraryDraftV2Field.appliesTo,
};

enum ItineraryDraftV2AccommodationSelection { single, alternatives }

final class ItineraryDraftV2HotelDetails {
  const ItineraryDraftV2HotelDetails._(
    this.hotelName,
    this.city,
    this.orSimilar,
    this.checkInDate,
    this.checkOutDate,
    this.nightCount,
    this.roomType,
    this.mealPlan,
    this.numberOfRooms,
    this.supplierStarRating,
  );
  factory ItineraryDraftV2HotelDetails._parse(Object? value) {
    final m = _V2.record(value, _hotelFields.map((f) => f.name).toSet());
    final start = _V2.packageDate(m['checkInDate']),
        end = _V2.packageDate(m['checkOutDate']);
    final nights = _V2.nullablePositive(m['nightCount']);
    _V2.range(start, end);
    if (start != null &&
        end != null &&
        nights != null &&
        DateTime.parse(
              '${end}T00:00:00Z',
            ).difference(DateTime.parse('${start}T00:00:00Z')).inDays !=
            nights) {
      _V2.invalid();
    }
    final similar = m['orSimilar'];
    if (similar != null && similar is! bool) _V2.invalid();
    if (m.values.every((v) => v == null)) _V2.invalid();
    return ItineraryDraftV2HotelDetails._(
      _V2.nullableText(m['hotelName']),
      _V2.nullableText(m['city']),
      similar as bool?,
      start,
      end,
      nights,
      _V2.nullableText(m['roomType']),
      _V2.nullableText(m['mealPlan']),
      _V2.nullablePositive(m['numberOfRooms']),
      _V2.nullableText(m['supplierStarRating']),
    );
  }
  final String? hotelName,
      city,
      checkInDate,
      checkOutDate,
      roomType,
      mealPlan,
      supplierStarRating;
  final bool? orSimilar;
  final int? nightCount, numberOfRooms;
}

final class ItineraryDraftV2AccommodationOption {
  const ItineraryDraftV2AccommodationOption._(
    this.id,
    this.order,
    this.details,
    this.provenance,
  );
  final String id;
  final int order;
  final ItineraryDraftV2HotelDetails details;
  final ItineraryDraftV2Provenance provenance;
}

final class ItineraryDraftV2Accommodation {
  const ItineraryDraftV2Accommodation._(
    this.id,
    this.order,
    this.selection,
    this.options,
  );
  factory ItineraryDraftV2Accommodation._parse(
    Object? value,
    int index,
    ItineraryDraftV2ImportResult imported,
  ) {
    final m = _V2.record(value, {'id', 'order', 'selection', 'options'});
    final selection = _V2.enumeration(
      m['selection'],
      ItineraryDraftV2AccommodationSelection.values,
      (v) => v.name,
    );
    var position = 0;
    final options = _V2.list(m['options'], (value) {
      final o = _V2.record(value, {'id', 'order', 'details', 'provenance'});
      return ItineraryDraftV2AccommodationOption._(
        _V2.id(o['id']),
        _V2.position(o['order'], position++),
        ItineraryDraftV2HotelDetails._parse(o['details']),
        ItineraryDraftV2Provenance._parse(
          o['provenance'],
          imported,
          _hotelFields,
          _hotelFields,
        ),
      );
    });
    if ((selection == ItineraryDraftV2AccommodationSelection.single &&
            options.length != 1) ||
        (selection == ItineraryDraftV2AccommodationSelection.alternatives &&
            options.length < 2)) {
      _V2.invalid();
    }
    return ItineraryDraftV2Accommodation._(
      _V2.id(m['id']),
      _V2.position(m['order'], index),
      selection,
      options,
    );
  }
  final String id;
  final int order;
  final ItineraryDraftV2AccommodationSelection selection;
  final List<ItineraryDraftV2AccommodationOption> options;
}

/// Same typed statement contract, held in separate inclusion/exclusion arrays.
final class ItineraryDraftV2Statement {
  const ItineraryDraftV2Statement._(
    this.id,
    this.order,
    this.category,
    this.text,
    this.quantity,
    this.frequency,
    this.appliesTo,
    this.provenance,
  );
  factory ItineraryDraftV2Statement._parse(
    Object? value,
    int index,
    ItineraryDraftV2ImportResult imported,
  ) {
    final m = _V2.record(value, {
      'id',
      'order',
      'category',
      'text',
      'quantity',
      'frequency',
      'appliesTo',
      'provenance',
    });
    return ItineraryDraftV2Statement._(
      _V2.id(m['id']),
      _V2.position(m['order'], index),
      _V2.enumeration(
        m['category'],
        SupplierExtractionStatementCategory.values,
        (v) => v.value,
      ),
      _V2.text(m['text']),
      _V2.nullablePositive(m['quantity']),
      _V2.nullableText(m['frequency']),
      _V2.appliesTo(m['appliesTo']),
      ItineraryDraftV2Provenance._parse(
        m['provenance'],
        imported,
        _statementFields,
        {
          ItineraryDraftV2Field.quantity,
          ItineraryDraftV2Field.frequency,
          ItineraryDraftV2Field.appliesTo,
        },
      ),
    );
  }
  final String id, text;
  final int order;
  final SupplierExtractionStatementCategory category;
  final int? quantity;
  final String? frequency;
  final List<KayraItineraryServiceType> appliesTo;
  final ItineraryDraftV2Provenance provenance;
}

final class ItineraryDraftV2Condition {
  const ItineraryDraftV2Condition._(
    this.id,
    this.order,
    this.kind,
    this.value,
    this.appliesTo,
    this.provenance,
  );
  factory ItineraryDraftV2Condition._parse(
    Object? value,
    int index,
    ItineraryDraftV2ImportResult imported,
  ) {
    final m = _V2.record(value, {
      'id',
      'order',
      'kind',
      'value',
      'appliesTo',
      'provenance',
    });
    final kind = _V2.enumeration(
      m['kind'],
      SupplierExtractionConditionKind.values,
      (v) => v.value,
    );
    return ItineraryDraftV2Condition._(
      _V2.id(m['id']),
      _V2.position(m['order'], index),
      kind,
      _V2.text(
        m['value'],
        directPayment: kind == SupplierExtractionConditionKind.paymentBasis,
      ),
      _V2.appliesTo(m['appliesTo']),
      ItineraryDraftV2Provenance._parse(
        m['provenance'],
        imported,
        _conditionFields,
        {ItineraryDraftV2Field.appliesTo},
      ),
    );
  }
  final String id, value;
  final int order;
  final SupplierExtractionConditionKind kind;
  final List<KayraItineraryServiceType> appliesTo;
  final ItineraryDraftV2Provenance provenance;
}

final class ItineraryDraftV2PackageContent {
  const ItineraryDraftV2PackageContent._(
    this.accommodations,
    this.inclusions,
    this.exclusions,
    this.conditions,
  );
  factory ItineraryDraftV2PackageContent._parse(
    Object? value,
    ItineraryDraftV2ImportResult imported,
  ) {
    final m = _V2.record(value, {
      'accommodations',
      'inclusions',
      'exclusions',
      'conditions',
    });
    List<T> ordered<T>(
      String key,
      T Function(Object?, int, ItineraryDraftV2ImportResult) parse,
    ) {
      var index = 0;
      return _V2.list(m[key], (v) => parse(v, index++, imported));
    }

    final accommodations = ordered(
      'accommodations',
      ItineraryDraftV2Accommodation._parse,
    );
    final inclusions = ordered('inclusions', ItineraryDraftV2Statement._parse);
    final exclusions = ordered('exclusions', ItineraryDraftV2Statement._parse);
    final conditions = ordered('conditions', ItineraryDraftV2Condition._parse);
    final count =
        accommodations.length +
        inclusions.length +
        exclusions.length +
        conditions.length +
        accommodations.fold<int>(0, (count, a) => count + a.options.length);
    if (count > 256) _V2.invalid();
    return ItineraryDraftV2PackageContent._(
      accommodations,
      inclusions,
      exclusions,
      conditions,
    );
  }
  final List<ItineraryDraftV2Accommodation> accommodations;
  final List<ItineraryDraftV2Statement> inclusions, exclusions;
  final List<ItineraryDraftV2Condition> conditions;
}
