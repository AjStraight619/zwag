import { Router } from "express";
import { z } from "zod";
import { Command } from "@langchain/langgraph";

import { AppError } from "../../error";
import { getGraph } from "../../graph/build-graph";
import { ModeSchema, ProviderSchema, ModelNameSchema } from "../../graph/state";
import {
  streamGraphToSse,
  writeSseEvent,
  writeSseHeaders,
  type RunOutcome,
} from "./sse";

const router = Router();

// mode/provider/modelName must be re-sent: they live in `configurable`, not
// in the checkpointed state.
const ResumeBase = z.object({
  threadId: z.string().min(1),
  mode: ModeSchema,
  provider: ProviderSchema,
  modelName: ModelNameSchema,
});

const ResumeRequestSchema = z.union([
  ResumeBase.extend({ resume: z.unknown() }),
  ResumeBase.extend({ resumeMap: z.record(z.string(), z.unknown()) }),
]);

router.post("/", async (req, res) => {
  const parsed = ResumeRequestSchema.safeParse(req.body);

  if (!parsed.success) {
    throw new AppError({
      type: "VALIDATION_ERROR",
      message: "Invalid resume body",
      statusCode: 400,
      details: z.flattenError(parsed.error),
    });
  }

  const body = parsed.data;
  const resumeValue = "resumeMap" in body ? body.resumeMap : body.resume;

  writeSseHeaders(res);
  writeSseEvent(res, "run_started", { threadId: body.threadId, resumed: true });

  let outcome: RunOutcome = "done";
  try {
    const graph = getGraph();
    const stream = await graph.stream(new Command({ resume: resumeValue }), {
      streamMode: ["messages", "updates"],
      configurable: {
        thread_id: body.threadId,
        mode: body.mode,
        provider: body.provider,
        modelName: body.modelName,
      },
    });

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
