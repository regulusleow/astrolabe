import test from "node:test";
import assert from "node:assert/strict";

import {
  collectObjects,
  findDetailOidCandidate,
  pickApp,
  retryUntilApps
} from "../scripts/smoke-utils.mjs";

test("collectObjects finds nested UI nodes", () => {
  const tree = {
    className: "UIWindow",
    subitems: [
      {
        className: "UIView",
        subitems: [
          {
            className: "UILabel",
            oid: "42"
          }
        ]
      }
    ]
  };

  const nodes = collectObjects(tree, (item) => typeof item.className === "string");

  assert.deepEqual(nodes.map((item) => item.className).sort(), ["UILabel", "UIView", "UIWindow"]);
});

test("collectObjects handles cycles", () => {
  const root = {
    className: "UIWindow",
    subitems: []
  };
  root.subitems.push(root);

  const nodes = collectObjects(root, (item) => typeof item.className === "string");

  assert.equal(nodes.length, 1);
  assert.equal(nodes[0], root);
});

test("pickApp selects explicit appId", () => {
  const apps = [
    {
      appId: "app-a",
      displayName: "A"
    },
    {
      appId: "app-b",
      displayName: "B"
    }
  ];

  assert.equal(pickApp(apps, "app-b").displayName, "B");
});

test("pickApp falls back to first app", () => {
  const apps = [
    {
      appId: "app-a",
      displayName: "A"
    }
  ];

  assert.equal(pickApp(apps, "").appId, "app-a");
});

test("pickApp rejects missing explicit appId", () => {
  assert.throws(
    () => pickApp([{ appId: "app-a" }], "missing"),
    /Specified App not found: missing/
  );
});

test("pickApp selects requested connection kind", () => {
  const apps = [
    {
      appId: "sim",
      connectionKind: "simulator"
    },
    {
      appId: "device",
      connectionKind: "usb"
    }
  ];

  assert.equal(pickApp(apps, "", { connectionKind: "usb" }).appId, "device");
});

test("pickApp rejects missing requested connection kind", () => {
  assert.throws(
    () => pickApp([{ appId: "sim", connectionKind: "simulator" }], "", { connectionKind: "usb" }),
    /No App found with connectionKind=usb/
  );
});

test("findDetailOidCandidate prefers UILabel", () => {
  const nodes = [
    {
      className: "UIView",
      oid: "1"
    },
    {
      className: "UILabel",
      oid: "2"
    }
  ];

  assert.equal(findDetailOidCandidate(nodes), "2");
});

test("findDetailOidCandidate falls back to any node oid", () => {
  const nodes = [
    {
      className: "UIView",
      oid: "1"
    }
  ];

  assert.equal(findDetailOidCandidate(nodes), "1");
});

test("findDetailOidCandidate accepts non-numeric opaque identifiers", () => {
  const nodes = [
    {
      className: "UILabel",
      oid: "node-title"
    }
  ];

  assert.equal(findDetailOidCandidate(nodes), "node-title");
});

test("retryUntilApps retries empty app list", async () => {
  let attempts = 0;
  const apps = await retryUntilApps(async () => {
    attempts += 1;
    return attempts === 3 ? [{ appId: "app-a" }] : [];
  }, {
    maxAttempts: 3,
    intervalMs: 0
  });

  assert.equal(attempts, 3);
  assert.deepEqual(apps, [{ appId: "app-a" }]);
});

test("retryUntilApps throws after empty attempts", async () => {
  await assert.rejects(
    () => retryUntilApps(async () => [], {
      maxAttempts: 2,
      intervalMs: 0
    }),
    /No inspectable App found/
  );
});
