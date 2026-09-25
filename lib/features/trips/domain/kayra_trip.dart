/// Stable persisted values are independent of Dart enum names and UI labels.
enum HotelCategory {
  threeStar('3_star', '3 Star'),
  fourStar('4_star', '4 Star'),
  fiveStar('5_star', '5 Star'),
  luxury('luxury', 'Luxury');

  const HotelCategory(this.value, this.label);
  final String value;
  final String label;

  static HotelCategory parse(Object? value) => values.firstWhere(
    (category) => category.value == value,
    orElse: () => throw const FormatException('Invalid hotel category.'),
  );
}

enum TripType {
  fit('fit', 'FIT'),
  business('business', 'Business'),
  corporate('corporate', 'Corporate'),
  groups('groups', 'Groups');

  const TripType(this.value, this.label);
  final String value;
  final String label;

  static TripType parse(Object? value) => values.firstWhere(
    (type) => type.value == value,
    orElse: () => throw const FormatException('Invalid trip type.'),
  );
}

enum TripStatus {
  draft('draft', 'Draft'),
  quotePrepared('quote_prepared', 'Quote Prepared'),
  sentToClient('sent_to_client', 'Sent to Client'),
  underDiscussion('under_discussion', 'Under Discussion'),
  revised('revised', 'Revised'),
  clientApproved('client_approved', 'Client Approved'),
  onHold('on_hold', 'On Hold'),
  confirmed('confirmed', 'Confirmed'),
  cancelled('cancelled', 'Cancelled'),
  lost('lost', 'Lost'),
  travelCompleted('travel_completed', 'Travel Completed');

  const TripStatus(this.value, this.label);
  final String value;
  final String label;

  static TripStatus parse(Object? value) => values.firstWhere(
    (status) => status.value == value,
    orElse: () => throw const FormatException('Invalid trip status.'),
  );
}

abstract final class TripValidation {
  static String id(String value) {
    if (value.isEmpty ||
        value.trim() != value ||
        value.contains('/') ||
        value == '.' ||
        value == '..') {
      throw const FormatException('Invalid trip, client or user identity.');
    }
    return value;
  }

  static String requiredText(String value, String label) {
    final text = value.trim();
    if (text.isEmpty) throw FormatException('$label is required.');
    return text;
  }

  static int count(int value, String label, {int minimum = 0}) {
    if (value < minimum) {
      throw FormatException('$label must be at least $minimum.');
    }
    return value;
  }

  static void clientCompany(TripType type, String? company) {
    if ((type == TripType.corporate || type == TripType.groups) &&
        (company == null || company.trim().isEmpty)) {
      throw const FormatException(
        'Client company is required for Corporate and Groups trips.',
      );
    }
  }
}

/// Only editable brief fields; no ownership, status, client link or audit data.
final class TripBrief {
  TripBrief({
    required List<String> destinations,
    required DateTime travelStartDate,
    required int numberOfNights,
    required int adults,
    required int children,
    required int infants,
    required this.hotelCategory,
    required this.tripType,
  }) : destinations = List.unmodifiable(
         destinations
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty),
       ),
       // Preserve the entered calendar day, not its local-time UTC conversion.
       travelStartDate = DateTime.utc(
         travelStartDate.year,
         travelStartDate.month,
         travelStartDate.day,
       ),
       numberOfNights = TripValidation.count(
         numberOfNights,
         'Number of nights',
         minimum: 1,
       ),
       adults = TripValidation.count(adults, 'Adults', minimum: 1),
       children = TripValidation.count(children, 'Children'),
       infants = TripValidation.count(infants, 'Infants') {
    if (this.destinations.isEmpty) {
      throw const FormatException('At least one destination is required.');
    }
  }

  final List<String> destinations;
  final DateTime travelStartDate;
  final int numberOfNights;
  final int adults;
  final int children;
  final int infants;
  final HotelCategory hotelCategory;
  final TripType tripType;

  DateTime get tripEndDate =>
      travelStartDate.add(Duration(days: numberOfNights));
  int get totalTravellerCount => adults + children + infants;

  void validateClientCompany(String? company) =>
      TripValidation.clientCompany(tripType, company);

  String tripNameFor(String firstName, String lastName) {
    final first = TripValidation.requiredText(firstName, 'Client first name');
    final last = TripValidation.requiredText(lastName, 'Client last name');
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '$first $last – ${destinations.join(' & ')} – ${months[travelStartDate.month - 1]} ${travelStartDate.year}';
  }

  /// The data layer converts the domain date into a Firestore Timestamp.
  Map<String, Object?> toMap() => {
    'destinations': destinations,
    'travelStartDate': travelStartDate,
    'numberOfNights': numberOfNights,
    'adults': adults,
    'children': children,
    'infants': infants,
    'hotelCategory': hotelCategory.value,
    'tripType': tripType.value,
  };

  factory TripBrief.fromMap(Map<String, Object?> data) {
    final destinations = data['destinations'];
    if (destinations is! List ||
        destinations.any((value) => value is! String)) {
      throw const FormatException('Invalid trip destinations.');
    }
    return TripBrief(
      destinations: destinations.cast<String>(),
      travelStartDate: _date(data['travelStartDate']),
      numberOfNights: _integer(data['numberOfNights']),
      adults: _integer(data['adults']),
      children: _integer(data['children']),
      infants: _integer(data['infants']),
      hotelCategory: HotelCategory.parse(data['hotelCategory']),
      tripType: TripType.parse(data['tripType']),
    );
  }
}

/// Persisted trip. Client identity and its creation-time name snapshot are fixed.
/// Company is checked against the Client on writes, never duplicated here.
final class KayraTrip {
  KayraTrip._({
    required String id,
    required String clientId,
    required String clientFirstName,
    required String clientLastName,
    required this.brief,
    required this.status,
    required String ownerUid,
    required String createdByUid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : id = TripValidation.id(id),
       clientId = TripValidation.id(clientId),
       clientFirstName = TripValidation.requiredText(
         clientFirstName,
         'Client first name',
       ),
       clientLastName = TripValidation.requiredText(
         clientLastName,
         'Client last name',
       ),
       ownerUid = TripValidation.id(ownerUid),
       createdByUid = TripValidation.id(createdByUid),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  /// Domain construction always starts Draft with one authenticated creator/owner.
  /// Repository creation supplies a verified Client and uses server audit times.
  factory KayraTrip.create({
    required String id,
    required String clientId,
    required String clientFirstName,
    required String clientLastName,
    required String? clientCompany,
    required TripBrief brief,
    required String currentUserUid,
    required DateTime createdAt,
  }) {
    brief.validateClientCompany(clientCompany);
    return KayraTrip._(
      id: id,
      clientId: clientId,
      clientFirstName: clientFirstName,
      clientLastName: clientLastName,
      brief: brief,
      status: TripStatus.draft,
      ownerUid: currentUserUid,
      createdByUid: currentUserUid,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  /// Strict domain parsing; the repository converts all Firestore timestamps first.
  factory KayraTrip.fromMap(
    Map<String, Object?> data, {
    required String documentId,
  }) {
    const fields = {
      'clientId',
      'clientFirstName',
      'clientLastName',
      'tripName',
      'destinations',
      'travelStartDate',
      'numberOfNights',
      'adults',
      'children',
      'infants',
      'hotelCategory',
      'tripType',
      'status',
      'ownerUid',
      'createdByUid',
      'createdAt',
      'updatedAt',
    };
    if (!fields.containsAll(data.keys) || !fields.every(data.containsKey)) {
      throw const FormatException('Incomplete or unsupported trip fields.');
    }
    final trip = KayraTrip._(
      id: documentId,
      clientId: _string(data['clientId']),
      clientFirstName: _string(data['clientFirstName']),
      clientLastName: _string(data['clientLastName']),
      brief: TripBrief.fromMap(data),
      status: TripStatus.parse(data['status']),
      ownerUid: _string(data['ownerUid']),
      createdByUid: _string(data['createdByUid']),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
    );
    if (data['tripName'] != trip.tripName) {
      throw const FormatException('Invalid generated trip name.');
    }
    return trip;
  }

  final String id;
  final String clientId;
  final String clientFirstName;
  final String clientLastName;
  final TripBrief brief;
  final TripStatus status;
  final String ownerUid;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get tripName => brief.tripNameFor(clientFirstName, clientLastName);
  List<String> get destinations => brief.destinations;
  DateTime get travelStartDate => brief.travelStartDate;
  int get numberOfNights => brief.numberOfNights;
  int get adults => brief.adults;
  int get children => brief.children;
  int get infants => brief.infants;
  HotelCategory get hotelCategory => brief.hotelCategory;
  TripType get tripType => brief.tripType;
  DateTime get tripEndDate => brief.tripEndDate;
  int get totalTravellerCount => brief.totalTravellerCount;

  Map<String, Object?> toMap() => {
    ...brief.toMap(),
    'clientId': clientId,
    'clientFirstName': clientFirstName,
    'clientLastName': clientLastName,
    'tripName': tripName,
    'status': status.value,
    'ownerUid': ownerUid,
    'createdByUid': createdByUid,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

String _string(Object? value) => switch (value) {
  String value => value,
  _ => throw const FormatException('Invalid required trip text.'),
};
int _integer(Object? value) => switch (value) {
  int value => value,
  _ => throw const FormatException('Invalid trip count.'),
};
DateTime _date(Object? value) => switch (value) {
  DateTime value => value,
  _ => throw const FormatException('Invalid trip date or timestamp.'),
};
