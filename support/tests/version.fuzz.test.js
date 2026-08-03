import assert from "node:assert/strict";
import test from "node:test";

import fc from "fast-check";

import {
  bumpVersion,
  classifyTransition,
  formatVersion,
  packageVersion,
  validateVersion,
} from "../version.mjs";

const releaseVersion = fc.record({
  major: fc.integer({ min: 1, max: 10_000 }),
  update: fc.integer({ min: 0, max: 99 }),
  fix: fc.integer({ min: 0, max: 1_000_000 }),
});

test("fuzzes release formatting without losing version components", () => {
  fc.assert(
    fc.property(releaseVersion, (version) => {
      assert.deepEqual(validateVersion(version), { ...version });
      assert.equal(
        formatVersion(version),
        `v${version.major}.${String(version.update).padStart(2, "0")}.${version.fix}`,
      );
      assert.equal(packageVersion(version), `${version.major}.${version.update}.${version.fix}`);
    }),
    { numRuns: 1_000 },
  );
});

test("fuzzes every valid release transition", () => {
  fc.assert(
    fc.property(
      releaseVersion,
      fc.constantFrom("major", "fix"),
      (version, level) => {
        assert.equal(classifyTransition(version, bumpVersion(version, level)), level);
      },
    ),
    { numRuns: 1_000 },
  );

  fc.assert(
    fc.property(
      releaseVersion.filter((version) => version.update < 99),
      (version) => {
        assert.equal(classifyTransition(version, bumpVersion(version, "update")), "update");
      },
    ),
    { numRuns: 1_000 },
  );

  fc.assert(
    fc.property(
      releaseVersion.filter((version) => version.update < 99),
      fc.integer({ min: 1, max: 99 }),
      (version, increment) => {
        const nextUpdate = Math.min(99, version.update + increment);
        assert.equal(
          classifyTransition(version, { major: version.major, update: nextUpdate, fix: 0 }),
          "update",
        );
      },
    ),
    { numRuns: 1_000 },
  );
});
