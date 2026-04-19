import type { ErrorRequestHandler } from "express";

export type AppErrorType =
  | "VALIDATION_ERROR"
  | "UNSUPPORTED_PROVIDER"
  | "INTERNAL_ERROR";

export class AppError extends Error {
  public readonly type: AppErrorType;
  public readonly statusCode: number;
  public readonly details?: unknown;

  constructor(args: {
    type: AppErrorType;
    message: string;
    statusCode?: number;
    details?: unknown;
  }) {
    super(args.message);
    this.name = "AppError";
    this.type = args.type;
    this.statusCode = args.statusCode ?? 500;
    this.details = args.details;
  }
}

export const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  if (err instanceof AppError) {
    switch (err.type) {
      case "VALIDATION_ERROR":
        return res.status(err.statusCode).json({
          ok: false,
          error: err.message,
          details: err.details ?? null,
        });

      case "UNSUPPORTED_PROVIDER":
        return res.status(err.statusCode).json({
          ok: false,
          error: err.message,
        });

      case "INTERNAL_ERROR":
      default:
        return res.status(err.statusCode).json({
          ok: false,
          error: err.message,
        });
    }
  }

  console.error(err);

  return res.status(500).json({
    ok: false,
    error: "Internal server error",
  });
};
