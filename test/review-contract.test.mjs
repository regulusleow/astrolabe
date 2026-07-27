import test from "node:test";
import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { versionConsistencyIssues } from "../scripts/versioning.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

test("canonical package version and derived release artifacts stay aligned", async () => {
  const mcpSource = await readProjectFile("mcp-adapter/src/index.ts");
  const smokeSource = await readProjectFile("scripts/smoke-test.mjs");

  assert.deepEqual(versionConsistencyIssues(projectRoot), []);
  assert.match(mcpSource, /readPackageVersion/);
  assert.doesNotMatch(mcpSource, /version: "\d+\.\d+\.\d+"/);
  assert.match(smokeSource, /canonicalRepositoryVersion/);
  assert.doesNotMatch(smokeSource, /version: "\d+\.\d+\.\d+"/);
});

test("root npm install owns the MCP adapter development dependencies", async () => {
  const rootPackage = JSON.parse(await readProjectFile("package.json"));
  const ciWorkflow = await readProjectFile(".github/workflows/ci.yml");

  assert.deepEqual(rootPackage.workspaces, ["mcp-adapter"]);
  assert.doesNotMatch(ciWorkflow, /npm --prefix mcp-adapter ci/);
});

test("smoke workflow uses bounded current-session inspection inputs", async () => {
  const smokeSource = await readProjectFile("scripts/smoke-test.mjs");

  assert.doesNotMatch(smokeSource, /providerPreview/);
  assert.doesNotMatch(smokeSource, /shouldAllowLowResolutionScreenshot/);
  assert.match(
    smokeSource,
    /function buildScreenshotComparisonSourceArgs\(\) \{\s+return buildScreenshotSourceArgs\(\);\s+\}/
  );
  assert.match(
    smokeSource,
    /\[\s*"capture-hierarchy",\s*selectedAppId,\s*"--node-limit",\s*"200",\s*"--json"\s*\]/
  );
  assert.doesNotMatch(smokeSource, /checkCandidate/);
  assert.doesNotMatch(smokeSource, /Number\([^\n]*(?:oid|detailOid)/i);
  assert.match(smokeSource, /buildCheckNodeArgs\(selectedAppId, inspectedClassName\)/);
  assert.match(smokeSource, /buildCheckNodeToolArgs\(selectedAppId, inspectedClassName\)/);
});

test("README command examples match the current positional CLI contract", async () => {
  const readme = await readProjectFile("README.md");

  assert.match(readme, /astrolabe capture-hierarchy <app-id> --json/);
  assert.match(readme, /astrolabe node-detail <app-id> <oid> --json/);
  assert.doesNotMatch(readme, /capture-hierarchy --app <app-id>/);
  assert.doesNotMatch(readme, /node-detail --app <app-id>/);
});

test("Astrolabe skill verifies image rendering beyond the container frame", async () => {
  const skill = await readProjectFile("skills/astrolabe/SKILL.md");

  assert.match(skill, /imageSize/);
  assert.match(skill, /imageScale/);
  assert.match(skill, /contentMode/);
  assert.match(skill, /frame or bounds alone/);
  assert.match(skill, /unscaled content mode/);
  assert.doesNotMatch(skill, /always use `?scaleAspectFit`?/i);
});

test("Astrolabe skill is platform-neutral and capability-driven", async () => {
  const skill = await readProjectFile("skills/astrolabe/SKILL.md");

  assert.match(skill, /supported mobile platform/i);
  assert.match(skill, /platform/);
  assert.match(skill, /capabilities/);
  assert.match(skill, /logical/);
  assert.match(skill, /pixel/);
  assert.match(skill, /snapshotId/);
  assert.match(skill, /recoverySuggestion/);
  assert.doesNotMatch(skill, /implementing, debugging, or reviewing an iOS/i);
  assert.doesNotMatch(skill, /`ios_[a-z_]+`|`android_[a-z_]+`/);
});

test("public documentation advertises delivered Android View support", async () => {
  const readme = await readProjectFile("README.md");
  const skillMetadata = await readProjectFile(
    "skills/astrolabe/agents/openai.yaml"
  );

  assert.match(readme, /Android View/);
  assert.match(readme, /ADB/);
  assert.match(readme, /astrolabe-runtime-android/);
  assert.match(readme, /Runtime for Android 2\.0/);
  assert.doesNotMatch(readme, /release preparation/);
  assert.doesNotMatch(readme, /- Android Runtime and Host support\./);
  assert.match(skillMetadata, /running mobile app/);
  assert.doesNotMatch(skillMetadata, /running iOS app/);
});

test("AI client commands reuse the shared installer", async () => {
  const rootPackage = JSON.parse(await readProjectFile("package.json"));
  const packageLock = JSON.parse(await readProjectFile("package-lock.json"));
  const readme = await readProjectFile("README.md");

  const normalizedPackageBins = Object.fromEntries(
    Object.entries(rootPackage.bin).map(([name, path]) => [name, path.replace(/^\.\//, "")])
  );
  assert.deepEqual(packageLock.packages[""].bin, normalizedPackageBins);

  assert.equal(
    rootPackage.scripts["reinstall:codex"],
    "node scripts/install.mjs --client codex"
  );
  assert.equal(
    rootPackage.scripts["update:codex"],
    "node scripts/install.mjs --client codex --repo https://github.com/regulusleow/astrolabe.git"
  );
  assert.equal(
    rootPackage.scripts["reinstall:opencode"],
    "node scripts/install.mjs --client opencode"
  );
  assert.equal(
    rootPackage.scripts["update:opencode"],
    "node scripts/install.mjs --client opencode --repo https://github.com/regulusleow/astrolabe.git"
  );
  assert.equal(
    rootPackage.scripts["reinstall:claude-code"],
    "node scripts/install.mjs --client claude-code"
  );
  assert.equal(
    rootPackage.scripts["update:claude-code"],
    "node scripts/install.mjs --client claude-code --repo https://github.com/regulusleow/astrolabe.git"
  );
  assert.match(readme, /npm run reinstall:codex/);
  assert.match(readme, /npm run update:codex/);
  assert.match(readme, /npm run install:opencode/);
  assert.match(readme, /npm run check:opencode/);
  assert.match(readme, /npm run install:claude-code/);
  assert.match(readme, /npm run check:claude-code/);
});

test("release commands remain available to maintainers", async () => {
  const rootPackage = JSON.parse(await readProjectFile("package.json"));

  assert.equal(
    rootPackage.scripts["version:check"],
    "node scripts/version-sync.mjs --check"
  );
  assert.equal(
    rootPackage.scripts["version:set"],
    "node scripts/version-sync.mjs --set"
  );
  assert.equal(
    rootPackage.scripts["release:prepare"],
    "node scripts/release-prepare.mjs"
  );
});

test("MCP adapter keeps transport, CLI execution, response mapping, and tool registration separated", async () => {
  const indexSource = await readProjectFile("mcp-adapter/src/index.ts");
  const cliSource = await readProjectFile("mcp-adapter/src/inspector-cli.ts");
  const responseSource = await readProjectFile("mcp-adapter/src/tool-response.ts");
  const toolsSource = await readProjectFile("mcp-adapter/src/tools.ts");

  assert.doesNotMatch(indexSource, /node:child_process/);
  assert.doesNotMatch(indexSource, /\.registerTool\(/);
  assert.match(indexSource, /registerInspectorTools/);
  assert.match(cliSource, /export async function runInspector/);
  assert.match(responseSource, /export function toolResponse/);
  assert.match(toolsSource, /export function registerInspectorTools/);
});

test("MCP inspector runner times out hung CLI subprocesses", async () => {
  const cliSource = await readProjectFile("mcp-adapter/src/inspector-cli.ts");

  assert.match(cliSource, /timeoutMs/);
  assert.match(cliSource, /child\.kill\("SIGTERM"\)/);
  assert.match(cliSource, /resolveOnce/);
  assert.match(cliSource, /clearTimeout/);
});

test("Swift CLI keeps entrypoint, command routing, Runtime UI Provider, and JSON output separated", async () => {
  const mainSource = await readProjectFile("Sources/AstrolabeExecutable/main.swift");
  const runnerSource = await readProjectFile("Sources/AstrolabeCLI/CommandLine/CLICommandRunner.swift");
  const hostFactorySource = await readProjectFiles([
    "Sources/AstrolabeIOSHost/AstrolabeIOSHostFactory.swift",
    "Sources/AstrolabeAndroidPlatform/AstrolabeAndroidHostFactory.swift"
  ]);
  const serviceSource = await readProjectFiles([
    "Sources/AstrolabeIOSHost/AstrolabeIOSRuntimeProvider.swift",
    "Sources/AstrolabeAndroidHost/AstrolabeAndroidRuntimeProvider.swift"
  ]);
  const moduleSource = await readProjectFile("Sources/AstrolabeCLI/Runtime/Core/HostPlatformModule.swift");
  const registrySource = await readProjectFile("Sources/AstrolabeCLI/Runtime/Core/HostPlatformModuleRegistry.swift");
  const outputSource = await readProjectFile("Sources/AstrolabeCLI/CommandLine/JSONOutput.swift");

  assert.match(mainSource, /CLICommandRunner\(platformModules:/);
  assert.match(mainSource, /AstrolabeIOSHostFactory\.makePlatformModule/);
  assert.match(mainSource, /AstrolabeAndroidHostFactory\.makePlatformModule/);
  assert.doesNotMatch(mainSource, /ASTInspectorClient/);
  assert.doesNotMatch(mainSource, /RunLoop/);
  assert.match(runnerSource, /struct CLICommandRunner/);
  assert.doesNotMatch(runnerSource, /AstrolabeIOSRuntimeProvider/);
  assert.match(hostFactorySource, /HostPlatformModuleBuilder/);
  assert.match(hostFactorySource, /CLICommandRunner\(platformModules:/);
  assert.match(serviceSource, /final class AstrolabeIOSRuntimeProvider/);
  assert.match(serviceSource, /final class AstrolabeAndroidRuntimeProvider/);
  assert.match(serviceSource, /RuntimeUIProviderTargeting/);
  assert.match(serviceSource, /RuntimeUIHierarchyCapturing/);
  assert.match(serviceSource, /RuntimeUINodeDetailProviding/);
  assert.match(serviceSource, /AstrolabeRuntimeProtocolClientFactory/);
  assert.match(moduleSource, /capabilityImplementationMismatch/);
  assert.match(moduleSource, /incompleteScreenshotRegistration/);
  assert.match(registrySource, /guard let provider = module\.hierarchyCapture/);
  assert.match(registrySource, /unsupportedCapability\(\.hierarchy/);
  assert.match(outputSource, /enum JSONOutput/);
});

test("Swift CLI runner keeps dispatch separate from command implementations", async () => {
  const runnerSource = await readProjectFile("Sources/AstrolabeCLI/CommandLine/CLICommandRunner.swift");
  const groupsSource = await readProjectFiles([
    "Sources/AstrolabeCLI/CommandLine/AppCommandGroup.swift",
    "Sources/AstrolabeCLI/Inspection/NodeInspectionCommandGroup.swift"
  ]);

  assert.match(groupsSource, /private func runListApps/);
  assert.match(groupsSource, /private func runCaptureHierarchy/);
  assert.match(groupsSource, /private func runNodeDetail/);
  assert.match(groupsSource, /private func runCheckNodeDetail/);

  const runBody = extractFunctionBody(runnerSource, "run");
  assert.doesNotMatch(runBody, /service\.fetch/);
  assert.doesNotMatch(runBody, /nodeDetailSummaryBuilder\.buildSummary/);
  assert.doesNotMatch(runBody, /expectationChecker\.check/);
});

test("Swift CLI runner delegates command domains to handlers", async () => {
  const runnerSource = await readProjectFile("Sources/AstrolabeCLI/CommandLine/CLICommandRunner.swift");
  const groupsSource = await readProjectFiles([
    "Sources/AstrolabeCLI/Screenshot/ScreenshotCommandGroup.swift",
    "Sources/AstrolabeCLI/Inspection/NodeInspectionCommandGroup.swift",
    "Sources/AstrolabeCLI/Baseline/BaselineCommandGroup.swift"
  ]);

  assert.match(runnerSource, /CLICommandHandling/);
  assert.match(runnerSource, /commandHandlers/);
  assert.doesNotMatch(runnerSource, /private func runCaptureScreenshot/);
  assert.doesNotMatch(runnerSource, /private func runCheckNodeDetail/);
  assert.match(groupsSource, /struct ScreenshotCommandGroup/);
  assert.match(groupsSource, /struct NodeInspectionCommandGroup/);
  assert.match(groupsSource, /struct BaselineCommandGroup/);
});

test("Swift screenshot provider separates source selection from payload assembly", async () => {
  const providerSource = await readProjectFile("Sources/AstrolabeCLI/Screenshot/Core/ScreenshotProvider.swift");
  const iosProviderSource = await readProjectFile("Sources/AstrolabeIOSScreenshot/IOSSystemScreenshotProvider.swift");
  const androidProviderSource = await readProjectFile("Sources/AstrolabeAndroidScreenshot/AndroidSystemScreenshotProvider.swift");
  const builderSource = await readProjectFile("Sources/AstrolabeScreenshotSupport/SystemScreenshotPayloadBuilder.swift");

  assert.match(providerSource, /protocol PlatformScreenshotProviding/);
  assert.match(providerSource, /private let platformProviders/);
  assert.match(iosProviderSource, /SystemScreenshotPayloadBuilding/);
  assert.match(iosProviderSource, /payloadBuilder/);
  assert.match(iosProviderSource, /struct IOSSystemScreenshotProvider/);
  assert.match(androidProviderSource, /SystemScreenshotPayloadBuilding/);
  assert.match(androidProviderSource, /payloadBuilder/);
  assert.match(builderSource, /struct SystemScreenshotPayloadBuilder/);
  assert.doesNotMatch(iosProviderSource, /"base64": pngData\.base64EncodedString\(\)/);
  assert.doesNotMatch(androidProviderSource, /"base64": pngData\.base64EncodedString\(\)/);
});

test("Swift node queries delegate semantic role classification", async () => {
  const classifierSource = await readProjectFile("Sources/AstrolabeCLI/Inspection/NodeSemanticRoleClassifier.swift");
  const extractorSource = await readProjectFile("Sources/AstrolabeCLI/Hierarchy/HierarchyNodeExtractor.swift");
  const finderSource = await readProjectFile("Sources/AstrolabeCLI/Hierarchy/HierarchyNodeFinder.swift");
  const mcpToolsSource = await readProjectFile("mcp-adapter/src/tools.ts");

  assert.match(classifierSource, /struct NodeSemanticRoleClassifier/);
  assert.match(extractorSource, /NodeSemanticRoleClassifier/);
  assert.match(extractorSource, /"semanticRoles"/);
  assert.match(finderSource, /semanticRoles\(from: node\)/);
  assert.doesNotMatch(finderSource, /"avatar"|"timer"|"countdown"/);

  const swiftRoleBlock = classifierSource.match(/enum NodeSemanticRole[^\{]*\{([\s\S]*?)\n\}\n\nstruct NodeSemanticRoleClassifier/)?.[1] ?? "";
  const swiftRoles = [...swiftRoleBlock.matchAll(/^\s+case (\w+)$/gm)].map((match) => match[1]).sort();
  const typescriptRoleBlock = mcpToolsSource.match(/const semanticRoleValues = \[([\s\S]*?)\] as const;/)?.[1] ?? "";
  const typescriptRoles = [...typescriptRoleBlock.matchAll(/"(\w+)"/g)].map((match) => match[1]).sort();
  assert.deepEqual(typescriptRoles, swiftRoles);
});

test("Swift process command runner avoids pipe buffer deadlocks", async () => {
  const source = await readProjectFile("Sources/AstrolabeIOSScreenshot/DeviceIdentifierResolver.swift");

  assert.match(source, /FileHandle\(forWritingTo:/);
  assert.doesNotMatch(source, /Pipe\(\)/);
});

test("maintained Swift files use the standard file header", async () => {
  const swiftFiles = await collectFiles(resolve(projectRoot, "Sources"), ".swift");

  for (const filePath of swiftFiles) {
    const relativePath = filePath.slice(projectRoot.length + 1);
    const source = await readFile(filePath, "utf8");
    const fileName = relativePath.split("/").at(-1);
    assert.match(
      source,
      new RegExp(`^//\\n//  ${escapeRegExp(fileName)}\\n//  astrolabe\\n//\\n//  Created by 轩辕十四 on \\d{4}/\\d{1,2}/\\d{1,2}\\.\\n//\\n`),
      `${relativePath} is missing the standard file header`
    );
  }
});

test("production Host registers only Astrolabe Runtime platform providers", async () => {
  const mainSource = await readProjectFile("Sources/AstrolabeExecutable/main.swift");
  const hostFactorySource = await readProjectFiles([
    "Sources/AstrolabeIOSHost/AstrolabeIOSHostFactory.swift",
    "Sources/AstrolabeAndroidPlatform/AstrolabeAndroidHostFactory.swift"
  ]);

  assert.match(hostFactorySource, /let provider = AstrolabeIOSRuntimeProvider\(\)/);
  assert.match(hostFactorySource, /let provider = AstrolabeAndroidRuntimeProvider\(\)/);
  assert.match(mainSource, /AstrolabeIOSHostFactory\.makePlatformModule/);
  assert.match(mainSource, /AstrolabeAndroidHostFactory\.makePlatformModule/);
  assert.doesNotMatch(hostFactorySource, /IOSRuntimeUIProvider/);
  assert.doesNotMatch(hostFactorySource, /RuntimeDiagnosticCommandGroup/);
});

test("Host core and iOS platform sources use independent SwiftPM boundaries", async () => {
  const packageSource = await readProjectFile("Package.swift");
  const coreFiles = await collectFiles(resolve(projectRoot, "Sources/AstrolabeCLI"), ".swift");
  const coreSource = (await Promise.all(coreFiles.map((path) => readFile(path, "utf8")))).join("\n");

  assert.match(packageSource, /path: "Sources\/AstrolabeIOSHost"/);
  assert.match(packageSource, /path: "Sources\/AstrolabeIOSInspection"/);
  assert.match(packageSource, /path: "Sources\/AstrolabeIOSScreenshot"/);
  assert.match(packageSource, /name: "AstrolabeIOSHostTests"/);
  assert.doesNotMatch(packageSource, /exclude:/);
  assert.doesNotMatch(coreSource, /UIKit|NSLayoutConstraint|autoLayout|simctl|devicectl|usbmux/i);
});

test("ObjC core exposes only Astrolabe USB mux symbols", async () => {
  const transportSource = await readProjectFile("Sources/AstrolabeCoreObjC/ASTUSBMuxTransport.m");
  const hubSource = await readProjectFile("Sources/AstrolabeCoreObjC/USBMux/ASTUSBHub.m");

  assert.match(transportSource, /ASTUSBHub/);
  assert.match(hubSource, /@implementation ASTUSBHub/);
  const legacyLookinReference = /\bLookin_[A-Za-z0-9_]*\b|#import\s+["<][^">]*Lookin/;
  assert.doesNotMatch(transportSource, legacyLookinReference);
  assert.doesNotMatch(hubSource, legacyLookinReference);
});

async function readProjectFile(relativePath) {
  return await readFile(resolve(projectRoot, relativePath), "utf8");
}

async function readProjectFiles(relativePaths) {
  return (await Promise.all(relativePaths.map(readProjectFile))).join("\n");
}

async function collectFiles(directory, extension) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const fullPath = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      return await collectFiles(fullPath, extension);
    }
    return entry.isFile() && entry.name.endsWith(extension) ? [fullPath] : [];
  }));
  return files.flat().sort();
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function extractFunctionBody(source, functionName) {
  const signature = `func ${functionName}(`;
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `Function not found: ${functionName}`);
  const firstBrace = source.indexOf("{", start);
  assert.notEqual(firstBrace, -1, `Function body not found: ${functionName}`);

  let depth = 0;
  for (let index = firstBrace; index < source.length; index += 1) {
    if (source[index] === "{") {
      depth += 1;
    }
    if (source[index] === "}") {
      depth -= 1;
      if (depth === 0) {
        return source.slice(firstBrace + 1, index);
      }
    }
  }
  throw new Error(`Incomplete function body: ${functionName}`);
}
