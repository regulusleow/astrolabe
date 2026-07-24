export function collectObjects(value, predicate) {
  const result = [];
  const stack = [value];
  const seen = new Set();

  while (stack.length > 0) {
    const current = stack.pop();
    if (!current || typeof current !== "object" || seen.has(current)) {
      continue;
    }
    seen.add(current);

    if (predicate(current)) {
      result.push(current);
    }

    if (Array.isArray(current)) {
      for (const item of current) {
        stack.push(item);
      }
    } else {
      for (const item of Object.values(current)) {
        stack.push(item);
      }
    }
  }

  return result;
}

export function pickApp(apps, appId, options = {}) {
  const connectionKind = options.connectionKind ?? "";
  const candidates = connectionKind
    ? apps.filter((item) => item.connectionKind === connectionKind)
    : apps;
  if (connectionKind && candidates.length === 0) {
    throw new Error(`No App found with connectionKind=${connectionKind}`);
  }

  const app = appId ? candidates.find((item) => item.appId === appId) : candidates[0];
  if (!app) {
    throw new Error(`Specified App not found: ${appId}`);
  }
  return app;
}

export function findDetailOidCandidate(nodes) {
  const candidate = nodes.find((item) => item.className === "UILabel" && nodeIdentifier(item))
    ?? nodes.find((item) => nodeIdentifier(item));
  if (!candidate) {
    throw new Error("No OID found for reading node details");
  }
  return nodeIdentifier(candidate);
}

export function pickInspectableClassName(nodes) {
  const visibleNodes = nodes.filter((item) => (
    typeof item.className === "string"
    && item.className.length > 0
    && nodeIdentifier(item)
    && item.hidden !== true
    && Number(item.alpha ?? 1) > 0
  ));
  const textNode = visibleNodes.find((item) => (
    typeof item.text === "string" && item.text.length > 0
  )) ?? visibleNodes.find((item) => /(?:Label|TextView)$/.test(item.className));
  const candidate = textNode ?? visibleNodes[0];
  if (!candidate) {
    throw new Error("No visible inspectable node class found");
  }
  return candidate.className;
}

function nodeIdentifier(node) {
  for (const value of [node.detailOid, node.oid]) {
    if (typeof value === "string" && value.length > 0) {
      return value;
    }
  }
  return undefined;
}

export async function retryUntilApps(fetchApps, options = {}) {
  const maxAttempts = options.maxAttempts ?? 5;
  const intervalMs = options.intervalMs ?? 500;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const apps = await fetchApps();
    if (Array.isArray(apps) && apps.length > 0) {
      return apps;
    }

    if (attempt < maxAttempts) {
      await delay(intervalMs);
    }
  }

  throw new Error("No inspectable App found; start the target App first");
}

function delay(intervalMs) {
  return new Promise((resolvePromise) => {
    setTimeout(resolvePromise, intervalMs);
  });
}
