const {test} = require('node:test');
const assert = require('node:assert/strict');
const {containsCommercialValue} = require('../lib/itineraryExtraction/nonCommercialText');

const blocked = [
  'Commission 12%', 'commission: 12 percent', 'commission: 5 percent',
  'COMMISSION:12%', 'Commission - 12 %', 'Markup 10%', 'markup 8 %',
  'Margin 8%', 'margin 10 percent', 'Discount 15%', 'discount 15 pct',
  'Supplement INR 500', 'supplement 2500', 'Surcharge ₹500', 'Rate 4500',
  'Cost 3200', 'Selling price 5500', 'Total price 12000', 'total 12000',
  'Payment due INR 20,000', 'Deposit USD 100', 'Price per adult ₹109,623',
  'price per adult 109623', 'CNY 500', '500 CNY', 'cny500', 'CNY 500.00',
  'USD100', '$100', 'EUR 99.50', '99.50 EUR', 'AED 1,250', '1,250 AED',
  'SGD500', 'MYR 300', 'THB 2500', 'RMB 500', 'JPY 12000', '¥ 12000',
  'AUD 250', 'CAD 250', 'CHF 250', 'HKD 1000', 'IDR 10000', 'VND 10000',
  'NPR 500', 'LKR 500', 'INR25,000', '₹ 25,000', 'GBP 10', '£10',
  'USD 100.50', '€10', '500CNY', 'CNY:\t500', 'Commission\n-\t12%',
  '12 percent commission', '30 cost', 'ＣＮＹ５００', '500 rupees',
];
const allowed = [
  '3 nights', '2 rooms', '4 adults', 'Breakfast for 3', 'Pick up time 10:00 am',
  '10:00 am', 'Flight AI 302', 'Gate 12', 'Terminal 3', '30 minutes photo stop',
  'Passport valid for 6 months', '6 months passport validity', '1 Double or 1 Twin',
  'Seat in Coach', 'Try 3 local dishes', '50,000 coverage', '100% vegetarian', '50% chance of rain',
  '2 bottles of water', '5 Star Hotel', 'Hotel 81', 'Myrtle Beach 3 nights',
  'Rambla 500', 'JPYard 12', 'CNYville 500', 'Shared transfer', 'Direct payment',
  '$', '¥', '€', 'Meet at the $ sign', 'Meet at ¥; Gate 12',
];
blocked.forEach((value, index) => test(`commercial value matrix blocked ${index + 1}`, () => {
  assert.equal(containsCommercialValue(value), true);
}));
allowed.forEach((value, index) => test(`commercial value matrix allowed ${index + 1}`, () => {
  assert.equal(containsCommercialValue(value), false);
}));
