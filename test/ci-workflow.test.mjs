import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("CI exercises a Homebrew-style installed lifecycle without source build commands", async () => {
  const workflow = await readFile(".github/workflows/ci.yml", "utf8");

  assert.match(workflow, /--user-skill-dir/);
  assert.match(workflow, /--client-config "?codex=/);
  assert.match(workflow, /--channel homebrew/);
  assert.match(workflow, /Cellar\/astrolabe\/2\.0\.0/);
  assert.match(workflow, /opt\/astrolabe/);
  assert.match(workflow, /doctor --verbose --json/);
  assert.match(workflow, /"\$stable_launcher" uninstall/);
  assert.match(workflow, /HOME="\$test_home"/);
  assert.match(workflow, /Unexpected source build command/);
  assert.match(workflow, /for command in git npm swift tsc/);
  assert.doesNotMatch(workflow, /--skill-dir/);
  assert.doesNotMatch(workflow, /\s--config\s/);
  assert.match(workflow, /"\$stable_launcher" check/);
  assert.doesNotMatch(workflow, /npm run check:codex/);
});
