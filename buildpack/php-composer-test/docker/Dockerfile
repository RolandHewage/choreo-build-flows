FROM alpine:3.21

ARG PACK_VERSION=0.40.0

RUN apk add --no-cache docker-cli podman fuse-overlayfs jq curl && \
    curl -sSL "https://github.com/buildpacks/pack/releases/download/v${PACK_VERSION}/pack-v${PACK_VERSION}-linux.tgz" \
    | tar xz -C /usr/local/bin && \
    apk del curl

# Podman config for rootless/privileged pod
RUN mkdir -p /etc/containers && \
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json && \
    printf '[registries.search]\nregistries = ["docker.io"]\n' > /etc/containers/registries.conf && \
    printf '[storage]\ndriver = "overlay"\ngraphroot = "/var/lib/containers/storage"\nrunroot = "/run/containers/storage"\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' > /etc/containers/storage.conf && \
    printf '[containers]\nenv = ["DOCKER_API_VERSION=1.44"]\n' > /etc/containers/containers.conf && \
    mkdir -p /var/lib/containers/storage /run/containers/storage

COPY app/ /workspace/app/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
