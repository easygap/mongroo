# Flutter 앱

몽그루의 Android/Web 클라이언트다. 프로젝트 설명과 서버 실행 방법은
[루트 README](../README.md)에 있다.

## 실행

```powershell
flutter pub get

# Android 에뮬레이터
flutter run

# Chrome
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

Android 에뮬레이터에서는 API 주소를 지정하지 않으면
`http://10.0.2.2:8000/api/v1`을 사용한다. 다른 기기나 서버에 연결할 때는 빌드
명령에 `--dart-define=API_BASE_URL=...`을 붙인다. Web은 주소를 생략하면 현재
origin의 `/api/v1`을 사용하므로 공식 컨테이너처럼 API를 같은 origin으로 프록시하는
배포에서는 별도 주소가 필요 없다.

```powershell
dart analyze
flutter test
flutter build web --wasm --no-web-resources-cdn --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

한글 본문과 Flutter Web 기본 대체 서체는 앱에 포함된 Gothic A1으로
해결한다. 공개 빌드에서는 `--no-web-resources-cdn`을 유지해 운영 CSP와
오프라인 환경에서도 외부 폰트·엔진 요청이 생기지 않게 한다.

공개 Web은 HTTPS가 필요하다. API 주소, CORS, Android 서명 설정은
[배포 문서](../docs/deployment.md)에 적어 두었다.
공개 Web/AAB에는 운영자명·주소·개인정보 문의 이메일·데이터 호스팅 고지도
`--dart-define`으로 넣어야 한다. 약관·개인정보·민감정보 동의 버전도 서버 설정과
같게 넣어야 하며, 공식 Docker/릴리스 workflow는 누락 시 실패한다.

로그인 화면의 `회원가입 없이 3분 체험`은 `/trial` 공개 경로를 사용한다. 체험
진행은 서버 API나 임시 계정을 만들지 않고 `flutter_secure_storage`에만 저장하며,
가입 사용자는 계정 화면에서 같은 가이드를 다시 실행할 수 있다.

## 코드 위치

```text
lib/core/       API, 라우팅, 세션, 테마
lib/features/   화면별 data/domain/presentation 코드
assets/         캐릭터, 방, 식물 이미지
test/           단위·위젯 테스트
```

화면 캡처는 앱 안에 넣지 않고 [docs/screenshots](../docs/screenshots/README.md)에
Android와 Web을 나눠 보관한다.
