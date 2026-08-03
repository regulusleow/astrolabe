import { createHash } from "node:crypto";
import { delimiter } from "node:path";

const visibleEnvironmentNames = new Set([
  "PATH",
  "SHELL",
  "TERM",
  "LANG",
  "LC_ALL"
]);

/**
 * @typedef {Object} SanitizationOptions
 * @property {string} homeDirectory - Exact home-directory prefix replaced with a tilde.
 */

/**
 * @param {Record<string, unknown>} rawReport
 * @param {SanitizationOptions} options
 * @returns {Record<string, unknown>}
 */
export function sanitizeDiagnosticReport(rawReport, options) {
  return sanitizeValue(rawReport, options, "");
}

/**
 * @param {string} value
 * @param {SanitizationOptions} options
 * @returns {string}
 */
export function redactText(value, options) {
  let result = value;
  if (options.homeDirectory) {
    result = result.replaceAll(options.homeDirectory, "~");
  }
  result = result.replace(/~\/[^\s,;:"']+/g, "<home-path>");
  result = result.replace(
    /\b(https?:\/\/)[^\s/@:]+:[^\s/@]+@/gi,
    "$1<redacted>@"
  );
  result = result.replace(
    /([?&](?:api[_-]?key|token|key|secret|password|passphrase|authorization)=)[^&#\s]+/gi,
    "$1<redacted>"
  );
  result = result.replace(
    /(Authorization\s*:\s*)(?:Basic|Bearer)?\s*[^\s,;]+/gi,
    "$1<redacted>"
  );
  result = result.replace(/\b(?:Bearer|Basic)\s+[^\s,;]+/gi, "<redacted>");
  result = result.replace(
    /((?:password|passphrase|cookie|_authToken)\s*[=:]\s*)[^\s&]+/gi,
    "$1<redacted>"
  );
  result = result.replace(/\bgh[pousr]_[A-Za-z0-9_]+\b/g, "<redacted>");
  result = result.replace(/\bnpm_[A-Za-z0-9]{20,}\b/g, "<redacted>");
  result = result.replace(
    /\b[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{12,}\b/g,
    (identifier) => maskedDeviceIdentifier(identifier)
  );
  result = result.replace(/(^|[\s"'=(])\/[^\s,;:"']+/g, "$1<path>");
  return result;
}

function sanitizeValue(value, options, key) {
  if (typeof value === "string") {
    if (key === "deviceIdentifiers") {
      return maskedDeviceIdentifier(value);
    }
    return redactText(value, options);
  }
  if (Array.isArray(value)) {
    return value.map((item) => sanitizeValue(item, options, key));
  }
  if (!value || typeof value !== "object") {
    return value;
  }

  const result = {};
  for (const [field, fieldValue] of Object.entries(value)) {
    if (isSecretField(field)) {
      result[field] = "<redacted>";
    } else if (field === "environment" && fieldValue && typeof fieldValue === "object" && !Array.isArray(fieldValue)) {
      result[field] = sanitizeEnvironment(fieldValue, options);
    } else {
      result[field] = sanitizeValue(fieldValue, options, field);
    }
  }
  return result;
}

function isSecretField(field) {
  const normalized = field.replaceAll("_", "").replaceAll("-", "").toLowerCase();
  return [
    "token",
    "secret",
    "password",
    "passphrase",
    "authorization",
    "cookie",
    "credential",
    "apikey"
  ].some((name) => normalized.includes(name));
}

function sanitizeEnvironment(environment, options) {
  const result = {};
  for (const [name, value] of Object.entries(environment)) {
    if (!visibleEnvironmentNames.has(name) || typeof value !== "string") {
      result[name] = "<redacted>";
    } else if (name === "PATH") {
      result[name] = value
        .split(delimiter)
        .map((entry) => redactText(entry, options))
        .join(delimiter);
    } else {
      result[name] = redactText(value, options);
    }
  }
  return result;
}

function maskedDeviceIdentifier(identifier) {
  const digest = createHash("sha256").update(identifier).digest("hex").slice(0, 8);
  return `<device:${digest}>`;
}
