import { tool } from "langchain";
import * as z from "zod";

export const readFile = tool({
  name: "read_file",
  description: [
    "Read a file from the user's local filesystem.",
    "Returns the file contents formatted as `LINE_NUMBER|content` so you can",
    "reference exact lines in subsequent edits.",
    "",
    "If `offset` and `limit` are omitted, the entire file is returned.",
    "Use `offset` (1-indexed) and `limit` for large files. A negative `offset`",
    "counts backwards from the end of the file (e.g. -50 with limit=50 returns",
    "the last 50 lines).",
  ].join(" "),
  schema: z.object({
    path: z
      .string()
      .min(1)
      .describe("Absolute path to the file. Relative paths are resolved against the user's cwd."),
    offset: z
      .number()
      .int()
      .optional()
      .describe(
        "1-indexed starting line. Negative values count from the end of the file. Omit to start at line 1.",
      ),
    limit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Maximum number of lines to return. Omit to read to end of file."),
  }),
});
