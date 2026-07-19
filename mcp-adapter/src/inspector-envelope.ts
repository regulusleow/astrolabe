import { z } from "zod";

export const inspectorEnvelopeSchemaVersion = 4;

export const inspectorToolOutputSchema = {
  /** Astrolabe CLI JSON envelope schema version. */
  schemaVersion: z.literal(inspectorEnvelopeSchemaVersion).describe("Astrolabe CLI JSON envelope schema version"),

  /** Executed Astrolabe CLI command. */
  command: z.string().min(1).optional().describe("Executed Astrolabe CLI command"),

  /** Whether the command completed successfully. */
  success: z.boolean().describe("Whether the command completed successfully"),

  /** Command-specific structured data. */
  data: z.unknown().optional().describe("Command-specific structured data"),

  /** Stable machine-readable failure code. */
  errorCode: z.string().min(1).optional().describe("Stable machine-readable failure code"),

  /** Human-readable failure message. */
  error: z.string().min(1).optional().describe("Human-readable failure message"),

  /** Actionable recovery guidance. */
  recoverySuggestion: z.string().min(1).optional().describe("Actionable recovery guidance"),

  /** Bounded CLI standard output included only for Adapter failures. */
  stdout: z.string().optional().describe("CLI standard output included for Adapter failures"),

  /** Bounded CLI standard error included only for Adapter failures. */
  stderr: z.string().optional().describe("CLI standard error included for Adapter failures")
};

const inspectorEnvelopeSchema = z.object({
  ...inspectorToolOutputSchema,
  command: z.string().min(1)
}).passthrough().superRefine((value, context) => {
  if (value.success && value.data === undefined) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["data"],
      message: "A successful response must contain data"
    });
  }
  if (!value.success) {
    for (const field of ["errorCode", "error", "recoverySuggestion"] as const) {
      if (!value[field]) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          path: [field],
          message: "A failed response must contain actionable diagnostics"
        });
      }
    }
  }
});

export type InspectorEnvelope = z.infer<z.ZodObject<typeof inspectorToolOutputSchema>>;

export type InspectorEnvelopeParseResult = {
  /** Parsed and validated CLI envelope. */
  envelope?: InspectorEnvelope;

  /** Stable parsing failure code. */
  errorCode?: string;

  /** Chinese parsing failure message. */
  error?: string;

  /** Action the caller can take to recover. */
  recoverySuggestion?: string;
};

export function parseInspectorEnvelope(stdout: string): InspectorEnvelopeParseResult {
  let value: unknown;
  try {
    value = JSON.parse(stdout);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      errorCode: "mcp_adapter_invalid_cli_json",
      error: `Failure: unable to parse Astrolabe Host JSON output: ${message}`,
      recoverySuggestion: "Reinstall Astrolabe Host and check whether other output is contaminating Host stdout"
    };
  }

  const parsed = inspectorEnvelopeSchema.safeParse(value);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    const path = issue?.path.length ? issue.path.join(".") : "root";
    return {
      errorCode: "mcp_adapter_invalid_cli_envelope",
      error: `Failure: Astrolabe Host JSON violates the response contract: ${path} ${issue?.message ?? "unknown field error"}`,
      recoverySuggestion: "Ensure the MCP Adapter and Astrolabe Host come from the same installation version"
    };
  }
  return { envelope: parsed.data };
}
