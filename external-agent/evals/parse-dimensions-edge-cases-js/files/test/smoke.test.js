import { test } from "node:test";
import assert from "node:assert/strict";
import { parseDimensions } from "../src/parseDims.js";

test("module exports parseDimensions", () => {
  assert.equal(typeof parseDimensions, "function");
});
