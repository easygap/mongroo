# 몽그루 품질 검증 기준

최종 갱신: 2026-07-15

현재 반복 실행할 수 있는 검사와 아직 확인하지 못한 항목을 기록한다. 기능·UI·콘텐츠를
바꾼 뒤에는 자동 검사와 주요 사용자 흐름을 다시 확인한다.

## 1. 자동 검사

| 영역 | 명령 | 현재 기준 |
|---|---|---|
| Flutter 정적 분석 | `cd app; dart analyze` | 경고·오류 0 |
| Flutter 단위/위젯 | `cd app; flutter test` | 137 passed |
| Web 릴리스 빌드 | `cd app; flutter build web --wasm --release --dart-define=API_BASE_URL=...` | 성공 |
| 서버 전체 | `cd server; pytest -q` | 164 passed |
| Python import/문법 | `python -m compileall server/app server/tests` | 성공 |
| API 계약 | `cd server; python -m app.export_openapi` | `server/openapi.json`과 일치 |
| 공백·줄끝 검사 | `git diff --check` | 오류 0 |

Android APK/AAB는 Android SDK와 release keystore가 준비된 환경에서 별도로 검증한다.
현재 개발 PC는 Android SDK가 없어 Web 빌드까지만 실행 가능하다.

## 2. 핵심 사용자 여정

390×844 모바일 Web에서 실제 API·worker·DB를 연결해 다음 순서를 검증한다.

1. 가입 → starter 캐릭터 자동 장착 → 로그인/토큰 갱신
2. 감정을 직접 고르지 않고 일기 작성 → 본문 분석 → XP/씨앗 즉시 반영
3. 방 테마 미리보기 → 씨앗 구매 → 도감 소유 상태 → 바로 적용·저장
4. 퀘스트 누적/7일 연속/구미호 보유/아이템 5종 조건의 잠금 진행도 → 달성 후
   해금받기 → 중복 claim 없이 적용
5. 홈에서 저장한 메인 캐릭터와 재화가 즉시 동기화되는지 확인
6. 대화 시작 → worker 응답 → 실패/재시도와 빈 입력 방지
7. 캘린더 일자 상세 → 월간 리포트·차트 연결
8. 씨앗·새싹 공통 성장 → 줄기부터 외형·성격 분기 → 만개 모습 그대로 수확 → 최근 10그루/대표 10그루
   박물관 전시 → 선택 해제와 10그루 제한 오류 복구
9. 위기 표현 기록 → 안전 화면 즉시 이동 → 퀘스트 억제 → 공식 지원 경로 노출

퀘스트는 36종·10개 카테고리이며, 같은 사용자/날짜에 결정적으로 재현된다. 최근
14일 중복을 피하고 직전 2회의 같은 카테고리를 피하는 회전 테스트와 30일 시뮬레이션을
유지한다. 보상은 기록 저장·퀘스트 완료·대화 시작 각각의 서버 원장 이벤트로 한 번만
지급되어야 한다.

## 3. UI·접근성 회귀 범위

- 360px/390px 모바일, 1440px 데스크톱
- 밝은/어두운 테마
- 200% 글자 배율
- 움직임 줄이기 설정(`prefers-reduced-motion`, Flutter `disableAnimations`)
- 키보드 포커스, 최소 48×48 logical pixel 터치 영역, 의미 레이블
- 긴 한국어 문구, 빈 상태, 로딩·오류·재시도·저장 충돌 상태
- 방 테마 6종의 16:9 crop, 잠금 scrim, 긴 획득 조건, 진행도 0/중간/달성,
  구매·claim 중복 탭, 획득 직후 바로 적용과 reduced motion 상태
- BI 심볼 16/24/34/160px 가독성, favicon 16/32/48px, PWA normal/maskable
  안전영역, Android adaptive/monochrome resource, native splash와 첫 Flutter frame 색 일치

Flutter semantics를 활성화한 모바일 Lighthouse snapshot은 화면에 따라 접근성 93~94,
Best Practices 100, SEO 100을 기록했다. 접근성 감점은 Flutter 3.44 엔진이 런타임에
주입하는 `maximum-scale=1, user-scalable=no` viewport 한 건이다. 앱 위젯 수준의
대비·레이블·확대 글자 검증은 별도 테스트로 유지하며, Flutter 업그레이드 때 이 엔진
제약을 다시 확인한다.

## 4. Web 성능 기준

2026-07-15 릴리스 빌드에서 다음을 확인했다.

- `main.dart.wasm`: 압축 전 3,070,195 bytes
- 방 배경 WebP: 파일당 약 50~130KB
- 390×844 박물관 화면에서는 `night-museum-ink.webp`를 요청하지 않고 세로 목록만 렌더링
- 로딩 셸은 Flutter 첫 프레임까지 유지되며, 20초가 지나면 네트워크 안내와 다시
  불러오기 버튼을 표시
- 실제 화면 흐름에서 브라우저 콘솔 오류·경고 0

로컬 Python 정적 서버는 압축·캐시·COOP/COEP 헤더를 제공하지 않으므로 여기서 얻은
로드 시간은 공개 환경의 성능 수치로 쓰지 않는다. Core Web Vitals, 전송 용량과 캐시
적중률은 최종 CDN에서 모바일 네트워크 조건으로 다시 측정한다. 공개 배포 설정은
[deployment.md](deployment.md#3-web-정적-호스팅과-원자적-배포)를 따른다.

## 5. 공개 배포 전 남은 조건

- `DATA_PROFILE=demo` 제한을 해제하기 전 개인정보 보관·삭제·암호화 정책 검증
- 무작위 운영 JWT secret, HTTPS, 정확한 CORS, MySQL/Ollama 비공개 네트워크
- 실제 MySQL 인스턴스에서 다중 API 프로세스 동시성·부하 테스트
- Android SDK에서 AAB 회귀 테스트와 운영 keystore 서명
- 실제 CDN에서 Brotli/gzip, MIME, cache, COOP/COEP, 원자적 되돌리기 확인
- 운영 AI 모델에서 안전 분류·지원 경로·latency 모니터링 재검증
