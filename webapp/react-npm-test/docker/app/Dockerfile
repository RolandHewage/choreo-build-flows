ARG NODE_IMAGE=node:18-alpine
ARG NGINX_IMAGE=choreoanonymouspullable.azurecr.io/nginxinc/nginx-unprivileged:stable-alpine-slim
FROM $NODE_IMAGE as builder
# Mount .npmrc secret so pnpm install works against auth-required proxy registries
# in restricted clusters (where the default registry.npmjs.org is blocked).
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm install -g pnpm
ARG NPM_REGISTRY
RUN if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi
WORKDIR /app
COPY . .
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    if [ -f "./package-lock.json" ]; then npm install; \
    elif [ -f "./yarn.lock" ]; then yarn; \
    elif [ -f "./pnpm-lock.yaml" ]; then pnpm install; fi
COPY . .
RUN npm run build

FROM $NGINX_IMAGE

# Update nginx user/group in alpine
ENV ENABLE_PERMISSIONS=TRUE
ENV DEBUG_PERMISSIONS=TRUE
ENV USER_NGINX=10015
ENV GROUP_NGINX=10015

COPY --from=builder /app/default.conf /etc/nginx/conf.d/default.conf

USER root
RUN ln -sf /app/public/ /usr/share/nginx/html/
USER nginx
COPY --from=builder /app/build /usr/share/nginx/html/
USER 10015
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
