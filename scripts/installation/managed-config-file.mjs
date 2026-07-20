import { copyFileSync, existsSync, mkdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

export function writeManagedConfig(configPath, nextText) {
  mkdirSync(dirname(configPath), { recursive: true });
  if (existsSync(configPath)) {
    copyFileSync(configPath, `${configPath}.astrolabe.bak`);
  }
  const temporaryPath = `${configPath}.astrolabe.tmp-${process.pid}-${Date.now()}`;
  try {
    writeFileSync(temporaryPath, nextText, { mode: 0o600 });
    renameSync(temporaryPath, configPath);
  } finally {
    rmSync(temporaryPath, { force: true });
  }
}
