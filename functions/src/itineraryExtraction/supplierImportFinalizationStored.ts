import {Timestamp} from "firebase-admin/firestore";
import {ItineraryDraftV2} from "./itineraryDraftV2";
import {itineraryDraftV2ToMap, validateItineraryDraftV2} from "./itineraryDraftV2Validation";
import {SupplierImportFinalizationReceipt} from "./supplierImportFinalizationReceipt";
import {supplierImportFinalizationReceiptFromMap, supplierImportFinalizationReceiptToMap} from "./supplierImportFinalizationReceiptValidation";
import {InvalidFinalizationState} from "./supplierImportFinalization";
import {array} from "./itineraryDraftValidationPrimitives";

/** Serializers only: no independent draft/receipt write API. */
export function itineraryDraftV2ForFirestore(candidate: ItineraryDraftV2): Record<string, unknown> {
  const map = itineraryDraftV2ToMap(candidate);
  const stored = transformDraftDates(map, (value, dateOnly) => {
    if (typeof value !== "string") throw new InvalidFinalizationState();
    return Timestamp.fromDate(new Date(dateOnly ? `${value}T00:00:00.000Z` : value));
  });
  readStoredItineraryDraftV2(candidate.id, stored);
  return stored;
}

export function readStoredItineraryDraftV2(id: string, input: unknown): ItineraryDraftV2 {
  try {
    return validateItineraryDraftV2(id, transformDraftDates(input, (value, dateOnly) => {
      const iso = storedTimestampIso(value);
      if (dateOnly && !iso.endsWith("T00:00:00.000Z")) throw new InvalidFinalizationState();
      return dateOnly ? iso.slice(0, 10) : iso;
    }));
  } catch { throw new InvalidFinalizationState(); }
}

export function finalizationReceiptForFirestore(receipt: SupplierImportFinalizationReceipt): Record<string, unknown> {
  const map = supplierImportFinalizationReceiptToMap(receipt);
  const stored = {...map, finalizedAt: Timestamp.fromDate(receipt.finalizedAt)};
  readStoredFinalizationReceipt(stored);
  return stored;
}

export function readStoredFinalizationReceipt(input: unknown): SupplierImportFinalizationReceipt {
  try {
    const map = plainMap(input);
    return supplierImportFinalizationReceiptFromMap({...map, finalizedAt: storedTimestampIso(map.finalizedAt)});
  } catch { throw new InvalidFinalizationState(); }
}

function transformDraftDates(input: unknown, convert: (value: unknown, dateOnly: boolean) => unknown): Record<string, unknown> {
  const map = plainMap(input);
  const serviceDates = (item: unknown): Record<string, unknown> => {
    const service = plainMap(item);
    if (service.hotelDetails === null) return service;
    const hotel = plainMap(service.hotelDetails);
    return {...service, hotelDetails: {...hotel,
      checkInDate: hotel.checkInDate === null ? null : convert(hotel.checkInDate, true),
      checkOutDate: hotel.checkOutDate === null ? null : convert(hotel.checkOutDate, true),
    }};
  };
  return {...map,
    ...(Object.prototype.hasOwnProperty.call(map, "unscheduledServices") ? {
      unscheduledServices: array(map.unscheduledServices, "Stored unscheduled services").map(serviceDates),
    } : {}), createdAt: convert(map.createdAt, false), updatedAt: convert(map.updatedAt, false),
    days: array(map.days, "Stored days").map((value) => {
      const day = plainMap(value);
      return {...day, date: day.date === null ? null : convert(day.date, true),
        services: array(day.services, "Stored services").map(serviceDates),
      };
    }),
  };
}

export function storedTimestampIso(value: unknown): string {
  // Domain Dates are millisecond precision. Never silently discard sub-ms data.
  if (!(value instanceof Timestamp) || value.nanoseconds % 1000000 !== 0) throw new InvalidFinalizationState();
  return value.toDate().toISOString();
}

export function plainMap(input: unknown): Record<string, unknown> {
  if (!input || typeof input !== "object" || ![Object.prototype, null].includes(Object.getPrototypeOf(input))) throw new InvalidFinalizationState();
  for (const key of Reflect.ownKeys(input)) {
    const field = Object.getOwnPropertyDescriptor(input, key)!;
    if (typeof key !== "string" || !field.enumerable || !("value" in field)) throw new InvalidFinalizationState();
  }
  return input as Record<string, unknown>;
}

/** Existing Resolution timestamps are stored as Timestamp and become ISO in
 * its pure stored validator. This conversion never drops unknown fields. */
export function resolutionFromFirestore(input: unknown): unknown {
  if (input instanceof Timestamp) return storedTimestampIso(input);
  if (Array.isArray(input)) return array(input, "Stored Resolution array").map(resolutionFromFirestore);
  if (input === null || typeof input !== "object") return input;
  return Object.fromEntries(Object.entries(plainMap(input)).map(([key, value]) => [key, resolutionFromFirestore(value)]));
}
