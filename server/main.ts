import express from "express";
import agentQueryRouter from "./routes/agent/query";

const app = express();
const port = 3000;

app.use(express.json());

app.get("/health", (_req, res) => {
  res.status(200).json({ ok: true });
});

app.use("/agent/query", agentQueryRouter);

app.use((_req, res) => {
  res.status(404).json({
    ok: false,
    error: "Not found",
  });
});

app.listen(port, () => {
  console.log(`Server listening on http://localhost:${port}`);
});
