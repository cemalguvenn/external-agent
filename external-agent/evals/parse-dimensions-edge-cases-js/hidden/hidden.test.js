// Hidden acceptance tests. Copy into the repo's test/ dir and run `node --test test/`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseDimensions as p } from "../src/parseDims.js";

const ok = (input, l, w, h) =>
  test(`accepts ${JSON.stringify(input)}`, () =>
    assert.deepEqual(p(input), { length: l, width: w, height: h }));
const bad = (input) =>
  test(`rejects ${JSON.stringify(input)}`, () => assert.throws(() => p(input)));

ok("120x80x60 cm", 1200, 800, 600);
ok("1,2 × 0,8 × 0,6m", 1200, 800, 600);
ok("300X200X150MM", 300, 200, 150);
ok("10.25x1x1 cm", 103, 10, 10);
ok("  2 x 3 x 4 Cm  ", 20, 30, 40);
ok("1.5x2x0,5 m", 1500, 2000, 500);
ok("0.6x1x1 mm", 1, 1, 1);
ok("5x5x5mm", 5, 5, 5);

bad("10x10x10");
bad("10x10x10 in");
bad("10x10 cm");
bad("1x2x3x4 cm");
bad("0x1x1 cm");
bad("-1x1x1 cm");
bad("0.04x1x1 mm");
bad("ax1x1 cm");
bad("1e3x1x1 cm");
bad("");
bad("   ");
bad("1,,2x1x1 cm");
bad("1.2.3x1x1 cm");
test("rejects non-string", () => {
  assert.throws(() => p(42));
  assert.throws(() => p(null));
  assert.throws(() => p(undefined));
});
