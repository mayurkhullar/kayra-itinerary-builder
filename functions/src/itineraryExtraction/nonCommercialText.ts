// The shared value boundary is deliberately independent of schema-specific
// restrictions on value-free commercial wording. Detection never rewrites text.
const currencyCodes = [
  "INR", "USD", "EUR", "GBP", "AED", "SGD", "MYR", "THB", "CNY", "RMB",
  "JPY", "AUD", "CAD", "CHF", "HKD", "IDR", "VND", "NPR", "LKR",
  "NZD", "KRW", "PHP", "MVR", "BTN", "BDT", "PKR", "SAR", "QAR",
  "OMR", "BHD", "KWD", "ZAR", "EGP", "MUR", "SCR", "KES",
];
const currency = `(?:${currencyCodes.join("|")}|rupees?|dollars?|euros?|dirhams?|yen|yuan|baht|ringgit)`;
const amount = "\\d+(?:[,.]\\d+)*";
const separator = "[\\s:=\\-–—]*";
// Unicode letter boundaries prevent codes inside destination/hotel names from
// matching; compact forms such as INR25000 and 500CNY still match.
const currencyAmount = new RegExp([
  `(?<![\\p{L}\\p{N}_])${currency}${separator}${amount}(?![\\p{L}\\p{N}_])`,
  `(?<![\\p{L}\\p{N}_])${amount}${separator}${currency}(?![\\p{L}\\p{N}_])`,
  `\\p{Sc}${separator}${amount}`,
  `${amount}${separator}\\p{Sc}`,
].join("|"), "iu");
const commercialConcept = "(?:commissions?|mark[ -]?ups?|margins?|discounts?|" +
  "supplements?|surcharges?|prices?|pricing|costs?|rates?|totals?|amounts?|" +
  "deposits?|payments?|fares?|fees?|charges?|payable|balance)";
// Bounded same-clause context permits labels such as "price per adult" and
// reverse forms such as "12 percent commission", without treating bare numbers
// or percentages as commercial. Decimal/grouping separators belong to amount.
const commercialValue = new RegExp([
  `\\b${commercialConcept}\\b[^\\d.!?;]{0,64}${amount}`,
  `${amount}[^\\d.!?;]{0,64}\\b${commercialConcept}\\b`,
].join("|"), "iu");
const commercialTermPattern = /\b(?:price|amount|currency|supplement|markup|margin|discount|payment)\b/iu;
const canonicalTermPattern = /\b(?:pricing|costs?|rates?|selling\s+price|payment\s+schedule)\b/iu;

/** One deterministic value predicate for all trusted V3/import boundaries.
 * This recognizes explicit monetary/value patterns, not arbitrary prose intent.
 * NFKC/whitespace normalization is detection-only; callers retain their input.
 */
export function containsCommercialValue(text: string): boolean {
  const detection = text.normalize("NFKC").replace(/\s+/gu, " ");
  return currencyAmount.test(detection) || commercialValue.test(detection);
}

/** Existing stricter, value-free schema policy; punctuation alone is not money. */
export function containsCommercialTerm(text: string, canonical = false): boolean {
  return commercialTermPattern.test(text) || canonical && canonicalTermPattern.test(text);
}
