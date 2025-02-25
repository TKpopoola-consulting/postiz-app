# This Dockerfile is used for producing 3 container images.
#
# base         - A common base image with Node and basic infrastructure.
# devcontainer - Used for development; includes source code and node_modules.
# dist         - Used for production; contains the built source code and node_modules.

ARG NODE_VERSION="20.17"

# ------------------------------
# Base Stage
# ------------------------------
FROM docker.io/node:${NODE_VERSION}-alpine3.19 AS base

# Reduce unnecessary log noise and disable telemetry
ENV NPM_CONFIG_UPDATE_NOTIFIER=false
ENV NEXT_TELEMETRY_DISABLED=1
ENV npm_config_audit=false

WORKDIR /app

# Expose ports required by your application
EXPOSE 3000
EXPOSE 4200
EXPOSE 5000

# Copy static files and configuration
COPY var/docker/entrypoint.sh /app/entrypoint.sh
COPY var/docker/supervisord.conf /etc/supervisord.conf
COPY var/docker/supervisord /app/supervisord_available_configs/
COPY var/docker/Caddyfile /app/Caddyfile
COPY .env.example /config/postiz.env

# Set executable permissions for the entrypoint script
RUN chmod +x /app/entrypoint.sh

# Declare volumes for persistent data/configuration
VOLUME /config
VOLUME /uploads

LABEL org.opencontainers.image.source=https://github.com/gitroomhq/postiz-app

# Set the entrypoint script (common for all images)
ENTRYPOINT ["/app/entrypoint.sh"]

# ------------------------------
# DevContainer (Builder) Stage
# ------------------------------
FROM base AS devcontainer

# Install build dependencies required for native modules (e.g., canvas)
RUN apk add --no-cache \
    pkgconfig \
    gcc \
    pixman-dev \
    cairo-dev \
    pango-dev \
    make \
    build-base

# Copy essential configuration files and source code
COPY nx.json tsconfig.base.json package.json package-lock.json build.plugins.js /app/
COPY apps /app/apps/
COPY libraries /app/libraries/

# Install dependencies and build projects using Nx
RUN npm ci --no-fund --legacy-peer-deps && \
    npm run update-plugins && \
    npx nx run-many --target=build --projects=frontend,backend,workers,cron

# Preserve volumes for configuration and uploads
VOLUME /config
VOLUME /uploads

LABEL org.opencontainers.image.title="Postiz App (DevContainer)"

# ------------------------------
# Production (dist) Stage
# ------------------------------
FROM base AS dist

# Copy built node_modules and distribution artifacts from the builder stage
COPY --from=devcontainer /app/node_modules/ /app/node_modules/
COPY --from=devcontainer /app/dist/ /app/dist/

# Required for Prisma and other libraries
COPY --from=devcontainer /app/libraries/ /app/libraries/

# Also copy essential configuration files (including tsconfig.base.json)
COPY package.json nx.json tsconfig.base.json /app/

# Preserve volumes for configuration and uploads
VOLUME /config
VOLUME /uploads

# Label the production image
LABEL org.opencontainers.image.title="Postiz App (Production)"

# Use the production start script defined in package.json (e.g., "start:prod": "node dist/apps/backend/main.js")
CMD ["npm", "start:prod"]
