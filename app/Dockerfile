FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS build

# 배포 이미지는 공개 시점이 늦는 서드파티 태그 대신 공식 아카이브를 검증해 사용한다.
ARG FLUTTER_VERSION=3.44.6
ARG FLUTTER_ARCHIVE_SHA256=a6320fd72e9a2690c08e2a6a70874a30cb120dee7c78f49d2c628bd7c9e20525
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/* \
    && curl --fail --location --silent --show-error \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      --output /tmp/flutter.tar.xz \
    && echo "${FLUTTER_ARCHIVE_SHA256}  /tmp/flutter.tar.xz" \
      | sha256sum --check --strict \
    && tar --extract --xz --file /tmp/flutter.tar.xz --directory /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory "${FLUTTER_HOME}" \
    && flutter config --no-analytics --enable-web \
    && flutter precache --web

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

FROM nginxinc/nginx-unprivileged:1.28.0-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY deploy/security-headers.conf /etc/nginx/snippets/mongroo-security.conf
COPY --from=build /workspace/build/web /usr/share/nginx/html
USER 101
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/nginx-health || exit 1
