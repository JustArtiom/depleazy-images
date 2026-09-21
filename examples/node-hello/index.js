// The smallest thing that proves a function is really running.
//
// Listens on PORT, which Depleazy sets for you, and says which service it
// belongs to — so if you deploy it twice you can tell the two apart.
import { createServer } from "node:http";

const port = Number(process.env.PORT ?? 8080);
const service = process.env.DEPLEAZY_SERVICE ?? "a function";
const project = process.env.DEPLEAZY_PROJECT ?? "somewhere";

createServer((request, response) => {
  response.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
  response.end(
    `Hello from ${service} in ${project}.\n` +
      `Node ${process.version}, listening on ${port}.\n` +
      `You asked for ${request.url}\n`,
  );
}).listen(port, () => {
  console.log(`listening on ${port}`);
});
