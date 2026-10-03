# --- Сборка Crystal-приложения (статический бинарник на Alpine) ---
FROM crystallang/crystal:latest-alpine AS build
WORKDIR /app

COPY shard.yml ./
RUN shards install --production || shards install

COPY src ./src
RUN shards build app --release --static --no-debug

# --- Минимальный рантайм-образ ---
FROM alpine:3.20
WORKDIR /app

COPY --from=build /app/bin/app /app/app
COPY public ./public

EXPOSE 3000
CMD ["/app/app"]
