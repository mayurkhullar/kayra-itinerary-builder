const serviceTypes = [
  "hotel",
  "transfer",
  "activity",
  "meal",
  "sightseeing",
  "free_time",
  "other",
] as const;

const statementCategories = [
  "accommodation",
  "meal",
  "guide",
  "water",
  "entrance",
  "transport",
  "visa",
  "other",
] as const;

const conditionKinds = [
  "operating_basis",
  "vehicle",
  "class",
  "ticket_scope",
  "availability",
  "payment_basis",
  "guide",
  "other",
] as const;

const sourceLocator = {
  type: "object",
  additionalProperties: false,
  properties: {
    fileIndex: {type: "integer", minimum: 1},
    sourceLabel: {type: "string"},
  },
  propertyOrdering: ["fileIndex", "sourceLabel"],
};

const sourceLocators = {
  type: "array",
  minItems: 1,
  items: {$ref: "#/$defs/sourceLocator"},
};

const hotelDetails = {
  type: "object",
  additionalProperties: false,
  properties: {
    hotelName: {type: "string"},
    city: {type: "string"},
    orSimilar: {type: "boolean"},
    checkInDate: {type: "string", format: "date"},
    checkOutDate: {type: "string", format: "date"},
    nightCount: {type: "integer", minimum: 1},
    roomType: {type: "string"},
    mealPlan: {type: "string"},
    numberOfRooms: {type: "integer", minimum: 1},
    supplierStarRating: {type: "string"},
  },
  propertyOrdering: [
    "hotelName",
    "city",
    "orSimilar",
    "checkInDate",
    "checkOutDate",
    "nightCount",
    "roomType",
    "mealPlan",
    "numberOfRooms",
    "supplierStarRating",
  ],
};

const statement = {
  type: "object",
  additionalProperties: false,
  properties: {
    category: {type: "string", enum: [...statementCategories]},
    text: {type: "string"},
    quantity: {type: "integer", minimum: 1},
    frequency: {type: "string"},
    appliesTo: {
      type: "array",
      items: {type: "string", enum: [...serviceTypes]},
    },
    sources: sourceLocators,
  },
  required: ["category", "text"],
  propertyOrdering: [
    "category", "text", "quantity", "frequency", "appliesTo", "sources",
  ],
};

const condition = {
  type: "object",
  additionalProperties: false,
  properties: {
    kind: {type: "string", enum: [...conditionKinds]},
    value: {type: "string"},
    sources: sourceLocators,
  },
  required: ["kind", "value"],
  propertyOrdering: ["kind", "value", "sources"],
};

const service = {
  type: "object",
  additionalProperties: false,
  properties: {
    type: {type: "string", enum: [...serviceTypes]},
    title: {type: "string"},
    description: {type: "string"},
    startTime: {type: "string"},
    endTime: {type: "string"},
    location: {type: "string"},
    city: {type: "string"},
    inclusions: {type: "array", items: {$ref: "#/$defs/statement"}},
    exclusions: {type: "array", items: {$ref: "#/$defs/statement"}},
    conditions: {type: "array", items: {$ref: "#/$defs/condition"}},
    notes: {type: "string"},
    hotelDetails: {$ref: "#/$defs/hotelDetails"},
    transferDetails: {
      type: "object",
      additionalProperties: false,
      properties: {
        pickup: {type: "string"},
        dropoff: {type: "string"},
        vehicleType: {type: "string"},
        transferType: {
          type: "string",
          enum: ["private", "shared", "scheduled", "other"],
        },
      },
      propertyOrdering: ["pickup", "dropoff", "vehicleType", "transferType"],
    },
    activityDetails: {
      type: "object",
      additionalProperties: false,
      properties: {
        activityName: {type: "string"},
        duration: {type: "string"},
        activityType: {type: "string"},
      },
      propertyOrdering: ["activityName", "duration", "activityType"],
    },
    sources: sourceLocators,
  },
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
    "conditions",
    "description",
    "notes",
    "sources",
  ],
};

const reviewTarget = {
  type: "object",
  additionalProperties: false,
  properties: {
    kind: {
      type: "string",
      enum: ["snapshot", "day", "service", "package_fact", "ancillary_fact"],
    },
    dayIndex: {type: "integer", minimum: 1},
    scope: {type: "string", enum: ["day", "unassigned"]},
    serviceIndex: {type: "integer", minimum: 1},
    factType: {
      type: "string",
      enum: [
        "accommodation", "inclusion", "exclusion", "condition", "flight", "visa",
      ],
    },
    factIndex: {type: "integer", minimum: 1},
  },
  required: ["kind"],
  propertyOrdering: [
    "kind", "scope", "dayIndex", "serviceIndex", "factType", "factIndex",
  ],
};

/**
 * Future Gemini response schema only. It is deliberately not imported by the
 * production V2.4 provider until the staging workflow is ready end to end.
 */
export const kayraSupplierExtractionV3ResponseSchema = {
  $id: "kayra_itinerary_extraction_v3_staging",
  type: "object",
  additionalProperties: false,
  $defs: {
    sourceLocator,
    hotelDetails,
    statement,
    condition,
    service,
    reviewTarget,
  },
  properties: {
    title: {
      type: "object",
      additionalProperties: false,
      properties: {
        text: {type: "string"},
        basis: {
          type: "string",
          enum: ["explicit_supplier", "neutral_supported"],
        },
        sources: sourceLocators,
      },
      required: ["text", "basis"],
      propertyOrdering: ["text", "basis", "sources"],
    },
    days: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          sourceDayNumber: {type: "integer", minimum: 1},
          date: {type: "string", format: "date"},
          title: {type: "string"},
          summary: {type: "string"},
          notes: {type: "string"},
          services: {type: "array", items: {$ref: "#/$defs/service"}},
          sources: sourceLocators,
        },
        propertyOrdering: [
          "sourceDayNumber", "date", "title", "summary", "services", "notes",
          "sources",
        ],
      },
    },
    unassignedServices: {
      type: "array",
      items: {$ref: "#/$defs/service"},
    },
    packageFacts: {
      type: "object",
      additionalProperties: false,
      properties: {
        accommodations: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              ...hotelDetails.properties,
              sources: sourceLocators,
            },
            propertyOrdering: [...hotelDetails.propertyOrdering, "sources"],
          },
        },
        inclusions: {type: "array", items: {$ref: "#/$defs/statement"}},
        exclusions: {type: "array", items: {$ref: "#/$defs/statement"}},
        conditions: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              kind: {type: "string", enum: [...conditionKinds]},
              value: {type: "string"},
              appliesTo: {
                type: "array",
                items: {type: "string", enum: [...serviceTypes]},
              },
              sources: sourceLocators,
            },
            required: ["kind", "value"],
            propertyOrdering: ["kind", "value", "appliesTo", "sources"],
          },
        },
      },
      propertyOrdering: ["accommodations", "inclusions", "exclusions", "conditions"],
    },
    ancillaryFacts: {
      type: "object",
      additionalProperties: false,
      properties: {
        flights: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              airline: {type: "string"},
              flightNumber: {type: "string"},
              origin: {type: "string"},
              destination: {type: "string"},
              departureDate: {type: "string", format: "date"},
              departureTime: {type: "string"},
              arrivalDate: {type: "string", format: "date"},
              arrivalTime: {type: "string"},
              cabinClass: {type: "string"},
              bookingClass: {type: "string"},
              notes: {type: "string"},
              conditions: {
                type: "array",
                items: {$ref: "#/$defs/condition"},
              },
              sources: sourceLocators,
            },
            propertyOrdering: [
              "airline", "flightNumber", "origin", "destination",
              "departureDate", "departureTime", "arrivalDate", "arrivalTime",
              "cabinClass", "bookingClass", "conditions", "notes", "sources",
            ],
          },
        },
        visas: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              disposition: {
                type: "string",
                enum: ["included", "excluded", "requirement", "mentioned", "unclear"],
              },
              text: {type: "string"},
              sources: sourceLocators,
            },
            required: ["disposition"],
            propertyOrdering: ["disposition", "text", "sources"],
          },
        },
      },
      propertyOrdering: ["flights", "visas"],
    },
    commercialContent: {
      type: "object",
      additionalProperties: false,
      properties: {
        present: {type: "boolean"},
        categories: {
          type: "array",
          items: {
            type: "string",
            enum: [
              "package_price",
              "per_person_price",
              "supplement",
              "visa_price",
              "payment_terms",
              "other_commercial_terms",
            ],
          },
        },
        sources: sourceLocators,
      },
      required: ["present"],
      propertyOrdering: ["present", "categories", "sources"],
    },
    reviewIssues: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          code: {
            type: "string",
            enum: [
              "chronology_unknown",
              "accommodation_span_unknown",
              "classification_ambiguous",
              "conflicting_dates",
              "global_mapping_required",
              "source_conflict",
              "other",
            ],
          },
          severity: {type: "string", enum: ["warning", "blocker"]},
          message: {type: "string"},
          target: {$ref: "#/$defs/reviewTarget"},
          resolutionRequired: {type: "boolean"},
          structureBasis: {type: "string", enum: ["absence_only", "explicit_relationship"]},
          sources: sourceLocators,
        },
        required: [
          "code", "severity", "message", "target", "resolutionRequired",
        ],
        propertyOrdering: [
          "code", "severity", "message", "target", "resolutionRequired", "structureBasis", "sources",
        ],
      },
    },
  },
  propertyOrdering: [
    "title",
    "days",
    "unassignedServices",
    "packageFacts",
    "ancillaryFacts",
    "commercialContent",
    "reviewIssues",
  ],
};
