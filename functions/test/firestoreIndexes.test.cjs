const {test} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {resolve} = require("node:path");

const config = JSON.parse(readFileSync(resolve(__dirname, "../../firestore.indexes.json"), "utf8"));
const payloads = {
  itinerary_drafts: ["days", "unscheduledServices", "packageContent", "importResult", "sourcePackageIds", "reviewIssues"],
  finalizations: ["outcomes"],
};

test("Firestore index configuration uses exact field exemptions and valid structure", () => {
  assert.deepEqual(Object.keys(config).sort(), ["fieldOverrides", "indexes"]);
  assert.deepEqual(config.indexes, []);
  assert.ok(Array.isArray(config.fieldOverrides));
  for (const override of config.fieldOverrides) {
    assert.deepEqual(Object.keys(override).sort(), ["collectionGroup", "fieldPath", "indexes"]);
    assert.equal(typeof override.collectionGroup, "string");
    assert.equal(typeof override.fieldPath, "string");
    assert.ok(payloads[override.collectionGroup]?.includes(override.fieldPath));
    assert.deepEqual(override.indexes, []);
  }
});

for (const [collectionGroup, fields] of Object.entries(payloads)) {
  for (const fieldPath of fields) {
    test(`${collectionGroup}.${fieldPath} has one complete single-field exemption`, () => {
      assert.deepEqual(config.fieldOverrides.filter((item) =>
        item.collectionGroup === collectionGroup && item.fieldPath === fieldPath),
      [{collectionGroup, fieldPath, indexes: []}]);
    });
  }
}

test("Firestore field overrides have no duplicate or parent/child conflicts", () => {
  const overrides = config.fieldOverrides;
  for (let i = 0; i < overrides.length; i++) {
    for (let j = i + 1; j < overrides.length; j++) {
      if (overrides[i].collectionGroup !== overrides[j].collectionGroup) continue;
      const a = overrides[i].fieldPath;
      const b = overrides[j].fieldPath;
      assert.notEqual(a, b);
      assert.ok(!a.startsWith(`${b}.`) && !b.startsWith(`${a}.`));
    }
  }
});

test("document lookup, ordering, version, status and ownership fields retain indexing", () => {
  const protectedFields = ["__name__", "tripId", "schemaVersion", "createdAt", "updatedAt", "status",
    "createdByUid", "ownerUid", "extractionId", "resolutionId", "sourcePackageId", "finalizedAt",
    "actorUid", "commandId", "finalizationId", "resultingDraftId", "policyVersion", "canonicalSchemaVersion"];
  for (const override of config.fieldOverrides) {
    assert.notEqual(override.fieldPath, "*");
    for (const field of protectedFields) {
      assert.ok(field !== override.fieldPath && !field.startsWith(`${override.fieldPath}.`));
    }
  }
});
