ARG BASE_IMAGE=node:18-alpine
FROM $BASE_IMAGE
ARG NPM_REGISTRY

RUN if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi

WORKDIR /app

COPY package.json ./
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm install

COPY server.js ./

RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid 10014 \
    "choreo"
USER 10014

EXPOSE 8080
CMD ["node", "server.js"]
