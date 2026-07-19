import { readFileSync } from "node:fs";

const releaseVersionPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

export function readPackageVersion(
  packageURL: URL = new URL("../package.json", import.meta.url)
): string {
  let packageMetadata: unknown;
  try {
    packageMetadata = JSON.parse(readFileSync(packageURL, "utf8"));
  } catch {
    throw new Error("Unable to read the MCP package version");
  }
  if (!isRecord(packageMetadata)
      || typeof packageMetadata.version !== "string"
      || !releaseVersionPattern.test(packageMetadata.version)) {
    throw new Error("Invalid MCP package version");
  }
  return packageMetadata.version;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
