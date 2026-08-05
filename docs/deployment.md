# 몽그루 실행·배포 전제

이 문서는 로컬 데모와 실제 사용자 데이터를 받는 공개 배포를 구분한다. 운영은
`APP_ENV=production`, `DATA_PROFILE=real-data` 조합만 허용하며, API 시작 전에
AES-256-GCM 필드 암호화 backfill과 전수 검증을 통과해야 한다. 개인정보·제품 안전
정책은 [design.md §9](design.md#9-보안개인정보제품-안전)를 함께 따른다.

## 0. 운영 스택 즉시 기동

루트의 `docker-compose.prod.yml`은 MySQL → Alembic 마이그레이션 → 민감 컬럼
암호화·검증 → API/worker → Flutter Web 순서를 health gate로 올린다. Web 컨테이너는 `/api/`를 내부
API로 프록시하므로 클라이언트와 API를 하나의 HTTPS origin으로 배포할 수
있다. 8080 포트 앞에는 반드시 TLS를 종료하는 load balancer나 reverse proxy를
둔다.

```powershell
Copy-Item .env.production.example .env.production
# .env.production의 replace-with-* 값과 도메인을 실제 secret/domain으로 교체
docker compose --env-file .env.production -f docker-compose.prod.yml config --quiet
docker compose --env-file .env.production -f docker-compose.prod.yml build --pull
docker compose --env-file .env.production -f docker-compose.prod.yml up -d
docker compose --env-file .env.production -f docker-compose.prod.yml ps
```

`APP_ENV=production`은 약한 JWT, SQLite, demo 데이터 프로파일, 유효하지 않은
암호화 키, fake AI, HTTP/wildcard CORS, 로컬/wildcard Host를 발견하면 API를 즉시
종료한다. 예시 파일의 `replace-with-*`를 실제 값으로 바꾸지 않으면 빌드 또는
기동이 실패하는 것이 정상이다. `/api/v1/health/live`은 프로세스,
`/ready`는 DB revision·암호화 검증 마커·동의 계약을 확인하며 위반 시 HTTP 503이다.

기본 운영값 `AI_MODE=rules`는 GPU와 외부 전송 없이 검수된 결정적 분류·대화·요약을
worker에서 처리한다. 모델 품질 검증과 전용 `local-ai` 이미지가 준비된 환경만
`AI_MODE=local`을 사용한다. 장애 격리 중 `AI_MODE=disabled`로 내릴 수 있지만 이때
일기 저장·성장·탐험 외의 분석·대화·요약은 명시적으로 비활성화된다.

## 1. 클라이언트 API 주소

Flutter의 API 주소는 `API_BASE_URL`을 지정하면 컴파일 시 고정된다. 생략하면 Web은
현재 origin의 `/api/v1`을 사용하고 Android는 에뮬레이터용
`http://10.0.2.2:8000/api/v1`을 사용한다. 공식 Web 컨테이너는 `/api/`를 내부 API로
프록시하므로 동일 출처 배포에서는 주소를 생략한다. Web과 API를 서로 다른 origin으로
배포하거나 Android를 빌드할 때는 HTTPS 운영 주소를 명시한다.

```powershell
# 로컬 Web
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1

# 공개 Web 예시: 법적 고지값도 빌드에 고정한다.
flutter build web --wasm --no-web-resources-cdn `
  --dart-define=API_BASE_URL=https://api.example.com/api/v1 `
  --dart-define=SERVICE_OPERATOR_NAME="실제 운영자명" `
  --dart-define=SERVICE_OPERATOR_ADDRESS="실제 운영자 주소" `
  --dart-define=PRIVACY_CONTACT_EMAIL=privacy@example.com `
  --dart-define=DATA_HOSTING_DISCLOSURE="사업자·리전·국가" `
  --dart-define=TERMS_VERSION=2026-08-05 `
  --dart-define=PRIVACY_VERSION=2026-08-05 `
  --dart-define=SENSITIVE_CONSENT_VERSION=2026-08-05

# USB Android 실기기 로컬 데모
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

`--no-web-resources-cdn`은 제거하지 않는다. 운영 CSP는 외부 폰트를 허용하지
않으며, Gothic A1과 Flutter Web 엔진 자원을 동일 출처에서 제공해 초기
렌더링이 Google Fonts 가용성에 의존하지 않게 한다.

환경별 주소를 바꾼 뒤에는 앱을 다시 빌드해야 한다. 토큰이나 비밀값은
`--dart-define`에 넣지 않는다.

## 2. Web HTTPS와 CORS

- 공개 Web과 API는 모두 HTTPS로 제공한다. Web refresh token 저장소가 안전한
  브라우저 컨텍스트를 요구하며, HTTP는 `localhost` 개발에만 사용한다.
- 서버 `CORS_ORIGINS`에는 프런트엔드의 **정확한 origin**(scheme, host, port)을
  JSON 배열로 넣는다. API URL이나 `/path`를 넣지 않는다.
- 프로덕션에서는 로컬 개발용 `CORS_ORIGIN_REGEX`를 제거하거나 프로덕션 도메인만
  허용하도록 좁힌다. credentials를 사용하므로 wildcard `*`는 허용하지 않는다.
- CDN/프록시에서 SSE 경로 `/api/v1/chat/runs/*/events`의 응답 버퍼링을 끄고
  장기 연결 timeout을 서버의 90초보다 길게 둔다.

```dotenv
CORS_ORIGINS=["https://app.example.com"]
CORS_ORIGIN_REGEX=
```

## 3. Web 정적 호스팅과 원자적 배포

`app/build/web` 전체를 하나의 배포 단위로 올린다. Flutter 3.44는 서비스
워커를 기본 생성·관리하지 않으므로, 현재 산출물도 오프라인 캐시가 아니라 HTTP/CDN
캐시 정책에 의존한다.

- `.wasm`, `.js`, `.mjs`, `.json`, `.html`, `.css`, `.svg`는 Brotli를 우선 제공하고
  지원하지 않는 클라이언트에는 gzip을 보낸다. `Vary: Accept-Encoding`을 함께 보내며, `.wasm`의
  `Content-Type`은 `application/wasm`이어야 한다. 이미 압축된 WebP/PNG/JPEG는 다시
  압축하지 않는다.
- Wasm 렌더러의 멀티스레드를 사용하려면 정적 문서와 자산 응답에
  `Cross-Origin-Opener-Policy: same-origin`과
  `Cross-Origin-Embedder-Policy: credentialless`(또는 모든 외부 자산을 검증한 뒤
  `require-corp`)를 설정한다. 헤더가 없어도 앱은 실행되지만 렌더링은 단일 스레드로
  제한된다.
- `index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`, `version.json`,
  `main.dart.*`, manifest/JSON/bin은 `Cache-Control: max-age=0, must-revalidate`로
  재검증한다. 이미지·폰트는 browser 1시간/shared cache 1주 정도로 시작하고 배포 후
  CDN을 무효화한다. URL에 release ID 또는 content hash가 있는 자산에만
  `max-age=31536000, immutable`을 사용한다.
- 새 빌드를 릴리스 ID 디렉터리에 먼저 업로드하고 시작 파일, Wasm, API의 기본 동작을
  확인한 뒤 현재 배포 경로를 한 번에 전환한다. 활성 디렉터리에 파일을 덮어쓰지 않으며,
  이전 릴리스는 즉시 되돌릴 수 있게 보관한다. API는 최소 직전 Web 릴리스와
  계약 호환성을 유지한다.

```powershell
curl.exe -I -H "Accept-Encoding: br" https://app.example.com/main.dart.wasm
curl.exe -I https://app.example.com/index.html
```

두 응답에서 `Content-Type`, `Content-Encoding`, `Cache-Control`, COOP/COEP를 확인한다.
오프라인 지원이 제품 요구사항이 되면 Workbox 등의 표준 도구로 별도 서비스 워커를
추가하고, 캐시 업데이트와 되돌리기 E2E를 배포 검사에 포함한다. 근거는 Flutter 공식
[Wasm 배포 지침](https://docs.flutter.dev/platform-integration/web/wasm#serve-the-built-output-with-an-http-server)과
[Web 캐시 FAQ](https://docs.flutter.dev/platform-integration/web/faq#how-do-i-configure-my-cache-headers)를
참조한다.

## 4. Android 빌드와 서명

- Flutter가 인식하는 Android SDK, `adb`, Java 17이 필요하다. `flutter doctor -v`에서
  Android toolchain 오류가 없어야 APK/AAB 검증이 가능하다.
- 로컬 HTTP 허용은 `debug`/`profile` manifest에만 있다. 공개 빌드는 HTTPS API를
  사용한다.
- `release` build는 `app/android/key.properties`와 운영 upload key가 없으면
  실패한다. `app/android/key.properties.example`을 복사해 네 값을 입력하고,
  keystore·`key.properties`·비밀번호는 커밋하지 않는다. release에 debug
  keystore로 대체하는 경로는 없다.
- application ID는 `com.easygap.mongroo`이다. 스토어 등록 뒤에는 호환성에 영향을
  주므로 임의로 변경하지 않는다.

최소 릴리스 검증은 다음과 같다.

```powershell
flutter doctor -v
dart analyze
flutter test
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

## 5. 서버 공개 전 설정

- `JWT_SECRET`을 32바이트 이상의 무작위 값으로 교체하고 secret store에서 주입한다.
- `FIELD_ENCRYPTION_KEYS`에는 base64 32바이트 키 ring을 JSON으로 넣고
  `ACTIVE_FIELD_ENCRYPTION_KEY_ID`로 쓰기 키를 선택한다. 키는 DB·백업·저장소와
  분리하며 예시 키를 운영에 사용하지 않는다.
- `DATABASE_URL`, CORS, Ollama 주소를 환경별로 분리하고 MySQL/Ollama를 공용망에
  직접 노출하지 않는다.
- `alembic upgrade head` 다음 `python -m app.protect_sensitive_data`를 실행한다.
  평문이 하나라도 남거나 현재 active key 검증 마커가 없으면 API readiness가 닫힌다.
- 기존 사용자가 있는 demo DB를 real-data로 승격할 때는 유효한 연령 확인·약관·민감정보
  동의를 별도 수집해야 한다. 동의 버전을 임의 backfill하지 않는다.
- `/api/v1/health/ready`가 의도한 상태인지 확인한다. AI 기능을 쓸 배포에서 worker가
  없으면 기록은 남아도 분석·대화·요약 job이 처리되지 않는다.
- `server/openapi.json`은 `cd server; python -m app.export_openapi`로 재생성하고
  클라이언트 계약 변경과 같은 커밋에서 검토한다.

## 6. 마이그레이션·백업·롤백

1. 배포 전 현재 이미지 tag, Git SHA, DB 마이그레이션 revision을 기록한다.
2. MySQL volume snapshot 또는 암호화된 `mysqldump --single-transaction` 백업을 생성하고
   복구 테스트가 있는 백업만 사용한다.
3. 마이그레이션 job이 0으로 종료된 뒤 API를 교체한다. API와 Web은 최소
   직전 클라이언트 계약을 유지한다.
4. 배포 후 가입·로그인, 일기 저장, 탐험 시작→이동→사건→귀환,
   `/ready`, 보안 헤더, worker heartbeat(AI 활성 시)를 smoke test한다.
5. 실패하면 Web·API를 직전 immutable image tag로 되돌린다. 이미 적용된
   추가형 마이그레이션은 즉시 downgrade하지 않고 전방 호환 API를 유지한다.
   정말 DB 복구가 필요하면 쓰기를 중단하고 검증된 snapshot을 별도 인스턴스에
   복구한 뒤 전환한다.

### 암호화 키 회전

1. 기존 키와 새 32바이트 키를 key ring에 함께 넣고 새 ID를 active로 지정한다.
2. 쓰기 트래픽을 중단하거나 maintenance로 전환한 뒤
   `python -m app.protect_sensitive_data --rotate`를 한 번만 실행한다.
3. `remaining_plaintext=0`, `/ready`의 `sensitive_storage=ok`, 계정 export 복호화를
   확인하고 백업 복구 리허설을 한다.
4. 이전 백업의 보존기간이 끝나기 전에는 구 키를 폐기하지 않는다. 회전 도중 실패하면
   구·신 키를 모두 유지한 채 같은 명령을 재실행한다.

## 7. GitHub 릴리스 입력과 산출물

`.github/workflows/release.yml`은 `vX.Y.Z` tag 또는 수동 version으로 실행한다. 서버·앱
전체 테스트와 MySQL production smoke를 통과한 뒤 서명 AAB, GHCR API/Web 이미지,
SBOM·provenance attestations, GitHub Release를 만든다. 컨테이너는 비root 사용자로
실행하고, HIGH/CRITICAL 취약점 검사를 통과한 digest만 `vX.Y.Z` tag로 승격한다.
이미 존재하는 tag가 다른 digest를 가리키면 덮어쓰지 않고 릴리스를 실패시킨다.

Repository secrets:

- `PRODUCTION_API_BASE_URL`(HTTPS)
- `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`,
  `ANDROID_KEY_ALIAS`

Repository variables:

- `SERVICE_OPERATOR_NAME`, `SERVICE_OPERATOR_ADDRESS`
- `PRIVACY_CONTACT_EMAIL`
- `DATA_HOSTING_DISCLOSURE`(호스팅 사업자·리전·국가)
- `TERMS_VERSION`, `PRIVACY_VERSION`, `SENSITIVE_CONSENT_VERSION`

일곱 법적 고지·동의 버전 변수 중 하나라도 비었거나 이메일 형식이 아니면 Web 이미지와
Android AAB 생성을 중단한다. 앱이 가입 때 보낸 세 문서 버전과 서버의 현재 버전이
다르면 동의를 저장하지 않고 409로 새로고침을 요구한다. 실제 배포 환경의 DB/JWT/암호화 키는 GitHub 이미지 빌드에 넣지
않고 런타임 secret store에서 주입한다.
