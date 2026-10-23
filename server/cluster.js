const cluster = require('cluster');
const os = require('os');
const path = require('path');

const numCPUs = process.env.WEB_CONCURRENCY ? parseInt(process.env.WEB_CONCURRENCY, 10) : os.cpus().length;

if (cluster.isPrimary) {
  console.log(`[Master ${process.pid}] Starting ${numCPUs} Fastify worker instances for 1M req/s throughput scale...`);

  // Fork workers
  for (let i = 0; i < numCPUs; i++) {
    cluster.fork();
  }

  cluster.on('exit', (worker, code, signal) => {
    console.warn(`[Master] Worker ${worker.process.pid} died (${signal || code}). Respawning immediately...`);
    cluster.fork();
  });
} else {
  // Workers share the TCP connection on port 3000
  require('./server');
  console.log(`[Worker ${process.pid}] Fastify instance initialized.`);
}
