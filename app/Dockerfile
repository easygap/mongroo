FROM ghcr.io/cirruslabs/flutter:3.44.6 AS build

WORKDIR /workspace
ARG API_BASE_URL=
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY . .
RUN if [ -n "$API_BASE_URL" ]; then \
      flutter build web --wasm --release --no-pub \
        --dart-define="API_BASE_URL=$API_BASE_URL"; \
    else \
      flutter build web --wasm --release --no-pub; \
    fi

FROM nginx:1.28.0-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY deploy/security-headers.conf /etc/nginx/snippets/mongroo-security.conf
COPY --from=build /workspace/build/web /usr/share/nginx/html
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/nginx-health || exit 1
