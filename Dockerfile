# ========================
# Base image: Common settings
# ========================
FROM docker.io/node:20.17-alpine3.19 AS base

# Reduce log noise and disable telemetry
ENV NPM_CONFIG_UPDATE_NOTIFIER=false
ENV NEXT_TELEMETRY_DISABLED=1
ENV npm_config_audit=false

WORKDIR /app

# Expose ports as needed (adjust if necessary)
EXPOSE 3000
EXPOSE 4200
EXPOSE 5000

# Copy environment examples or other static configuration files
COPY .env.example /config/postiz.env

# ========================
# Build Stage: Install and Build
# ========================
FROM base AS build

# Install build tools (needed for packages like canvas)
RUN apk add --no-cache pkgconfig gcc pixman-dev cairo-dev pango-dev make build-base

# Copy project files needed for installing dependencies and building
COPY package.json package-lock.json nx.json build.plugins.js /app/
COPY apps /app/apps/
COPY libraries /app/libraries/

# Install dependencies (using legacy-peer-deps to bypass peer conflicts)
RUN npm ci --legacy-peer-deps

# Run build plugins script and then build the apps
RUN npm run update-plugins
RUN npx nx run-many --target=build --projects=frontend,backend,workers,cron

# ========================
# Production Stage: Final Runtime Image
# ========================
FROM docker.io/node:20.17-alpine3.19 AS production

WORKDIR /app

# Copy only the production-ready assets from the build stage:
# - node_modules (dependencies)
# - built output (dist)
# - libraries (required for Prisma and others)
COPY --from=build /app/node_modules/ /app/node_modules/
COPY --from=build /app/dist/ /app/dist/
COPY --from=build /app/libraries/ /app/libraries/
COPY package.json nx.json /app/

# Optionally, copy additional files if required (e.g., build.plugins.js) if your runtime expects them:
# COPY --from=build /app/build.plugins.js /app/

# Define volumes if your application uses external configuration or storage
VOLUME /config
VOLUME /uploads

# Use the production start script (adjust to the proper entry point for your app)
CMD ["npm", "start:prod"]
