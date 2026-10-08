import type {ReviewStructureBasis} from "./supplierExtractionSnapshot";

/** No default: historical ambiguous issues retain their original meaning. */
export function reviewStructureFields(data: Record<string, unknown>, invalid: (message: string) => never): {structureBasis?: ReviewStructureBasis} {
  if (!Object.prototype.hasOwnProperty.call(data, "structureBasis")) return {};
  if (!["chronology_unknown", "global_mapping_required", "accommodation_span_unknown"].includes(String(data.code)) ||
      !["absence_only", "explicit_relationship"].includes(String(data.structureBasis))) {
    return invalid("Invalid review structure evidence.");
  }
  return {structureBasis: data.structureBasis as ReviewStructureBasis};
}
