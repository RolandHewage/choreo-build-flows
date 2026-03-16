FROM alpine:3.19

RUN apk add --no-cache docker-cli podman fuse-overlayfs

RUN mkdir -p /etc/containers && \
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json && \
    printf '[registries.search]\nregistries = ["docker.io"]\n' > /etc/containers/registries.conf && \
    printf '[storage]\ndriver = "overlay"\ngraphroot = "/var/lib/containers/storage"\nrunroot = "/run/containers/storage"\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' > /etc/containers/storage.conf && \
    mkdir -p /var/lib/containers/storage /run/containers/storage

COPY app/ /workspace/app/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
