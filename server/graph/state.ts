import { StateSchema, MessagesValue, ReducedValue } from "@langchain/langgraph";
import * as z from "zod";

export const SUPPORTED_MODES = ["plan", "edit", "ask"] as const;
export const SUPPORTED_PROVIDERS = ["openai"] as const;
export const SUPPORTED_MODELS = [
  "gpt-4.1",
  "gpt-4.1-mini",
  "gpt-5.4-mini",
] as const;

export const ModeSchema = z.enum(SUPPORTED_MODES);
export const ProviderSchema = z.enum(SUPPORTED_PROVIDERS);
export const ModelNameSchema = z.enum(SUPPORTED_MODELS);

export type Mode = z.infer<typeof ModeSchema>;
export type Provider = z.infer<typeof ProviderSchema>;
export type ModelName = z.infer<typeof ModelNameSchema>;

export const AgentState = new StateSchema({
  messages: MessagesValue,
  llmCalls: new ReducedValue(z.number().default(0), {
    reducer: (left: number, right: number) => left + right,
  }),
});

export const AgentContext = z.object({
  mode: ModeSchema,
  provider: ProviderSchema,
  modelName: ModelNameSchema,
});

export type AgentContextType = z.infer<typeof AgentContext>;
