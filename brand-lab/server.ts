import { extname, join, normalize } from "node:path";

const root = import.meta.dir;
const port = Number(Bun.env.PORT ?? 4173);
const types: Record<string, string> = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
};

const server = Bun.serve({
  port,
  async fetch(request) {
    const url = new URL(request.url);
    const requested = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
    const safePath = normalize(requested).replace(/^(\.\.(\/|\\|$))+/, "");
    const file = Bun.file(join(root, safePath));

    if (!(await file.exists())) {
      return new Response("Not found", { status: 404 });
    }

    return new Response(file, {
      headers: {
        "Cache-Control": "no-store",
        "Content-Type": types[extname(safePath)] ?? "application/octet-stream",
      },
    });
  },
});

console.log(`Brand lab ready at ${server.url}`);
