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

const source = {
  type: "object",
  additionalProperties: false,
  properties: {
    fileIndex: {type: "integer", minimum: 1},
    sourceLabel: {type: "string"},
  },
  propertyOrdering: ["fileIndex", "sourceLabel"],
};

const hotelDetails = {
  type: "object",
  additionalProperties: false,
  properties: {
    hotelName: {type: "string"},
    checkInDate: {type: "string", format: "date"},
    checkOutDate: {type: "string", format: "date"},
    roomType: {type: "string"},
    mealPlan: {type: "string"},
    numberOfRooms: {type: "integer", minimum: 1},
    supplierStarRating: {type: "string"},
  },
  required: ["hotelName"],
  propertyOrdering: [
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
    vehicleType: {type: "string"},
    transferType: {type: "string", enum: [...geminiTransferTypes]},
  },
  required: ["pickup", "dropoff"],
  propertyOrdering: [
    "pickup",
    "dropoff",
    "vehicleType",
    "transferType",
  ],
};

const activityDetails = {
  type: "object",
  additionalProperties: false,
  properties: {
    activityName: {type: "string"},
    duration: {type: "string"},
    activityType: {type: "string"},
  },
  required: ["activityName"],
  propertyOrdering: ["activityName", "duration", "activityType"],
};

const service = {
  type: "object",
  additionalProperties: false,
  properties: {
    type: {type: "string", enum: [...geminiServiceTypes]},
    title: {type: "string"},
    description: {type: "string"},
    startTime: {type: "string"},
    endTime: {type: "string"},
    location: {type: "string"},
    city: {type: "string"},
    inclusions: {type: "array", items: {type: "string"}},
    exclusions: {type: "array", items: {type: "string"}},
    notes: {type: "string"},
    hotelDetails,
    transferDetails,
    activityDetails,
    source,
  },
  required: ["type"],
  propertyOrdering: [
    "type",
    "title",
    "hotelDetails",
    "transferDetails",
    "activityDetails",
    "startTime",
    "endTime",
    "location",
    "city",
    "inclusions",
    "exclusions",
    "description",
    "notes",
    "source",
  ],
};

const day = {
  type: "object",
  additionalProperties: false,
  properties: {
    date: {type: "string", format: "date"},
    title: {type: "string"},
    summary: {type: "string"},
    services: {type: "array", items: service},
    notes: {type: "string"},
  },
  required: ["title"],
  propertyOrdering: ["title", "date", "summary", "services", "notes"],
};

const reviewIssue = {
  type: "object",
  additionalProperties: false,
  properties: {
    fieldPath: {type: "string"},
    message: {type: "string"},
    severity: {type: "string", enum: [...geminiReviewSeverities]},
  },
  required: ["fieldPath", "message", "severity"],
  propertyOrdering: ["fieldPath", "message", "severity"],
};

export const kayraItineraryExtractionResponseSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    title: {type: "string"},
    days: {type: "array", items: day},
    reviewIssues: {type: "array", items: reviewIssue},
  },
  required: ["title", "days"],
  propertyOrdering: ["title", "days", "reviewIssues"],
};
