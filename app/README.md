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
명령에 `--dart-define=API_BASE_URL=...`을 붙인다.

```powershell
dart analyze
flutter test
flutter build web --wasm --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

공개 Web은 HTTPS가 필요하다. API 주소, CORS, Android 서명 설정은
[배포 문서](../docs/deployment.md)에 적어 두었다.

## 코드 위치

```text
lib/core/       API, 라우팅, 세션, 테마
lib/features/   화면별 data/domain/presentation 코드
assets/         캐릭터, 방, 식물 이미지
test/           단위·위젯 테스트
```

화면 캡처는 앱 안에 넣지 않고 [docs/screenshots](../docs/screenshots/README.md)에
Android와 Web을 나눠 보관한다.
