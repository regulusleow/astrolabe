import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { readPackageVersion } from "./package-metadata.js";
import { registerInspectorTools } from "./tools.js";

const currentDir = dirname(fileURLToPath(import.meta.url));
const defaultInspectorBin = resolve(currentDir, "../../.build/debug/astrolabe");
const inspectorBin = process.env.ASTROLABE_BIN ?? defaultInspectorBin;

const version = readPackageVersion();
const server = new McpServer({
  name: "astrolabe",
  version
});

registerInspectorTools(server, inspectorBin);

async function main(): Promise<void> {
  if (process.argv[2] === "--doctor-probe") {
    process.stdout.write(`${JSON.stringify({ version })}\n`);
    return;
  }
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Failed: MCP server startup failed: ${message}`);
  process.exit(1);
});
