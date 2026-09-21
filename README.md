# depleazy-images

Runtime images for Depleazy functions, and examples that run on them.

## The idea

A function is **not** an image built per deploy. It's one shared runtime image,
told where to find the user's code:

```
docker run  ghcr.io/justartiom/depleazy-runtime-node:24
  -e DEPLEAZY_CODE_URL=https://.../abc.zip
  -e DEPLEAZY_CODE_SHA256=9f86d0...
  -e PORT=8080
```

The image's entrypoint downloads the zip, checks it, unpacks it and runs it.

Two things follow from that. A deploy is an **upload**, not a build — seconds
instead of minutes, with no registry, no builder and no image per version. And
there's one image on disk however many people are running something, which
matters a great deal when the whole platform is one box.

It also means the platform doesn't know it's running "a function". It runs a
container with environment variables, which it already knew how to do — all the
cleverness lives in here.

## The contract

Everything the entrypoint needs arrives as environment variables. Core sets the
first three; the rest are for tuning and rarely touched.

| Variable | |
|---|---|
| `DEPLEAZY_CODE_URL` | where to fetch the zip. Required. |
| `DEPLEAZY_CODE_SHA256` | what it must hash to. Required. |
| `PORT` | what the app should listen on. Always 8080. |
| `DEPLEAZY_SERVICE`, `DEPLEAZY_PROJECT` | who this is, for logs |
| `DEPLEAZY_MAX_UNPACKED_BYTES` | refuse archives that expand past this (512 MiB) |
| `DEPLEAZY_FETCH_TIMEOUT` | seconds to spend downloading (120) |

### What gets run

In order: `main` from `package.json`, then `index.js`, then `server.js`, then
`npm start`. The first three run the file with `node` directly so the app is
PID 1 and a stop actually reaches it — going through npm puts a process in
between that forwards signals unreliably, which turns every stop into a wait
for the kill.

A zip made by right-clicking a folder has everything one level down. That's
handled rather than rejected.

### What it refuses

- A zip whose checksum doesn't match, **before** unpacking it
- Paths that escape the directory (`../…`, `/…`)
- Archives that expand past the size limit

## Dependencies

There is no `npm install` step. **Zip your `node_modules` along with your
code.** Starts are instant and nothing needs the network, at the cost of a
larger upload. Caching by lockfile is a later problem.

## Building

```sh
docker build -t ghcr.io/justartiom/depleazy-runtime-node:24 \
  -f runtimes/node/Dockerfile runtimes/node
docker push ghcr.io/justartiom/depleazy-runtime-node:24
```

Then add it in the console under **Admin → Runtimes**: a name and that image
reference. Adding Node 25 is building this image with a different base and
adding a row — never a code change to the platform.

Note that a runtime has to be built **from here**. Pointing a runtime at plain
`node:25` won't work: the entrypoint that fetches and runs the code is what
makes it a runtime, and it lives in these images.

## Trying one by hand

```sh
cd examples/node-hello && zip -r /tmp/hello.zip . && cd -
shasum -a 256 /tmp/hello.zip           # note the hash

(cd /tmp && python3 -m http.server 49213 --bind 127.0.0.1) &

docker run --rm -p 127.0.0.1:49217:8080 \
  -e DEPLEAZY_CODE_URL=http://host.docker.internal:49213/hello.zip \
  -e DEPLEAZY_CODE_SHA256=<the hash> \
  ghcr.io/justartiom/depleazy-runtime-node:24

curl http://127.0.0.1:49217/
```
