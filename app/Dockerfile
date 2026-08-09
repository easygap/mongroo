FROM ghcr.io/cirruslabs/flutter:3.44.6 AS build

WORKDIR /workspace
ARG API_BASE_URL=
ARG SERVICE_OPERATOR_NAME
ARG SERVICE_OPERATOR_ADDRESS
ARG PRIVACY_CONTACT_EMAIL
ARG DATA_HOSTING_DISCLOSURE
ARG TERMS_VERSION
ARG PRIVACY_VERSION
ARG SENSITIVE_CONSENT_VERSION
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY . .
RUN test -n "$SERVICE_OPERATOR_NAME" \
    && test -n "$SERVICE_OPERATOR_ADDRESS" \
    && test -n "$PRIVACY_CONTACT_EMAIL" \
    && test -n "$DATA_HOSTING_DISCLOSURE" \
    && test -n "$TERMS_VERSION" \
    && test -n "$PRIVACY_VERSION" \
    && test -n "$SENSITIVE_CONSENT_VERSION" \
    && case "$PRIVACY_CONTACT_EMAIL" in *@*.*) ;; *) exit 1 ;; esac \
    && if [ -n "$API_BASE_URL" ]; then \
      flutter build web --wasm --release --no-pub --no-web-resources-cdn \
        --dart-define="API_BASE_URL=$API_BASE_URL" \
        --dart-define="SERVICE_OPERATOR_NAME=$SERVICE_OPERATOR_NAME" \
        --dart-define="SERVICE_OPERATOR_ADDRESS=$SERVICE_OPERATOR_ADDRESS" \
        --dart-define="PRIVACY_CONTACT_EMAIL=$PRIVACY_CONTACT_EMAIL" \
        --dart-define="DATA_HOSTING_DISCLOSURE=$DATA_HOSTING_DISCLOSURE" \
        --dart-define="TERMS_VERSION=$TERMS_VERSION" \
        --dart-define="PRIVACY_VERSION=$PRIVACY_VERSION" \
        --dart-define="SENSITIVE_CONSENT_VERSION=$SENSITIVE_CONSENT_VERSION"; \
    else \
      flutter build web --wasm --release --no-pub --no-web-resources-cdn \
        --dart-define="SERVICE_OPERATOR_NAME=$SERVICE_OPERATOR_NAME" \
        --dart-define="SERVICE_OPERATOR_ADDRESS=$SERVICE_OPERATOR_ADDRESS" \
        --dart-define="PRIVACY_CONTACT_EMAIL=$PRIVACY_CONTACT_EMAIL" \
        --dart-define="DATA_HOSTING_DISCLOSURE=$DATA_HOSTING_DISCLOSURE" \
        --dart-define="TERMS_VERSION=$TERMS_VERSION" \
        --dart-define="PRIVACY_VERSION=$PRIVACY_VERSION" \
        --dart-define="SENSITIVE_CONSENT_VERSION=$SENSITIVE_CONSENT_VERSION"; \
    fi

FROM nginxinc/nginx-unprivileged:1.31.3-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY deploy/security-headers.conf /etc/nginx/snippets/mongroo-security.conf
COPY --from=build /workspace/build/web /usr/share/nginx/html
USER 101
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/nginx-health || exit 1
