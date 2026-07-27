import { lstatSync, mkdirSync, realpathSync, symlinkSync, unlinkSync } from "node:fs";
import { dirname } from "node:path";

export function installManagedSkillLink(userSkillDir, packageSkillDir, dryRun) {
  const existingStat = lstatIfExists(userSkillDir);
  if (existingStat && !existingStat.isSymbolicLink()) {
    throw new Error(`Failed: skill directory exists and is not a symbolic link: ${userSkillDir}`);
  }
  if (dryRun) {
    return;
  }
  mkdirSync(dirname(userSkillDir), { recursive: true });
  if (existingStat) {
    unlinkSync(userSkillDir);
  }
  symlinkSync(packageSkillDir, userSkillDir, "dir");
}

export function removeManagedSkillLink(userSkillDir, packageSkillDir, dryRun) {
  const existingStat = lstatIfExists(userSkillDir);
  if (!existingStat?.isSymbolicLink()) {
    return false;
  }
  if (!linksTo(userSkillDir, packageSkillDir)) {
    return false;
  }
  if (!dryRun) {
    unlinkSync(userSkillDir);
  }
  return true;
}

export function checkManagedSkillLink(userSkillDir, packageSkillDir) {
  const existingStat = lstatIfExists(userSkillDir);
  if (!existingStat) {
    return [`User-level Astrolabe skill not found: ${userSkillDir}/SKILL.md`];
  }
  if (!existingStat.isSymbolicLink()) {
    return [`User-level Astrolabe skill is not a symbolic link: ${userSkillDir}`];
  }
  if (!linksTo(userSkillDir, packageSkillDir)) {
    return [`User-level Astrolabe skill does not point to the installed runtime package: ${userSkillDir}`];
  }
  return [];
}

function linksTo(linkPath, targetPath) {
  try {
    return realpathSync(linkPath) === realpathSync(targetPath);
  } catch {
    return false;
  }
}

function lstatIfExists(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error?.code === "ENOENT") {
      return null;
    }
    throw error;
  }
}
