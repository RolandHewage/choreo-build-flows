ARG NODE_IMAGE=node:18-alpine
ARG NGINX_IMAGE=choreoanonymouspullable.azurecr.io/nginxinc/nginx-unprivileged:stable-alpine-slim

FROM $NODE_IMAGE AS builder
WORKDIR /app
COPY package.json ./
# npm install (no lockfile committed). Parallel tarball extraction is what
# exercises the overlay race the storage.conf fix targets.
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm install --no-audit --no-fund --prefer-offline
COPY . .
RUN npx tsc -b && npx vite build

FROM $NGINX_IMAGE
COPY --from=builder /app/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/build /usr/share/nginx/html/
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
