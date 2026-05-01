const http = require("node:http");
const { Worker, NativeConnection } = require("@temporalio/worker");
const activities = require("./activities");

const port = Number(process.env.PORT || "8095");
const temporalAddress = process.env.TEMPORAL_ADDRESS || "temporal-frontend.temporal.svc.cluster.local:7233";
const namespace = process.env.SOUNIO_TEMPORAL_NAMESPACE || "beagle";
const taskQueue = process.env.SOUNIO_TEMPORAL_TASK_QUEUE || "sounio-paperrun";
const workerEnabled = process.env.SOUNIO_TEMPORAL_WORKER_ENABLED !== "false";

const state = {
  started_at: new Date().toISOString(),
  worker_enabled: workerEnabled,
  temporal_address: temporalAddress,
  namespace,
  task_queue: taskQueue,
  worker_status: "starting",
  last_error: null,
};

function respond(res, code, payload) {
  res.writeHead(code, { "content-type": "application/json" });
  res.end(JSON.stringify(payload));
}

http
  .createServer((req, res) => {
    if (req.url === "/health") {
      respond(res, 200, { status: "ok", service: "sounio-runner" });
      return;
    }
    if (req.url === "/ready") {
      const ready = !workerEnabled || state.worker_status === "running";
      respond(res, ready ? 200 : 503, {
        status: ready ? "ready" : "degraded",
        ...state,
      });
      return;
    }
    respond(res, 404, { error: "not_found" });
  })
  .listen(port, () => {
    console.log(JSON.stringify({ level: "info", msg: "sounio-runner http listening", port }));
  });

async function startWorker() {
  if (!workerEnabled) {
    state.worker_status = "disabled";
    return;
  }
  try {
    const connection = await NativeConnection.connect({ address: temporalAddress });
    const worker = await Worker.create({
      connection,
      namespace,
      taskQueue,
      workflowsPath: require.resolve("./workflows"),
      activities,
    });
    state.worker_status = "running";
    await worker.run();
  } catch (error) {
    state.worker_status = "degraded";
    state.last_error = error?.message || String(error);
    console.error(JSON.stringify({ level: "error", msg: "sounio-runner worker failed", error: state.last_error }));
  }
}

startWorker();
