import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve, extname, sep } from "node:path";
import { pathToFileURL } from "node:url";

export function serve(root = "build/odin-player/web", port = 8080) {
  const base = resolve(root);
  const types = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript",
    ".wasm": "application/wasm",
    ".png": "image/png",
    ".data": "application/octet-stream",
  };
  const server = createServer(async (request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
      const file = resolve(base, `.${pathname === "/" ? "/player.html" : pathname}`);
      if (!file.startsWith(base + sep)) {
        response.writeHead(403).end();
        return;
      }
      const data = await readFile(file);
      response.writeHead(200, {
        "Content-Type": types[extname(file)] || "application/octet-stream",
        "Cache-Control": "no-store",
      });
      response.end(data);
    } catch {
      response.writeHead(404).end("Not found");
    }
  });
  server.listen(port, "127.0.0.1");
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const server = serve(process.argv[2], Number(process.env.PORT || 8080));
  server.on("listening", () =>
    console.log(`Player: http://127.0.0.1:${server.address().port}/player.html`),
  );
  server.on("error", (error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
