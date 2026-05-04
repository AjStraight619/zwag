import { tool } from "langchain";
import * as z from "zod";

export const listDir = tool({
  name: "list_dir",
  description: [
    "List the contents of a directory on the user's filesystem.",
    "Returns each entry's name, type (file or dir), size in bytes, and last-modified timestamp.",
    "Prefer this over `glob` when you just want to discover what's in a directory.",
  ].join(" "),
  schema: z.object({
    path: z
      .string()
      .min(1)
      .describe("Absolute path to the directory. Relative paths are resolved against the user's cwd."),
    depth: z
      .number()
      .int()
      .min(1)
      .max(8)
      .default(1)
      .describe("How many levels deep to recurse. 1 means only the immediate children."),
    showHidden: z
      .boolean()
      .default(false)
      .describe("Include dotfiles and dot-directories."),
  }),
});
