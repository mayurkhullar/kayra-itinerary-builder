const {test} = require('node:test');
const assert = require('node:assert/strict');
const f = require('./supplierImportV2Assembly.fixtures.cjs');
const {assembleSupplierImportV2} = require('../lib/itineraryExtraction/supplierImportV2Assembly');
const {validateSupplierImportResolution} = require('../lib/itineraryExtraction/supplierImportResolutionValidation');
const {validateItineraryDraftV2, itineraryDraftV2ToMap, serializeItineraryDraftV2} = require('../lib/itineraryExtraction/itineraryDraftV2Validation');
const {readStoredItineraryDraftV2, itineraryDraftV2ForFirestore} = require('../lib/itineraryExtraction/supplierImportFinalizationStored');
const {createSupplierImportFinalizationReceipt} = require('../lib/itineraryExtraction/supplierImportFinalizationReceiptFactory');
const clone = x => JSON.parse(JSON.stringify(x));
const conditions = [{kind:'availability', value:'Subject to availability'}, {kind:'ticket_scope', value:'Entry only'}];
const source = (extra = {}) => f.snapshot({days:[f.day({date:'2027-01-01', services:[f.service(extra)]})]});
const hotel = (details = {}) => source({type:'hotel', hotelDetails:{hotelName:'Harbour Hotel', ...details}});
const assemble = (s, overrides) => assembleSupplierImportV2(s, f.aggregate(s, overrides === undefined ? {} : {decisions:[f.serviceDecision('staged-service-1',{overrides})]}), f.context());
const ready = r => {assert.equal(r.canFinalize,true,JSON.stringify(r.blockers));return r.candidate;};
const service = r => ready(r).days[0].services[0];
const map = () => clone(itineraryDraftV2ToMap(ready(assemble(hotel()))));

test('safe conditions auto-carry in order separately from notes, lists and package conditions', () => {
 const s = f.snapshot({days:[f.day({notes:'Day note', services:[f.service({conditions,notes:'Service note'})]})],packageFacts:{conditions:[{kind:'guide',value:'English speaking guide'}]}});
 const r=assemble(s), d=ready(r), v=d.days[0].services[0];
 assert.deepEqual(v.conditions,conditions); assert.equal(v.notes,'Service note');assert.equal(d.days[0].notes,'Day note');
 assert.equal(d.packageContent.conditions[0].value,'English speaking guide');assert.deepEqual(v.inclusions,[]);assert.deepEqual(v.exclusions,[]);
 assert.equal(r.accounting.find(x=>x.entityKind==='service').outcome,'auto_retained');
 assert.equal(r.blockers.some(x=>x.code==='unsupported_service_content'),false);
 assert(Object.isFrozen(v.conditions));assert(Object.isFrozen(v.conditions[0]));
});
for (const [name, change, expected] of [['set',f.set([{kind:'vehicle',value:'Coach'}]),[{kind:'vehicle',value:'Coach'}]],['clear',f.clear,[]],['reset',undefined,conditions]]) {
 test(`condition ${name} preserves source and records exact sparse semantics`,()=>{
  const s=source({conditions}), r=assemble(s,change===undefined?{}:{conditions:change});
  assert.deepEqual(service(r).conditions,expected);assert.equal(s.facts[0].conditions[0].value,conditions[0].value);
  assert.deepEqual(r.accounting.find(x=>x.entityKind==='service').fieldChanges,change===undefined?[]:[{field:'conditions',operation:change.operation}]);
 });
}
for (const value of ['Commission 12%','CNY 500','Supplement INR 500']) {
 test(`commercial source condition rejected: ${value}`,()=>assert.throws(()=>source({conditions:[{kind:'other',value}]})));
 test(`injected stored condition rejected: ${value}`,()=>{const s=clone(source({conditions}));s.facts[0].conditions[0].value=value;assert.equal(assemble(s).blockers[0].code,'invalid_snapshot');});
 test(`commercial corrected condition rejected: ${value}`,()=>assert.equal(assemble(source(),{conditions:f.set([{kind:'other',value}])}).blockers[0].code,'invalid_resolution'));
 test(`commercial canonical condition and hotel city rejected: ${value}`,()=>{for(const field of ['condition','city']){const m=map();const s=m.days[0].services[0];if(field==='city')s.hotelDetails.city=value;else s.conditions=[{kind:'other',value}];assert.throws(()=>validateItineraryDraftV2('draft-1',m));}});
}
for(const [field,value] of [['city','Kyoto'],['orSimilar',true],['orSimilar',false],['nightCount',3]]) {
 test(`hotel ${field} ${value} auto-carries without package duplication`,()=>{const d=ready(assemble(hotel({[field]:value})));assert.equal(d.days[0].services[0].hotelDetails[field],value);assert.deepEqual(d.packageContent.accommodations,[]);});
 test(`hotel ${field} set/clear/reset is lossless`,()=>{const s=hotel({[field]:value});assert.equal(service(assemble(s,{hotel:{[field]:f.set(value)}})).hotelDetails[field],value);assert.equal(service(assemble(s,{hotel:{[field]:f.clear}})).hotelDetails[field],null);assert.equal(service(assemble(s,{})).hotelDetails[field],value);});
}
test('city and nights are not inferred from service city, day date or hotel dates',()=>{
 const s=source({type:'hotel',city:'Osaka',hotelDetails:{hotelName:'Kyoto Hotel',checkInDate:'2027-01-01',checkOutDate:'2027-01-04'}});
 const v=service(assemble(s)).hotelDetails;assert.equal(v.city,undefined);assert.equal(v.nightCount,undefined);assert.equal(v.orSimilar,undefined);
});
test('nights never manufacture dates',()=>{const v=service(assemble(hotel({nightCount:3}))).hotelDetails;assert.equal(v.checkInDate,null);assert.equal(v.checkOutDate,null);});
for(const [field,value] of [['conditions',null],['conditions',[{kind:'future',value:'Note'}]],['conditions',[{kind:'other',value:'Note',price:3}]],['city',3],['orSimilar','true'],['nightCount',0],['nightCount',1.5],['nightCount',Number.MAX_SAFE_INTEGER+1]]) {
 test(`malformed optional canonical ${field} ${JSON.stringify(value)} rejected`,()=>{const m=map();(field==='conditions'?m.days[0].services[0]:m.days[0].services[0].hotelDetails)[field]=value;assert.throws(()=>validateItineraryDraftV2('draft-1',m));});
}
test('old V2 roundtrip omits absent optional keys and new V2 stored roundtrip preserves exact fields',()=>{
 const old=map();const oldV=validateItineraryDraftV2('draft-1',old);assert.deepEqual(itineraryDraftV2ToMap(oldV),old);
 assert.equal('conditions' in old.days[0].services[0],false);assert.equal('city' in old.days[0].services[0].hotelDetails,false);
 const d=ready(assemble(hotel({city:'Kyoto',orSimilar:false,nightCount:2}),{conditions:f.set(conditions)}));
 assert.equal(serializeItineraryDraftV2(readStoredItineraryDraftV2(d.id,itineraryDraftV2ForFirestore(d))),serializeItineraryDraftV2(d));
});
test('condition and hotel corrections use existing private receipt field operations',()=>{
 const r=assemble(hotel(),{conditions:f.set(conditions),hotel:{city:f.set('Kyoto'),orSimilar:f.set(true),nightCount:f.set(2)}});ready(r);
 const receipt=createSupplierImportFinalizationReceipt(r,{tripId:'trip-1',extractionId:'extraction-1',commandId:'finalization-1',expectedRevision:1,policyVersion:f.context().policyVersion,actorUid:'agent-1',finalizedAt:new Date(f.at)});
 const row=receipt.outcomes.find(x=>x.targetId==='staged-service-1');
 assert.deepEqual(row.fieldOperations.map(x=>x.field),['conditions','hotel.city','hotel.nightCount','hotel.orSimilar']);
 assert(row.fieldOperations.every(x=>x.decisionId==='staged-service-1'));assert(!JSON.stringify(receipt).includes('Subject to availability'));
});
for(const [type,details] of [['hotel',{hotelName:f.set('Selected Hotel')}],['transfer',{pickup:f.set('Airport'),dropoff:f.set('Hotel')}],['activity',{activityName:f.set('Boat tour')}]]) {
 test(`newly typed ${type} requires authored details and preserves no invented values`,()=>{
 const s=source();assert.equal(assemble(s,{serviceType:f.set(type)}).canFinalize,false);
 const v=service(assemble(s,{serviceType:f.set(type),[type]:details}));assert.equal(v.type,type);
 for(const [k,val]of Object.entries(v[`${type}Details`])) if(!Object.hasOwn(details,k))assert.equal(val,null);
 const stale=f.aggregate(s,{decisions:[f.serviceDecision('staged-service-1',{overrides:{[type]:details}})]});
 assert.throws(()=>validateSupplierImportResolution(s,stale));
 assert.equal(service(assemble(s,{}))[`${type}Details`],null);
 });
}
