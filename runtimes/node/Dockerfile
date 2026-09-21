# The Node.js runtime for Depleazy functions.
#
# One image serves every Node function on the platform. The user's code isn't
# baked in — it's fetched at start from a URL the platform passes in. That's
# what makes a deploy an upload instead of a build, and what keeps one image on
# disk however many people are running something.
#
#   docker build -t ghcr.io/justartiom/depleazy-runtime-node:24 \
#     -f runtimes/node/Dockerfile runtimes/node
ARG NODE_VERSION=24
FROM node:${NODE_VERSION}-alpine

# curl for the fetch, unzip to unpack, ca-certificates so https actually
# verifies rather than quietly failing.
RUN apk add --no-cache curl unzip ca-certificates

# Never root. Someone else's code runs in here, and a container escape that
# starts as root is a much shorter path to the host than one that doesn't.
RUN addgroup -S app && adduser -S -G app -h /home/app app && \
    mkdir -p /app && chown app:app /app

COPY entrypoint.sh /usr/local/bin/depleazy-entrypoint
RUN chmod 555 /usr/local/bin/depleazy-entrypoint

USER app
WORKDIR /app

# The whole platform listens here, and core injects the same value as PORT.
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/depleazy-entrypoint"]
