import type { Runtime } from "@langchain/langgraph";
import { AgentState, type AgentContextType } from "../state";
import { createModel } from "../../models/create-model";
import { bindToolsByMode } from "../../tools/bind-tools-by-mode";

// Typed manually because AgentState.Node has no context generic slot.
export const agentNode = async (
  state: typeof AgentState.State,
  runtime: Runtime<AgentContextType>,
): Promise<typeof AgentState.Update> => {
  const { provider, modelName, mode } = runtime.context!;

  const model = createModel({ provider, modelName });
  const modelWithTools = bindToolsByMode(model, mode);

  const response = await modelWithTools.invoke(state.messages);

  return {
    messages: [response],
    llmCalls: 1,
  };
};
