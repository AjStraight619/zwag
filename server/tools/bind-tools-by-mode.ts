import { ChatOpenAI } from "@langchain/openai";
import { READ_ONLY_TOOLS } from "./index";

export type AgentMode = "plan" | "edit" | "ask";

export function bindToolsByMode(model: ChatOpenAI, mode: AgentMode) {
  switch (mode) {
    case "ask":
    case "plan":
    case "edit":
      return model.bindTools([...READ_ONLY_TOOLS]);
  }
}
