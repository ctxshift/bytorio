import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { realpath, stat } from "node:fs/promises";
import { extname, resolve, sep } from "node:path";
import { pipeline } from "node:stream/promises";
import { spawn } from "node:child_process";
import { snapshotWeb, removeGenerated } from "./output.mjs";

const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".png": "image/png",
  ".json": "application/json",
  ".txt": "text/plain; charset=utf-8",
};

export async function openBrowser(url) {
  let executable;
  let args;
  if (process.platform === "darwin") {
    executable = "/usr/bin/open";
    args = [url];
  } else if (process.platform === "win32") {
    const system = process.env.SystemRoot ?? process.env.WINDIR;
    if (!system) {
      throw new Error(
        "Windows system directory is unavailable; open the printed player URL manually",
      );
    }
    executable = resolve(system, "System32/rundll32.exe");
    args = ["url.dll,FileProtocolHandler", url];
  } else {
    throw new Error("Open the printed player URL in your browser");
  }
  await new Promise((done, reject) => {
    const child = spawn(executable, args, { windowsHide: true, stdio: "ignore" });
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error("Browser launch timed out"));
    }, 10000);
    child.once("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.once("exit", (code) => {
      clearTimeout(timer);
      if (code === 0) {
        done();
      } else {
        reject(new Error("Browser launch failed"));
      }
    });
  });
}

export async function startPreview(project, { port = 0, open = true } = {}) {
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error("Port must be an integer from 0 to 65535");
  }
  const root = await snapshotWeb(project.directory, resolve(project.buildRoot, "web"));
  const entry = project.release.manifest.web.page.path;
  const server = createServer(async (request, response) => {
    try {
      if (!["GET", "HEAD"].includes(request.method)) {
        response.writeHead(405).end();
        return;
      }
      const url = new URL(request.url, "http://localhost");
      if (url.pathname === "/") {
        response.writeHead(302, { Location: `/${entry}${url.search}` }).end();
        return;
      }
      const path = resolve(root, `.${decodeURIComponent(url.pathname)}`);
      if (!path.startsWith(root + sep) || !(await realpath(path)).startsWith(root + sep)) {
        response.writeHead(403).end();
        return;
      }
      const info = await stat(path);
      if (!info.isFile()) {
        response.writeHead(404).end();
        return;
      }
      response.writeHead(200, {
        "Content-Type": types[extname(path)] ?? "application/octet-stream",
        "Content-Length": info.size,
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
      });
      if (request.method === "HEAD") {
        response.end();
      } else {
        await pipeline(createReadStream(path), response);
      }
    } catch {
      if (response.headersSent) {
        response.destroy();
      } else {
        response.writeHead(404).end("Not found");
      }
    }
  });
  try {
    await new Promise((done, reject) => {
      server.once("error", reject);
      server.listen(port, "127.0.0.1", done);
    });
  } catch (error) {
    await removeGenerated(root);
    throw error;
  }
  const url = `http://127.0.0.1:${server.address().port}/`;
  console.log(`Player: ${url}`);
  if (open) {
    try {
      await openBrowser(url);
    } catch (error) {
      console.error(`${error.message}. The player is available at ${url}`);
    }
  }
  return {
    url,
    async close() {
      server.closeAllConnections();
      await new Promise((done) => server.close(done));
      await removeGenerated(root);
    },
  };
}
