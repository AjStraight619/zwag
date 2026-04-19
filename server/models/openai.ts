import { ChatOpenAI, type ChatOpenAIFields } from "@langchain/openai";

export type SupportedOpenAIModel = "gpt-4.1" | "gpt-4.1-mini" | "gpt-5.4-mini";

const DEFAULTS: Partial<ChatOpenAIFields> = {
  temperature: 0,
  maxRetries: 2,

};

export function createOpenAIModel(
  modelName: SupportedOpenAIModel,
  opts: Partial<ChatOpenAIFields> = {},
) {
  return new ChatOpenAI({
    model: modelName,
    ...DEFAULTS,
    ...opts,
  });
}
