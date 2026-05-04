import { readFile } from "./read-file";
import { listDir } from "./list-dir";
import { glob } from "./glob";
import { grep } from "./grep";

export { readFile, listDir, glob, grep };

export const READ_ONLY_TOOLS = [readFile, listDir, glob, grep] as const;

export type ReadOnlyTool = (typeof READ_ONLY_TOOLS)[number];
