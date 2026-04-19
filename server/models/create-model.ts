import { AppError } from "../error";
import { createOpenAIModel, type SupportedOpenAIModel } from "./openai";

export type SupportedProvider = "openai";

export type CreateModelInput =
  | {
    provider: "openai";
    modelName: SupportedOpenAIModel;
  };

export function createModel(input: CreateModelInput) {
  switch (input.provider) {
    case "openai":
      return createOpenAIModel(input.modelName);
    default:
      throw new AppError({
        type: "UNSUPPORTED_PROVIDER",
        message: `Unsupported provider: ${(input as { provider?: string }).provider ?? "unknown"}`,
        statusCode: 400,
      });
  }
}
