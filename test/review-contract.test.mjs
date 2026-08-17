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

test("Astrolabe skill keeps UI graph inspection bounded to one frozen snapshot", async () => {
  const skill = await readProjectFile("skills/astrolabe/SKILL.md");

  assert.match(skill, /uiGraphRelations/);
  assert.match(
    skill,
    /capture_hierarchy[\s\S]*query_ui_graph[\s\S]*summarize_node_detail/
  );
  assert.match(skill, /truncationReasons/);
  assert.match(skill, /frontierOids/);
  assert.match(skill, /omittedFrontierCount/);
  assert.match(skill, /same `appId` and `snapshotId`/);
  assert.doesNotMatch(skill, /`ios_query_ui_graph`|`android_query_ui_graph`/);
});

test("Astrolabe skill loads advanced inspection guidance progressively", async () => {
  const skill = await readProjectFile("skills/astrolabe/SKILL.md");

  assert.ok(
    skill.split("\n").length <= 260,
    "core skill should stay bounded while advanced workflows live in references"
  );
  assert.match(skill, /references\/rendered-content\.md/);
  assert.match(skill, /references\/ui-graph\.md/);
  assert.match(skill, /references\/visual-regression\.md/);
  assert.match(skill, /references\/temporary-patches\.md/);
});

test("Astrolabe skill gates design verification on target readiness and complete design evidence", async () => {
  const skill = await readProjectFile("skills/astrolabe/SKILL.md");
  const guidance = await readProjectFile(
    "skills/astrolabe/references/design-verification.md"
  ).catch(() => "");
  const evals = await readProjectFile("skills/astrolabe/evals/evals.json").catch(() => "");

  assert.ok(skill.split("\n").length <= 260);
  assert.match(skill, /design-verification\.md/);
  assert.match(skill, /Target State Readiness/i);
  assert.match(skill, /fresh[\s\S]*formal acceptance[\s\S]*snapshot/i);
  assert.match(skill, /before readiness.*do not issue.*passed.*failed.*inconclusive/is);
  assert.match(skill, /visible normal UI/i);
  assert.match(skill, /App Router|private initializer|unapproved deep link/i);
  assert.match(skill, /presentation-only/i);
  assert.match(skill, /snapshot.*preliminary.*discard|discard.*preliminary.*snapshot/is);
  assert.match(skill, /Design Expectations.*Coverage Ledger.*before.*checks/is);
  assert.match(skill, /formal acceptance.*after readiness.*passed.*failed.*inconclusive/is);

  assert.match(guidance, /Design source priority/i);
  assert.match(guidance, /Target Context/i);
  assert.match(guidance, /Design Expectation/i);
  assert.match(guidance, /current Target Context.*current device.*sufficient/is);
  assert.match(guidance, /do not\s+automatically.*another device/is);
  assert.match(guidance, /Other viewports.*neither blocks.*passed.*inconclusive/is);
  for (const policy of [
    "exact",
    "minimum",
    "maximum",
    "range",
    "relation",
    "derived",
    "conditional"
  ]) {
    assert.match(guidance, new RegExp(`\\b${policy}\\b`, "i"));
  }
  assert.match(guidance, /tolerance.*measurement error/i);
  assert.match(guidance, /fixed.*flexible|flexible.*fixed/is);
  assert.match(guidance, /1\s*\/\s*displayScale/i);
  assert.match(guidance, /one physical\s+pixel/i);
  assert.match(guidance, /raw `actual`/i);
  assert.match(guidance, /never.*layout flexibility/is);
  assert.match(guidance, /unique node|coordinate.*evidence/i);
  assert.match(guidance, /Coverage Ledger/i);
  assert.match(guidance, /screenshot.*contradiction|contradiction.*screenshot/is);
  assert.match(guidance, /required failed.*failed/is);
  assert.match(guidance, /required inconclusive.*unchecked.*inconclusive/is);
  assert.match(guidance, /notApplicable/);
  assert.match(guidance, /authoritative contract.*does not apply.*current conditions/is);
  assert.match(guidance, /notApplicable.*neither.*unchecked.*blocks.*passed/is);
  assert.match(guidance, /20x20/);
  assert.match(guidance, /leading.*15/i);
  assert.match(guidance, /Avatar-to-Title.*10/i);
  assert.match(guidance, /Title-to-CallIcon.*minimum.*10/i);
  assert.match(guidance, /centerY/i);

  const evalCatalog = JSON.parse(evals);
  assert.ok(Array.isArray(evalCatalog.evals));
  const evalsByID = new Map(evalCatalog.evals.map((entry) => [entry.id, entry]));
  for (const id of [
    "fixed-spacing-failure",
    "legal-adaptive-spacing",
    "missing-adaptive-contract",
    "ambiguous-selector",
    "image-center-mode-overflow",
    "target-absent-ios-physical-device",
    "authorized-mock-presentation-only",
    "exact-policy-pass",
    "exact-policy-fail",
    "minimum-policy-pass",
    "minimum-policy-fail",
    "maximum-policy-pass",
    "maximum-policy-fail",
    "range-policy-pass",
    "range-policy-fail",
    "relation-policy-pass",
    "relation-policy-fail",
    "derived-policy-pass",
    "derived-policy-fail",
    "conditional-policy-pass",
    "conditional-policy-fail",
    "contact-cell-scale2-quantization-fixed-gap-regression"
  ]) {
    assert.ok(evalsByID.has(id), `missing stable eval: ${id}`);
  }
  for (const entry of evalCatalog.evals) {
    assert.equal(typeof entry.prompt, "string");
    assert.equal(typeof entry.expected_output, "string");
    assert.ok(Array.isArray(entry.files));
  }
  assert.match(evalsByID.get("image-center-mode-overflow").prompt, /27x27/);
  assert.match(evalsByID.get("image-center-mode-overflow").prompt, /54x54/);
  assert.match(evalsByID.get("image-center-mode-overflow").prompt, /fully contained/i);
  const quantizationEval = evalsByID.get(
    "contact-cell-scale2-quantization-fixed-gap-regression"
  );
  assert.match(quantizationEval.prompt, /displayScale 2/i);
  assert.match(quantizationEval.prompt, /-0\.25/);
  assert.match(quantizationEval.prompt, /Avatar-to-Title.*18/i);
});

test("Astrolabe skill separates rendered content from its layout container", async () => {
  const skill = await readProjectFile("skills/astrolabe/SKILL.md");
  const guidance = await readProjectFile(
    "skills/astrolabe/references/rendered-content.md"
  ).catch(() => "");
  const contract = `${skill}\n${guidance}`;

  assert.match(contract, /layout box/i);
  assert.match(contract, /rendered footprint/i);
  assert.match(contract, /intrinsic content/i);
  assert.match(contract, /mapping policy/i);
  assert.match(contract, /clipping or masking/i);
  assert.match(contract, /transform or visual effect/i);
  assert.match(contract, /cannot produce `passed`/i);
  assert.match(contract, /imageSize/);
  assert.match(contract, /contentMode/);
});

test("Astrolabe skill distinguishes UI graph tool and Runtime failures", async () => {
  const guidance = await readProjectFile(
    "skills/astrolabe/references/ui-graph.md"
  ).catch(() => "");

  assert.match(guidance, /Tool is unavailable/i);
  assert.match(guidance, /uiGraphRelations/);
  assert.match(guidance, /invalid_ui_graph_snapshot/);
  assert.match(guidance, /ui_graph_node_not_found/);
  assert.match(guidance, /capture_hierarchy.*same `snapshotId`/is);
});

test("Astrolabe skill metadata covers rendered content and UI relations", async () => {
  const skill = await readProjectFile("skills/astrolabe/SKILL.md");
  const metadata = await readProjectFile(
    "skills/astrolabe/agents/openai.yaml"
  );

  assert.match(skill.slice(0, skill.indexOf("---", 4)), /rendered content/i);
  assert.match(skill.slice(0, skill.indexOf("---", 4)), /UI relations/i);
  assert.match(metadata, /rendered content/i);
  assert.match(metadata, /UI relations/i);
});

test("Astrolabe skill does not treat node details as an atomic hierarchy snapshot", async () => {
  const skill = await readProjectFile("skills/astrolabe/SKILL.md");

  assert.match(skill, /detailSource/);
  assert.match(skill, /snapshotCache/);
  assert.match(skill, /liveRuntime/);
  assert.match(skill, /detailCapturedAtUnixTime/);
  assert.match(skill, /not.*atomic|not.*same capture time/is);
});

test("Astrolabe skill rejects absence conclusions from a truncated hierarchy", async () => {
  const skill = await readProjectFile("skills/astrolabe/SKILL.md");

  assert.match(skill, /summarize_hierarchy/);
  assert.match(skill, /maxDepth/);
  assert.match(skill, /nodeCount/);
  assert.match(skill, /returnedNodeCount/);
  assert.match(skill, /omittedNodeCount/);
  assert.match(skill, /truncated/);
  assert.match(skill, /not.*(?:absent|missing).*truncated/is);
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
  assert.equal(rootPackage.scripts["update:codex"], undefined);
  assert.equal(
    rootPackage.scripts["reinstall:opencode"],
    "node scripts/install.mjs --client opencode"
  );
  assert.equal(rootPackage.scripts["update:opencode"], undefined);
  assert.equal(
    rootPackage.scripts["reinstall:claude-code"],
    "node scripts/install.mjs --client claude-code"
  );
  assert.equal(rootPackage.scripts["update:claude-code"], undefined);
  assert.match(readme, /npm run reinstall:codex/);
  assert.doesNotMatch(readme, /npm run update:codex/);
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
