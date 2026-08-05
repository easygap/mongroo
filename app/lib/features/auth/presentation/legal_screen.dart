import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';

enum LegalDocument {
  terms,
  privacy,
  sensitive;

  static LegalDocument fromPath(String? path) => switch (path) {
        'privacy' => LegalDocument.privacy,
        'sensitive' => LegalDocument.sensitive,
        _ => LegalDocument.terms,
      };
}

class _LegalSection {
  const _LegalSection(this.title, this.body);

  final String title;
  final String body;
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final content = _content(document);
    final version = _version(document);
    return Scaffold(
      appBar: AppBar(title: Text(content.$1)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      content.$1,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '시행일 ${_displayDate(version)} · 버전 $version',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 20),
                    _OperatorDisclosure(document: document),
                    const SizedBox(height: 24),
                    for (final section in content.$2) ...[
                      Text(
                        section.title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        section.body,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.65,
                            ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperatorDisclosure extends StatelessWidget {
  const _OperatorDisclosure({required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final configured = AppConfig.publicLegalMetadataConfigured;
    final scheme = Theme.of(context).colorScheme;
    final operator =
        configured ? AppConfig.serviceOperatorName : '운영자 정보 미설정(개발 빌드)';
    final address = configured ? AppConfig.serviceOperatorAddress : '미설정';
    final contact = configured ? AppConfig.privacyContactEmail : '미설정';
    final hosting = configured ? AppConfig.dataHostingDisclosure : '미설정';
    return Semantics(
      container: true,
      label: configured ? '서비스 운영 정보' : '공개 배포 전 운영 정보 입력 필요',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: configured
              ? scheme.surfaceContainerHighest
              : scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                configured ? '서비스 운영 정보' : '개발 빌드 안내',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text('운영자: $operator\n주소: $address\n문의: $contact'),
              if (document != LegalDocument.terms) Text('데이터 호스팅: $hosting'),
              if (!configured) ...[
                const SizedBox(height: 8),
                const Text('이 빌드는 공개 서비스용 법적 고지값이 입력되지 않았습니다.'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

(String, List<_LegalSection>) _content(LegalDocument document) =>
    switch (document) {
      LegalDocument.terms => ('이용약관', _terms),
      LegalDocument.privacy => ('개인정보처리방침', _privacy),
      LegalDocument.sensitive => ('민감정보 처리 동의', _sensitive),
    };

String _version(LegalDocument document) => switch (document) {
      LegalDocument.terms => AppConfig.termsVersion,
      LegalDocument.privacy => AppConfig.privacyVersion,
      LegalDocument.sensitive => AppConfig.sensitiveConsentVersion,
    };

String _displayDate(String version) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(version);
  if (match == null) return version;
  return '${int.parse(match.group(1)!)}년 ${int.parse(match.group(2)!)}월 '
      '${int.parse(match.group(3)!)}일';
}

const _terms = [
  _LegalSection(
    '1. 서비스의 목적',
    '몽그루는 마음 일기를 기록하고, 기록에서 자란 가상 캐릭터와 함께 회고·정원 꾸미기·탐험을 즐기는 웰니스 서비스입니다. 의료 진단, 치료, 처방 또는 응급 대응을 제공하지 않습니다.',
  ),
  _LegalSection(
    '2. 계정과 이용 연령',
    '공개 서비스는 만 18세 이상만 이용할 수 있습니다. 이용자는 본인이 관리하는 이메일을 사용하고 비밀번호와 기기를 안전하게 관리해야 합니다. 타인의 계정 사용, 서비스 방해, 자동화된 부정 요청은 금지됩니다.',
  ),
  _LegalSection(
    '3. 기록과 캐릭터 콘텐츠',
    '이용자는 자신이 작성할 권리가 있는 내용만 기록해야 합니다. 씨앗, 의상, 캐릭터 경험치와 탐험 아이템은 서비스 안의 가상 재화이며 현금 가치나 환급 권리를 갖지 않습니다. 밸런스 조정은 기존 애착과 진행을 과도하게 훼손하지 않는 범위에서 고지 후 적용합니다.',
  ),
  _LegalSection(
    '4. 안전과 서비스 제한',
    '위기 표현이 감지되면 일부 게임 기능보다 공식 도움 경로를 먼저 안내할 수 있습니다. 이는 전문적인 위험 평가가 아닙니다. 보안, 법령 준수, 장애 대응에 필요한 경우 최소 범위에서 이용을 제한할 수 있습니다.',
  ),
  _LegalSection(
    '5. 변경·중단과 문의',
    '중요한 약관 변경은 적용 전에 앱 또는 배포 페이지에서 알립니다. 운영자와 문의 채널은 이 문서 상단과 앱 스토어 등록 정보에 최신 상태로 제공합니다.',
  ),
];

const _privacy = [
  _LegalSection(
    '1. 처리하는 정보',
    '계정 정보(이메일, 닉네임, 비밀번호 해시), 마음 일기와 사용자가 입력한 태그, 감정 분석 결과, 캐릭터 성장·정원·탐험 기록, 대화와 리포트, 안전 신호의 분류 코드, 접속 보안 기록을 처리합니다. 안전 이벤트에는 일기 원문을 중복 저장하지 않습니다.',
  ),
  _LegalSection(
    '2. 이용 목적',
    '로그인과 계정 보호, 일기 저장·회고, 캐릭터 성장과 탐험 진행, AI 분석·대화, 보상 중복 방지, 장애·보안 대응을 위해서만 사용합니다. 광고 프로파일링이나 데이터 판매에는 사용하지 않습니다.',
  ),
  _LegalSection(
    '3. 보관과 보호',
    '계정이 유지되는 동안 필요한 정보를 보관하고 탈퇴 시 사용자 소유 데이터와 인증 세션을 삭제합니다. 법령상 별도 보관 의무가 있다면 해당 항목만 분리 보관한 뒤 파기합니다. 일기·대화·분석 결과·리포트와 재시도 응답은 AES-256-GCM 필드 암호화로 저장하고 키는 데이터베이스와 분리합니다. 전송 구간은 HTTPS를 사용합니다.',
  ),
  _LegalSection(
    '4. 이용자의 권리',
    '계정과 데이터 화면에서 보유 데이터를 JSON으로 내보내고 계정을 직접 삭제할 수 있습니다. 기록은 개별 수정·삭제할 수 있습니다. 동의 철회는 계정 삭제로 요청할 수 있으며, 필수 민감정보 처리를 거부하면 마음 일기 기반 기능을 제공할 수 없습니다.',
  ),
  _LegalSection(
    '5. 제공·처리위탁과 국외 이전',
    '현재 배포의 데이터 호스팅 정보는 이 문서 상단에 표시합니다. 메일, 오류 관측 또는 외부 AI 처리 사업자를 추가하는 경우 사업자명·국가·항목·목적·기간·거부 방법을 적용 전에 고지합니다. 해당 고지가 없는 외부 사업자에게 마음 기록 원문을 보내지 않습니다.',
  ),
  _LegalSection(
    '6. 문의',
    '개인정보 관련 열람·정정·삭제·처리정지 문의는 이 문서 상단의 개인정보 문의 이메일로 접수합니다. 운영자와 연락처는 앱 스토어 개발자 정보에도 동일하게 고지합니다.',
  ),
];

const _sensitive = [
  _LegalSection(
    '처리 항목',
    '마음 일기와 대화의 자유본문, 감정 태그, 감정 분석 라벨·점수, 회고 리포트 및 안전 신호처럼 건강 상태나 심리 상태를 드러내거나 추론할 수 있는 정보를 처리합니다.',
  ),
  _LegalSection(
    '처리 목적과 기간',
    '일기 회고, 캐릭터 성장, 안전 안내, 사용자가 요청한 AI 대화와 리포트를 제공하기 위해 계정 탈퇴 또는 동의 철회 때까지 처리합니다. 법령상 보존 의무가 있는 경우 그 기간만큼 별도 보관합니다.',
  ),
  _LegalSection(
    '동의 거부 권리',
    '민감정보 처리에 동의하지 않을 수 있습니다. 다만 마음 일기 분석과 그에 따른 성장·회고가 서비스의 핵심이므로 동의하지 않으면 계정을 만들고 핵심 기능을 이용할 수 없습니다.',
  ),
  _LegalSection(
    '보호 방식',
    '민감한 자유본문과 분석 결과는 인증된 암호화로 저장하고, 접근 토큰과 암호화 키를 원문 데이터와 분리합니다. 원문은 요청 로그와 메트릭에 남기지 않습니다.',
  ),
];
