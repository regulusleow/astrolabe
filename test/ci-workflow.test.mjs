import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("Codex installation CI uses the shared installer options", async () => {
  const workflow = await readFile(".github/workflows/ci.yml", "utf8");

  assert.match(workflow, /--user-skill-dir/);
  assert.match(workflow, /--client-config "?codex=/);
  assert.doesNotMatch(workflow, /--skill-dir/);
  assert.doesNotMatch(workflow, /\s--config\s/);
});
