#!/usr/bin/env node

const http = require("node:http");

const port = Number.parseInt(process.argv[2] ?? "", 10);
if (!Number.isFinite(port) || port <= 0) {
  process.exit(1);
}

let body = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  body += chunk;
});

process.stdin.on("end", () => {
  const request = http.request(
    {
      hostname: "127.0.0.1",
      port,
      path: "/hook/session-start",
      method: "POST",
      headers: {
        "content-type": "application/json",
        "content-length": Buffer.byteLength(body),
      },
    },
    (response) => {
      response.resume();
      response.on("end", () => {
        process.exit(response.statusCode && response.statusCode < 400 ? 0 : 1);
      });
    },
  );

  request.on("error", () => {
    process.exit(1);
  });

  request.end(body);
});
