import { tool } from "langchain";
import * as z from "zod";

export const glob = tool({
  name: "glob",
  description: [
    "Find files by glob pattern. Returns matching paths sorted by modification time (most recent first).",
    "Patterns that don't begin with `**/` are automatically prefixed so the search is recursive by default.",
    "Examples: `*.ts` (all TypeScript files), `src/**/*.test.ts`, `**/node_modules/**`.",
  ].join(" "),
  schema: z.object({
    pattern: z
      .string()
      .min(1)
      .describe("Glob pattern. Auto-prepends `**/` if not present so searches are recursive."),
    targetDirectory: z
      .string()
      .optional()
      .describe(
        "Absolute directory to search within. Defaults to the user's cwd when omitted.",
      ),
  }),
});
