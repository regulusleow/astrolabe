import { spawnSync } from "node:child_process";

export function runCommand(command, args, options = {}) {
  const cwd = options.cwd ?? process.cwd();
  const displayCommand = [command, ...args].join(" ");
  if (options.dryRun) {
    console.log(`Would run: ${displayCommand}`);
    return;
  }
  const result = spawnSync(command, args, {
    cwd,
    stdio: "inherit",
    env: process.env
  });
  if (result.error) {
    throw new Error(`Failed: unable to start command: ${displayCommand}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`Failed: command failed: ${displayCommand}`);
  }
}
