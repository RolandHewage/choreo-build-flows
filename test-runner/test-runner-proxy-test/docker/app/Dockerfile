ARG NODE_IMAGE=node:18-alpine
FROM $NODE_IMAGE
ARG NPM_REGISTRY

RUN if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi

# Create a directory for postman collections
RUN mkdir /etc/postman

# Copy all Postman collection files to the container
COPY postman-collection/*.json /etc/postman/

# Install newman cli
RUN npm i -g newman -y

# Copy script to run collections
COPY run-collections.sh /etc/run-collections.sh

RUN chmod +x /etc/run-collections.sh

RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid 10014 \
    "choreo"
# Use the above created unprivileged user
USER 10014

# Run the script when the container starts
ENTRYPOINT ["sh", "-c", "/etc/run-collections.sh $@", "--"]
