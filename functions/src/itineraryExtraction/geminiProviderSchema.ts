export const geminiServiceTypes = [
  "hotel",
  "transfer",
  "activity",
  "meal",
  "sightseeing",
  "free_time",
  "other",
] as const;

export const geminiTransferTypes = [
  "private",
  "shared",
  "scheduled",
  "other",
] as const;

export const geminiReviewSeverities = ["warning", "blocker"] as const;

const nullableString = {
  anyOf: [{type: "string"}, {type: "null"}],
};

const nullableDate = {
  anyOf: [{type: "string", format: "date"}, {type: "null"}],
};

const hotelDetails = {
  type: "object",
  additionalProperties: false,
  properties: {
    hotelName: {type: "string"},
    checkInDate: nullableDate,
    checkOutDate: nullableDate,
    roomType: nullableString,
    mealPlan: nullableString,
    numberOfRooms: {
      anyOf: [{type: "integer", minimum: 1}, {type: "null"}],
    },
    supplierStarRating: nullableString,
  },
  required: [
    "hotelName",
    "checkInDate",
    "checkOutDate",
    "roomType",
    "mealPlan",
    "numberOfRooms",
    "supplierStarRating",
  ],
};

const transferDetails = {
  type: "object",
  additionalProperties: false,
  properties: {
    pickup: {type: "string"},
    dropoff: {type: "string"},
    vehicleType: nullableString,
    transferType: {
      anyOf: [
        {type: "string", enum: [...geminiTransferTypes]},
        {type: "null"},
      ],
    },
  },
  required: ["pickup", "dropoff", "vehicleType", "transferType"],
};

const activityDetails = {
  type: "object",
  additionalProperties: false,
  properties: {
    activityName: {type: "string"},
    duration: nullableString,
    activityType: nullableString,
  },
  required: ["activityName", "duration", "activityType"],
};

const sourceReference = {
  type: "object",
  additionalProperties: false,
  properties: {
    supplierSourcePackageId: {type: "string"},
    supplierSourceFileId: nullableString,
    sourceLabel: nullableString,
  },
  required: [
    "supplierSourcePackageId",
    "supplierSourceFileId",
    "sourceLabel",
  ],
};

const service = {
  type: "object",
  additionalProperties: false,
  properties: {
    id: {type: "string"},
    type: {type: "string", enum: [...geminiServiceTypes]},
    title: {type: "string"},
    description: nullableString,
    startTime: nullableString,
    endTime: nullableString,
    location: nullableString,
    city: nullableString,
    inclusions: {type: "array", items: {type: "string"}},
    exclusions: {type: "array", items: {type: "string"}},
    notes: nullableString,
    hotelDetails: {anyOf: [hotelDetails, {type: "null"}]},
    transferDetails: {anyOf: [transferDetails, {type: "null"}]},
    activityDetails: {anyOf: [activityDetails, {type: "null"}]},
    sourceReference: {anyOf: [sourceReference, {type: "null"}]},
  },
  required: [
    "id",
    "type",
    "title",
    "description",
    "startTime",
    "endTime",
    "location",
    "city",
    "inclusions",
    "exclusions",
    "notes",
    "hotelDetails",
    "transferDetails",
    "activityDetails",
    "sourceReference",
  ],
};

const day = {
  type: "object",
  additionalProperties: false,
  properties: {
    dayNumber: {type: "integer", minimum: 1},
    date: nullableDate,
    title: {type: "string"},
    summary: nullableString,
    services: {type: "array", items: service},
    notes: nullableString,
  },
  required: ["dayNumber", "date", "title", "summary", "services", "notes"],
};

const reviewIssue = {
  type: "object",
  additionalProperties: false,
  properties: {
    id: {type: "string"},
    fieldPath: {type: "string"},
    message: {type: "string"},
    severity: {type: "string", enum: [...geminiReviewSeverities]},
  },
  required: ["id", "fieldPath", "message", "severity"],
};

export const kayraItineraryExtractionResponseSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    title: {type: "string"},
    days: {type: "array", items: day},
    reviewIssues: {type: "array", items: reviewIssue},
  },
  required: ["title", "days", "reviewIssues"],
  propertyOrdering: ["title", "days", "reviewIssues"],
};
