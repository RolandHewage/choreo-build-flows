FROM alpine:3.19

RUN apk add --no-cache podman fuse-overlayfs jq

# Baseline podman config — leave /etc/containers/storage.conf alone. The
# entrypoint writes it at runtime based on STORAGE_CONF_VARIANT, exactly
# the way the production webapp build pod does (the script overwrites
# /etc/containers/storage.conf via a heredoc just before invoking podman build).
RUN mkdir -p /etc/containers /var/lib/containers/storage /run/containers/storage && \
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json && \
    printf '[registries.search]\nregistries = ["docker.io"]\n' > /etc/containers/registries.conf

COPY app/ /workspace/app/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
