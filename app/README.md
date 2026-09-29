# 몽그루 실행 안내

내 PC에서 몽그루를 실행하는 방법입니다. 게임 소개는 [메인 README](../README.md)에서 볼 수 있습니다.

## Windows에서 처음 실행하기

Git, Flutter 3.44.6, Python 3.12, Docker Desktop이 필요합니다. Docker Desktop을 켠 뒤 PowerShell에서 진행하세요.

```powershell
git clone https://github.com/easygap/mongroo.git
cd mongroo

# 처음 한 번: Python 환경, DB, 기본 설정 준비
powershell -ExecutionPolicy Bypass -File scripts/bootstrap.ps1

# 데모 서버와 일기 처리 실행
powershell -ExecutionPolicy Bypass -File scripts/start_demo.ps1 -AiMode fake

# Chrome에서 게임 열기
cd app
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

위 설정은 외부 AI 서비스에 연결하지 않는 로컬 데모입니다. 앱이 열리면 **회원가입 없이 3분 체험**으로 먼저 둘러보거나, 데모 계정을 만들어 플레이할 수 있습니다. 체험 기록은 사용 중인 기기에만 저장되며 가입한 계정으로 자동 이전되지 않습니다.

다음부터는 서버 실행과 `flutter run`만 진행하면 됩니다. 데모를 끝낼 때는 저장소 최상위 폴더에서 `scripts/stop_demo.ps1`을 실행하세요.

## Android에서 실행하기

Android SDK와 에뮬레이터가 준비돼 있다면 `app/`에서 다음 명령으로 실행합니다.

```powershell
flutter run
```

Android 에뮬레이터의 기본 API 주소는 `http://10.0.2.2:8000/api/v1`입니다. 실제 휴대폰이나 다른 서버에 연결하려면 해당 기기에서 접속할 수 있는 주소를 `--dart-define=API_BASE_URL=...`로 지정하세요. Web에서 주소를 생략하면 게임을 연 도메인의 `/api/v1`에 연결합니다.

## 빌드와 배포

```powershell
flutter analyze
flutter test
flutter build web --wasm --no-web-resources-cdn --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

앱 본문은 Wanted Sans를 사용합니다. 글꼴 파일을 앱에 포함했으며, Flutter Web의 기본 대체 글꼴도 로컬 파일로 연결했습니다. 공개 Web 빌드에서는 `--no-web-resources-cdn`을 유지합니다. 사용한 글꼴의 출처와 라이선스는 [글꼴 안내](assets/fonts/README.md)에 있습니다.

공개 Web은 HTTPS가 필요합니다. 운영자명·주소·개인정보 문의 이메일·데이터 저장 위치, 약관·개인정보 처리방침·민감정보 동의 버전도 빌드에 포함해야 합니다. 공식 Docker 빌드와 릴리스 작업은 필수 설정이 빠지면 중단됩니다. API 주소, CORS, AI 연결, Android 서명과 운영 설정은 [배포 안내](../docs/deployment.md)를 확인하세요.

## 코드와 관련 자료

| 위치 | 내용 |
| --- | --- |
| `lib/core/` | API 연결, 화면 이동, 로그인 상태, 테마 |
| `lib/features/` | 기능별 화면과 데이터 처리 |
| `assets/` | 캐릭터, 방, 탐험, 효과음, 글꼴 |
| `test/` | 단위·위젯 테스트 |

[화면 캡처](../docs/screenshots/README.md) · [게임 구조](../docs/combat_system_design_v8.md) · [화면·글꼴 기준](../design-system/2026-09-22-interface-research.md) · [출시 검수](../docs/release-review-2026-09-22.md) · [보상·성능 검수](../docs/game-feedback-review-2026-09-22.md)
