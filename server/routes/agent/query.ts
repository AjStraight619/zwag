import { Router } from "express";
import { randomUUID } from "node:crypto";
import { z } from "zod";

import { AppError } from "../../error";
import { getGraph } from "../../graph/build-graph";
import {
  ModeSchema,
  ProviderSchema,
  ModelNameSchema,
} from "../../graph/state";
import {
  streamGraphToSse,
  writeSseEvent,
  writeSseHeaders,
  type RunOutcome,
} from "./sse";

const router = Router();

const QueryRequestSchema = z.object({
  provider: ProviderSchema,
  modelName: ModelNameSchema,
  mode: ModeSchema,
  prompt: z.string().min(1),
  threadId: z.string().min(1).optional(),
});

router.post("/", async (req, res) => {
  const parsed = QueryRequestSchema.safeParse(req.body);

  if (!parsed.success) {
    throw new AppError({
      type: "VALIDATION_ERROR",
      message: "Invalid request body",
      statusCode: 400,
      details: z.flattenError(parsed.error),
    });
  }

  const { provider, modelName, mode, prompt } = parsed.data;
  const threadId = parsed.data.threadId ?? randomUUID();

  writeSseHeaders(res);
  writeSseEvent(res, "run_started", { threadId, mode });

  let outcome: RunOutcome = "done";
  try {
    const graph = getGraph();
    const stream = await graph.stream(
      { messages: [{ role: "user", content: prompt }] },
      {
        streamMode: ["messages", "updates"],
        configurable: {
          thread_id: threadId,
          mode,
          provider,
          modelName,
        },
      },
    );

    outcome = await streamGraphToSse(res, stream);
  } catch (err) {
    outcome = "error";
    writeSseEvent(res, "error", {
      message: err instanceof Error ? err.message : String(err),
    });
  }

  writeSseEvent(res, "run_ended", { reason: outcome });
  res.end();
});

export default router;
