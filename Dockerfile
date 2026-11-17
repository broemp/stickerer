# syntax=docker/dockerfile:1
FROM node:24-slim AS build
ENV PNPM_HOME=/pnpm PATH=/pnpm:$PATH
RUN corepack enable
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

FROM node:24-slim
# ffmpeg decodes the video, webp provides img2webp for animated WebP encoding
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg webp \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production PORT=3000 HOST=0.0.0.0
COPY --from=build /app/build ./build
COPY package.json ./
USER node
EXPOSE 3000
CMD ["node", "build"]
