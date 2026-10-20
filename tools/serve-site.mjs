import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";
import { repo } from "./toolchain.mjs";

export function serveSite({
  port = 8088,
  host = "127.0.0.1",
  root = resolve(repo, "build/site"),
} = {}) {
  const base = resolve(root);
  const types = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript",
    ".css": "text/css",
    ".json": "application/json",
    ".wasm": "application/wasm",
    ".png": "image/png",
    ".svg": "image/svg+xml",
  };
  const server = createServer(async (request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
      const file = resolve(base, `.${pathname.endsWith("/") ? `${pathname}index.html` : pathname}`);
      if (!file.startsWith(base + sep)) {
        response.writeHead(403).end("Forbidden");
        return;
      }
      const data = await readFile(file);
      response.writeHead(200, {
        "Content-Type": types[extname(file)] || "application/octet-stream",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
      });
      response.end(data);
    } catch {
      response.writeHead(404, { "Content-Type": "text/plain" }).end("Page not found");
    }
  });
  server.listen(port, host);
  return server;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const server = serveSite({
    port: Number(process.env.PORT || 8088),
    host: process.env.HOST || "127.0.0.1",
  });
  server.on("listening", () =>
    console.log(`Site: http://${process.env.HOST || "127.0.0.1"}:${server.address().port}/`),
  );
  server.on("error", (error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
