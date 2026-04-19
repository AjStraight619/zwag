import { Router, type Response } from "express";
import { z } from "zod";
import { AppError } from "../../error";
import { createModel } from "../../models/create-model";

const router = Router();

const QueryRequestSchema = z.object({
  provider: z.literal("openai"),
  modelName: z.enum(["gpt-4.1", "gpt-4.1-mini"]),
  prompt: z.string().min(1),
  mode: z.enum(["plan", "edit", "ask"]),
});

type QueryRequest = z.infer<typeof QueryRequestSchema>;

function writeSseEvent(res: Response, event: string, data: unknown) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

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

  const body: QueryRequest = parsed.data;

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");

  res.flushHeaders?.();

  writeSseEvent(res, "run_started", {
    provider: body.provider,
    modelName: body.modelName,
    mode: body.mode,
  });

  const model = createModel({
    provider: body.provider,
    modelName: body.modelName,
  });

  writeSseEvent(res, "status", {
    message: "Model created",
    modelCreated: !!model,
  });

  writeSseEvent(res, "run_completed", { ok: true });
  res.end();
});

export default router;
