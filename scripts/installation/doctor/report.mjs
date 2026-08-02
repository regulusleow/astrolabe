import { collectDiagnosticFacts } from "./collectors.mjs";
import { sanitizeDiagnosticReport } from "./redactor.mjs";

export async function buildDiagnosticReport(context) {
  const rawReport = await collectDiagnosticFacts(context);
  return sanitizeDiagnosticReport(rawReport, {
    homeDirectory: context.homeDirectory
  });
}

export function renderHumanReport(report, { verbose = false } = {}) {
  const lines = report.checks.map((item) => (
    `${item.label.padEnd(28)} ${item.status}`
  ));
  if (verbose) {
    lines.push("", ...report.checks.map((item) => `${item.id}: ${item.detail}`));
  }
  lines.push("", "Review this report before sharing it publicly.");
  return `${lines.join("\n")}\n`;
}

export function renderJSONReport(report) {
  return `${JSON.stringify(report, null, 2)}\n`;
}
