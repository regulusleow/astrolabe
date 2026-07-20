export function runInstallation(options, dependencies) {
  const clients = dependencies.registry.resolve(options.clientIDs);
  switch (options.action) {
    case "install":
      dependencies.preparePackage();
      for (const skillDirectory of uniqueSkillDirectories(clients)) {
        dependencies.installSkillLink(skillDirectory);
      }
      for (const client of clients) {
        client.install();
      }
      return;
    case "uninstall":
      uninstallClients(clients, dependencies);
      return;
    case "check":
      checkClients(clients, dependencies);
      return;
    default:
      throw new Error(`Failed: unsupported installation action: ${options.action}`);
  }
}

function uninstallClients(clients, dependencies) {
  const candidateSkillDirectories = uniqueSkillDirectories(clients);
  const removedClientIDs = new Set(clients.map((client) => client.id));
  for (const client of clients) {
    client.uninstall();
  }

  const configuredClients = dependencies.registry
    .all()
    .filter((client) => !removedClientIDs.has(client.id) && shouldRetainSharedResources(client));
  const retainedSkillDirectories = new Set(uniqueSkillDirectories(configuredClients));
  for (const skillDirectory of candidateSkillDirectories) {
    if (!retainedSkillDirectories.has(skillDirectory)) {
      dependencies.removeSkillLink(skillDirectory);
    }
  }
}

function shouldRetainSharedResources(client) {
  try {
    return client.isConfigured();
  } catch {
    return true;
  }
}

function checkClients(clients, dependencies) {
  const sharedProblems = dependencies.checkSharedInstallation?.() ?? [];
  const problems = [...sharedProblems, ...clients.flatMap((client) => client.check())];
  if (problems.length > 0) {
    throw new Error(`Failed: local installation check failed:\n${problems.join("\n")}`);
  }
}

function uniqueSkillDirectories(clients) {
  return [...new Set(clients.flatMap((client) => client.skillDirectories))];
}
