import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve, extname } from "node:path";

// Interactive playback needs no retained PCM capture; the measurement task saves it.
createServer(async (request, response) => {
  const pathname = new URL(request.url, "http://localhost").pathname;
  if (request.method === "POST" && /^\/capture\/[a-z0-9-]+\.f32$/.test(pathname)) {
    for await (const chunk of request) {
      void chunk;
    }
    response.writeHead(200).end();
    return;
  }
  const name = pathname === "/" ? "index.html" : pathname.slice(1);
  if (!/^[a-z0-9.-]+$/.test(name)) {
    response.writeHead(404).end();
    return;
  }
  try {
    response.setHeader(
      "Content-Type",
      { ".html": "text/html", ".js": "text/javascript" }[extname(name)] ??
        "application/octet-stream",
    );
    response.end(await readFile(resolve("build/vorbis-prototype/web", name)));
  } catch {
    response.writeHead(404).end();
  }
}).listen(8094, "127.0.0.1", () => console.log("Vorbis prototype: http://127.0.0.1:8094/"));
