const {test} = require('node:test');
const assert = require('node:assert/strict');
const f = require('./supplierImportV2Assembly.fixtures.cjs');
const admin = require('./supplierImportFinalization.fixtures.cjs');
const {optionalChronologyImportPolicy: policy} = require('../lib/itineraryExtraction/itineraryDraftV2');
const {assembleSupplierImportV2: build} = require('../lib/itineraryExtraction/supplierImportV2Assembly');
const {validateItineraryDraftV2: validate, itineraryDraftV2ToMap: map} = require('../lib/itineraryExtraction/itineraryDraftV2Validation');
const {itineraryDraftV2ForFirestore: store, readStoredItineraryDraftV2: read} = require('../lib/itineraryExtraction/supplierImportFinalizationStored');
const {supplierImportCanonicalContentDigest: digest} = require('../lib/itineraryExtraction/supplierImportFinalizationReceiptDigest');
const {createSupplierImportFinalizationReceipt: receipt} = require('../lib/itineraryExtraction/supplierImportFinalizationReceiptFactory');
const {finalizeSupplierImportAdmin: finalize} = require('../lib/itineraryExtraction/supplierImportFinalizationAdmin');
const {validateFinalizationRequest} = require('../lib/itineraryExtraction/supplierImportFinalization');
const {finalizationPayloadBytes: bytes, requireFinalizationBudget: budget} = require('../lib/itineraryExtraction/supplierImportFinalizationCapacity');
const {parseSupplierExtractionSnapshotStructure: parseSnapshot} = require('../lib/itineraryExtraction/supplierExtractionStoredValidation');
const assemble = (s, changes = {}, p = policy) => build(s, f.aggregate(s, changes), {...f.context(), policyVersion:p});
const ready = r => {assert.equal(r.canFinalize,true,JSON.stringify(r.blockers));return r.candidate;};
const blocked = (r, code) => {assert.equal(r.canFinalize,false);assert.equal(r.candidate,null);if(code)assert(r.blockers.some(b=>b.code===code),JSON.stringify(r.blockers));};
const snapshot = extra => f.snapshot({unassignedServices:[f.service()],...extra});
const plain = d => JSON.parse(JSON.stringify(map(d)));
const issue = (code,basis='absence_only',extra={}) => f.issue({code,severity:'blocker',resolutionRequired:true,
  target:{kind:'service',scope:'unassigned',serviceIndex:1},...(basis ? {structureBasis:basis}:{}),...extra});
const retained = r => r.accounting.find(a=>a.entityKind==='service');

for(const [name,payload] of [
 ['one unscheduled',{unassignedServices:[f.service()]}],
 ['several unscheduled',{unassignedServices:[f.service({title:'Second'}),f.service({title:'First'})]}],
 ['package only',{packageFacts:{inclusions:[{category:'other',text:'Admission'}]}}],
 ['scheduled only',{days:[f.day()]}],
 ['days and unscheduled',{days:[f.day()],unassignedServices:[f.service()]}],
 ['package and unscheduled',{packageFacts:{inclusions:[{category:'other',text:'Admission'}]},unassignedServices:[f.service()]}],
 ['all three',{days:[f.day()],packageFacts:{inclusions:[{category:'other',text:'Admission'}]},unassignedServices:[f.service()]}],
]) test(`new policy finalizes ${name} with four writes and exact replay`,async()=>{
 const {db,paths}=admin.fixture(payload), req=admin.request({policyVersion:policy});
 const r=await finalize(db,admin.actor,req);assert.equal(r.outcome,'applied');assert.equal(db.commits.length,1);assert.equal(db.commits[0].length,4);
 const d=read(paths.resultingDraftId,db.records.get(paths.draft));assert.equal(d.days.length,payload.days?.length??0);
 assert.equal(d.unscheduledServices?.length??0,payload.unassignedServices?.length??0);
 const ledger=db.records.get(paths.receipt).outcomes;
 for(const s of d.unscheduledServices??[]){const rows=ledger.filter(a=>a.outputTargets.some(o=>o.id===s.id));assert.equal(rows.length,1);assert.equal(rows[0].outcome,'auto_retained');assert(rows[0].outputTargets.every(o=>o.kind==='service'&&!('dayNumber'in o)));}
 assert.equal((await finalize(db,admin.actor,req)).outcome,'already_applied');assert.equal(db.commits.length,1);
});
test('no decision, manual item or chronology is invented and source display order is deterministic',()=>{
 const s=snapshot({unassignedServices:[f.service({title:'Z',startTime:'09:00'}),f.service({title:'A'})]});
 const r=assemble(s),d=ready(r);assert.deepEqual(d.days,[]);assert.deepEqual(d.unscheduledServices.map(s=>s.title),['Z','A']);
 assert.equal(d.unscheduledServices[0].startTime,'09:00');assert.equal('dayNumber'in d.unscheduledServices[0],false);
 assert.deepEqual(retained(r).decisionIds,[]);assert.equal(retained(r).origin,'supplier');assert.deepEqual(map(d),map(ready(assemble(s))));
});
test('old policy still blocks unassigned content',()=>blocked(assemble(snapshot(),{},f.context().policyVersion),'unresolved_unassigned_service'));
test('old map and digest remain unchanged without optional field',()=>{
 const s=f.snapshot({days:[f.day()]});const d=ready(assemble(s,{},f.context().policyVersion));
 assert.equal('unscheduledServices'in map(d),false);assert.equal(digest(d),digest(read(d.id,store(d))));
 const explicit=validate(d.id,{...plain(d),unscheduledServices:[]});assert.deepEqual(map(explicit).unscheduledServices,[]);assert.notEqual(digest(explicit),digest(d));
});
test('historical finalization replays after newer policy is installed',async()=>{
 const {db,paths}=admin.fixture();const req=admin.request();assert.equal((await finalize(db,admin.actor,req)).outcome,'applied');
 const original=structuredClone(db.records.get(paths.receipt).contentDigest);
 assert.equal((await finalize(db,admin.actor,req)).outcome,'already_applied');assert.equal(db.records.get(paths.receipt).contentDigest,original);
 assert.equal('unscheduledServices'in db.records.get(paths.draft),false);
});
for(const type of ['hotel','transfer','activity','meal','sightseeing','free_time','other'])test(`strict shared ${type} service shape survives unscheduled`,()=>{
 const details=type==='hotel'?{hotelDetails:{hotelName:'Hotel',city:'City',orSimilar:false,nightCount:3,checkInDate:'2027-01-01',checkOutDate:'2027-01-04',roomType:'Twin',mealPlan:'Breakfast',numberOfRooms:2}}:
 type==='transfer'?{transferDetails:{pickup:'Airport',dropoff:'Hotel',vehicleType:'Van',transferType:'private'}}:
 type==='activity'?{activityDetails:{activityName:'Tour',duration:'2 hours',activityType:'Walking'}}:{};
 const value=f.service({type,...details,title:'Service',description:'Description',startTime:'09:00',endTime:'11:00',location:'Entrance',city:'City',notes:'Bring hat',
 inclusions:[{category:'other',text:'Water'}],exclusions:[{category:'other',text:'Lunch'}],conditions:[{kind:'availability',value:'Subject to availability'}]});
 const d=ready(assemble(snapshot({unassignedServices:[value]})));const service=d.unscheduledServices[0];
 const scheduled=ready(assemble(f.snapshot({days:[f.day({services:[value]})]}))).days[0].services[0];assert.deepEqual(service,scheduled);
 assert.deepEqual(map(read(d.id,store(d))),map(d));assert.equal(service.sourceReference.supplierSourceFileId,'file-1');
});
for(const [name,change] of [
 ['missing title',s=>delete s.title],['unknown type',s=>s.type='flight'],['unknown price',s=>s.price=100],
 ['malformed conditions',s=>s.conditions=[{kind:'other',value:7}]],['foreign provenance',s=>s.sourceReference.supplierSourcePackageId='foreign'],
 ...['Commission 12%','CNY 500','Supplement INR 500'].map(v=>[v,s=>s.notes=v]),
])test(`unscheduled canonical rejects ${name}`,()=>{const d=ready(assemble(snapshot())),m=plain(d);change(m.unscheduledServices[0]);assert.throws(()=>validate(d.id,m));});
for(const location of ['unscheduled','day'])test(`duplicate ID across ${location} fails`,()=>{
 const d=ready(assemble(snapshot({days:[f.day()]}))),m=plain(d);
 if(location==='day')m.unscheduledServices[0].id=m.days[0].services[0].id;else m.unscheduledServices.push({...m.unscheduledServices[0]});assert.throws(()=>validate(d.id,m));
});
test('explicit schedule consumes service once and retains supplier origin',()=>{
 const s=snapshot({days:[f.day({services:[]})]});const r=assemble(s,{decisions:[f.serviceDecision('staged-service-1',{day:{kind:'staged_day',dayId:'staged-day-1'},canonicalOrder:1})]});
 const d=ready(r);assert.equal(d.days[0].services.length,1);assert.equal(d.unscheduledServices,undefined);assert.equal(retained(r).origin,'supplier');
});
test('explicit assignment without order still blocks',()=>blocked(assemble(snapshot({days:[f.day({services:[]})]}),{decisions:[f.serviceDecision('staged-service-1',{day:{kind:'staged_day',dayId:'staged-day-1'}})]}),'missing_service_order'));
test('exclusion wins and no output contains excluded service',()=>{const r=assemble(snapshot(),{decisions:[f.serviceDecision('staged-service-1',f.exclusion())]});const d=ready(r);assert.deepEqual(d.days,[]);assert.equal(d.unscheduledServices,undefined);assert.equal(retained(r).outcome,'excluded');});
test('excluded source day never implicitly unschedules its service',()=>blocked(assemble(f.snapshot({days:[f.day()]}),{decisions:[f.dayDecision('staged-day-1',f.exclusion())]}),'invalid_resolution'));
test('corrections apply while unscheduled with correction lineage',()=>{
 const r=assemble(snapshot(),{decisions:[f.serviceDecision('staged-service-1',{overrides:{title:f.set('Changed'),notes:f.clear,conditions:f.set([{kind:'guide',value:'English guide'}])}})]});
 const s=ready(r).unscheduledServices[0];assert.equal(s.title,'Changed');assert.equal(s.notes,null);assert.equal(s.conditions[0].value,'English guide');assert.deepEqual(retained(r).decisionIds,['staged-service-1']);
});
test('lossy structured service inclusion still blocks',()=>blocked(assemble(snapshot({unassignedServices:[f.service({inclusions:[{category:'meal',text:'Lunch',quantity:3}]})]})),'unsupported_service_content'));
test('malformed service still blocks without a day',()=>blocked(assemble(snapshot({unassignedServices:[f.service({type:'transfer'})]})),'missing_required_service_details'));
for(const code of ['chronology_unknown','global_mapping_required']){
 test(`${code} explicit absence evidence allows auto-carry`,()=>{const r=assemble(snapshot({reviewIssues:[issue(code)]}));ready(r);assert.equal(r.accounting.find(a=>a.entityKind==='review_issue').outcome,'review_derived');});
 for(const basis of [undefined,'explicit_relationship'])test(`${code} ${basis??'historical ambiguous'} stays blocked`,()=>blocked(assemble(snapshot({reviewIssues:[issue(code,basis??null)]})),'structural_review_issue_unresolved'));
 test(`${code} message never controls evidence semantics`,()=>{ready(assemble(snapshot({reviewIssues:[issue(code,'absence_only',{message:'Chronology conflict wording is not parsed'})]})));blocked(assemble(snapshot({reviewIssues:[issue(code,null,{message:'No dates needed'})]})));});
}
for(const code of ['source_conflict','classification_ambiguous','conflicting_dates','other'])test(`${code} remains unresolved`,()=>blocked(assemble(snapshot({reviewIssues:[issue(code,null)]}))));
test('optional warning needs no acknowledgement',()=>ready(assemble(snapshot({reviewIssues:[issue('other',null,{severity:'warning',resolutionRequired:false})]}))));
test('absence evidence cannot downgrade source-assigned chronology',()=>blocked(assemble(f.snapshot({days:[f.day()],reviewIssues:[issue('chronology_unknown','absence_only',{target:{kind:'service',scope:'day',dayIndex:1,serviceIndex:1}})]}))));
test('absence-only accommodation span survives package scope',()=>ready(assemble(f.snapshot({packageFacts:{accommodations:[{hotelName:'Hotel'}]},reviewIssues:[issue('accommodation_span_unknown','absence_only',{target:{kind:'package_fact',factType:'accommodation',factIndex:1}})]}))));
for(const basis of [null,'unknown',42])test(`invalid structure evidence ${basis} rejected`,()=>assert.throws(()=>snapshot({reviewIssues:[issue('chronology_unknown',basis,{structureBasis:basis})]})));
test('structure evidence on source conflict rejected by normalization and stored reader',()=>{
 assert.throws(()=>snapshot({reviewIssues:[issue('source_conflict')]}));const s=JSON.parse(JSON.stringify(snapshot({reviewIssues:[issue('other',null)]})));s.reviewIssues[0].structureBasis='absence_only';assert.throws(()=>parseSnapshot(s));
});
test('safe explicit package mapping targets unscheduled service and receipt field',()=>{
 const s=snapshot({packageFacts:{inclusions:[{category:'other',text:'Water'}]}});
 const r=assemble(s,{decisions:[f.packageDecision('package-fact-1','package_statement',{disposition:'map_to_service',service:{kind:'staged_service',serviceId:'staged-service-1'},destination:'service_inclusion'})]});
 const d=ready(r);assert.deepEqual(d.unscheduledServices[0].inclusions,['Water']);assert.deepEqual(d.packageContent.inclusions,[]);
 const ledger=receipt(r,{tripId:s.tripId,extractionId:s.extractionId,commandId:f.context().finalizationId,expectedRevision:1,policyVersion:policy,actorUid:f.context().actorUid,finalizedAt:new Date(f.context().updatedAt)});
 assert(ledger.outcomes.find(o=>o.targetId==='package-fact-1').outputTargets.some(o=>o.kind==='service'&&o.field==='inclusions'));
});
test('ancillary never becomes unscheduled service',()=>blocked(assemble(snapshot({ancillaryFacts:{visas:[{disposition:'mentioned',text:'Visa required'}]}})),'unresolved_ancillary_fact'));
test('unscheduled records do not count toward package-only 256-record budget',()=>{const d=ready(assemble(snapshot({unassignedServices:Array.from({length:257},()=>f.service())})));assert.equal(d.unscheduledServices.length,257);assert.deepEqual(d.packageContent.inclusions,[]);});
test('unscheduled payload counts toward canonical capacity without truncation',()=>{
 const d=ready(assemble(snapshot())),m=plain(d);m.unscheduledServices[0].description='a'.repeat(800000);const encoded=store(validate(d.id,m));assert(bytes(encoded)>768*1024);assert.throws(()=>budget('canonical',bytes(encoded)));
});
test('new-policy malformed requests reject',()=>{for(const bad of [policy+' ',null,'future'])assert.throws(()=>validateFinalizationRequest(admin.request({policyVersion:bad})));});
