import type { Response } from "express";
import type { AIMessageChunk } from "@langchain/core/messages";
import type { IterableReadableStream } from "@langchain/core/utils/stream";

export type RunOutcome = "done" | "interrupted" | "error";

export function writeSseEvent(res: Response, event: string, data: unknown) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

export function writeSseHeaders(res: Response) {
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();
}

type MessagesChunk = [AIMessageChunk, { langgraph_node?: string }];
type InterruptEntry = { id?: string; value: unknown };
type UpdatesChunk = Record<string, unknown> & {
  __interrupt__?: ReadonlyArray<InterruptEntry>;
};

export async function streamGraphToSse(
  res: Response,
  stream: IterableReadableStream<unknown>,
): Promise<RunOutcome> {
  let outcome: RunOutcome = "done";

  for await (const entry of stream) {
    const [mode, chunk] = entry as [string, unknown];
    if (mode === "messages") {
      const [msg, metadata] = chunk as MessagesChunk;
      if (metadata?.langgraph_node !== "agent") continue;

      const content = typeof msg.content === "string" ? msg.content : "";
      if (content) writeSseEvent(res, "token", { content });
      continue;
    }

    if (mode === "updates") {
      const update = chunk as UpdatesChunk;
      const interrupts = update.__interrupt__;
      if (!interrupts?.length) continue;

      outcome = "interrupted";
      for (const entry of interrupts) {
        const value = entry.value as
          | {
              type?: string;
              toolCall?: { id?: string; name?: string; args?: unknown };
            }
          | undefined;

        if (value?.type === "tool" && value.toolCall) {
          writeSseEvent(res, "tool_call", {
            interruptId: entry.id,
            toolCallId: value.toolCall.id,
            name: value.toolCall.name,
            args: value.toolCall.args,
          });
        } else {
          writeSseEvent(res, "interrupt", {
            interruptId: entry.id,
            value,
          });
        }
      }
    }
  }

  return outcome;
}
