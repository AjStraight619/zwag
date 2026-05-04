import { StateGraph, START, END } from "@langchain/langgraph";
import { ToolNode, toolsCondition } from "@langchain/langgraph/prebuilt";

import { AgentState, AgentContext } from "./state";
import { agentNode } from "./nodes/agent";
import { checkpointer } from "./checkpointer";
import { READ_ONLY_TOOLS } from "../tools";

let compiled: ReturnType<typeof build> | null = null;

function build() {
  const toolNode = new ToolNode([...READ_ONLY_TOOLS]);

  const graph = new StateGraph(AgentState, AgentContext)
    .addNode("agent", agentNode)
    .addNode("tools", toolNode)
    .addEdge(START, "agent")
    .addConditionalEdges("agent", toolsCondition, {
      tools: "tools",
      [END]: END,
    })
    .addEdge("tools", "agent");

  return graph.compile({ checkpointer });
}

export function getGraph() {
  if (!compiled) compiled = build();
  return compiled;
}
