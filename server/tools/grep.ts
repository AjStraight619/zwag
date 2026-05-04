import { tool } from "langchain";
import * as z from "zod";

export const grep = tool({
  name: "grep",
  description: [
    "Regex search across files using ripgrep on the user's machine.",
    "Use `outputMode` to control what comes back:",
    "- `content` (default): matching lines, optionally with context",
    "- `files_with_matches`: just the file paths that contain a match",
    "- `count`: per-file match counts",
    "Combine with `glob` or `type` to narrow the search. Use `headLimit`+`offset` to paginate large result sets.",
  ].join(" "),
  schema: z.object({
    pattern: z.string().min(1).describe("Regex pattern (ripgrep syntax)."),
    path: z
      .string()
      .optional()
      .describe("File or directory to search in. Defaults to the user's cwd."),
    glob: z
      .string()
      .optional()
      .describe("Glob filter (e.g. `*.ts`, `*.{js,tsx}`)."),
    type: z
      .string()
      .optional()
      .describe("Ripgrep file-type filter (e.g. `js`, `py`, `rust`)."),
    caseInsensitive: z.boolean().default(false).describe("Case-insensitive match (`-i`)."),
    outputMode: z
      .enum(["content", "files_with_matches", "count"])
      .default("content")
      .describe("Result format. Defaults to `content`."),
    linesBefore: z
      .number()
      .int()
      .min(0)
      .optional()
      .describe("Lines of context before each match. Only honored when outputMode is `content`."),
    linesAfter: z
      .number()
      .int()
      .min(0)
      .optional()
      .describe("Lines of context after each match. Only honored when outputMode is `content`."),
    linesContext: z
      .number()
      .int()
      .min(0)
      .optional()
      .describe("Lines of context both before and after. Only honored when outputMode is `content`."),
    headLimit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe(
        "Cap the number of results. For `content`: total matches. For `files_with_matches` and `count`: number of files.",
      ),
    offset: z
      .number()
      .int()
      .min(0)
      .optional()
      .describe("Skip the first N entries. Pair with `headLimit` for pagination."),
    multiline: z
      .boolean()
      .default(false)
      .describe("Allow patterns to match across line boundaries (`-U --multiline-dotall`)."),
    showLineNumbers: z
      .boolean()
      .default(true)
      .describe("Prefix each result line with its line number. Only honored when outputMode is `content`."),
  }),
});
