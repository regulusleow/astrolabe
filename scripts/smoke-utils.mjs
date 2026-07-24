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
  return nodeIdentifier(inspectableNodeCandidate(nodes));
}

export function pickInspectableClassName(nodes) {
  return inspectableNodeCandidate(nodes).className;
}

function inspectableNodeCandidate(nodes) {
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
  return candidate;
}

export function findReversibleStringPatch(detailAttributes, patchableAttributes) {
  for (const patchableAttribute of patchableAttributes) {
    const allowedValues = patchableAttribute.valueConstraints?.allowedValues;
    if (
      patchableAttribute.valueType !== "string"
      || (Array.isArray(allowedValues) && allowedValues.length > 0)
      || typeof patchableAttribute.attributePattern !== "string"
    ) {
      continue;
    }
    const detailIdentifier = patchableAttribute.attributePattern.split(".").at(-1);
    const detailAttribute = detailAttributes.find((item) => (
      item.identifier === detailIdentifier && typeof item.value === "string"
    ));
    if (detailAttribute) {
      return {
        attributeIdentifier: patchableAttribute.attributePattern,
        value: detailAttribute.value
      };
    }
  }
  throw new Error("No reversible string patch candidate found");
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
