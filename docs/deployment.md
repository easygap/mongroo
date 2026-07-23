# 몽그루 실행·배포 전제

이 문서는 로컬 데모 실행과 공개 배포 준비를 구분한다. 현재 서버의
`DATA_PROFILE`은 `demo`만 허용하므로, 아래 설정을 마쳐도 실제 민감정보를 받는
운영 서비스가 되는 것은 아니다. 개인정보·암호화 검토 항목은
[design.md §9](design.md#9-보안개인정보제품-안전)를 별도로 충족해야 한다.

## 1. 클라이언트 API 주소

Flutter의 API 주소는 컴파일 시 `API_BASE_URL`로 고정된다. 생략 시 Android
에뮬레이터용 `http://10.0.2.2:8000/api/v1`가 들어가므로 Web 또는 배포 빌드에서는
반드시 명시한다.

```powershell
# 로컬 Web
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1

# 공개 Web 예시: HTTPS API만 사용
flutter build web --wasm --dart-define=API_BASE_URL=https://api.example.com/api/v1

# USB Android 실기기 로컬 데모
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

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
- 현재 `release` build type은 로컬 기본 동작 확인을 위해 debug keystore로
  서명한다. 스토어 제출 전 자체 upload key/keystore와 CI secret을 연결하고
  debug 서명 대체 설정을 제거해야 한다. keystore와 비밀번호는 커밋하지 않는다.
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
- `DATABASE_URL`, CORS, Ollama 주소를 환경별로 분리하고 MySQL/Ollama를 공용망에
  직접 노출하지 않는다.
- `alembic upgrade head`를 먼저 적용하고 API와 AI worker를 함께 실행한다.
- `/api/v1/health/ready`가 의도한 상태인지 확인한다. AI 기능을 쓸 배포에서 worker가
  없으면 기록은 남아도 분석·대화·요약 job이 처리되지 않는다.
- `server/openapi.json`은 `cd server; python -m app.export_openapi`로 재생성하고
  클라이언트 계약 변경과 같은 커밋에서 검토한다.
