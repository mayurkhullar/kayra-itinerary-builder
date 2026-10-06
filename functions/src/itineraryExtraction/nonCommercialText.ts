// Shared pure predicates. Keep the two existing policies distinct: extraction
// permits operational qualifiers; consultant overrides use a stricter vocabulary.
const currencyCode = "(?:INR|USD|EUR|GBP|AED|AUD|CAD|CHF|JPY|SGD|THB)";
const commercialValuePattern = new RegExp([
  `(?:[$€£₹]\\s*\\d)`,
  `(?:\\d[\\d,.]*\\s*(?:[$€£₹]|${currencyCode}\\b))`,
  `(?:\\b${currencyCode}\\s*\\d)`,
  "(?:\\b(?:price|pricing|cost|total|amount|rate|supplement|margin|payment)" +
    "\\b[^.!?\\n]{0,32}\\d)",
  "(?:\\d[^.!?\\n]{0,32}\\b(?:price|pricing|cost|total|amount|rate|" +
    "supplement|margin|payment)\\b)",
].join("|"), "i");
const commercialTermPattern = /(?:\b(?:price|amount|currency|supplement|markup|margin|discount|payment)\b|[$€£₹])/iu;

export function containsCommercialValue(text: string): boolean {
  return commercialValuePattern.test(text);
}

export function containsCommercialTerm(text: string): boolean {
  return commercialTermPattern.test(text);
}
