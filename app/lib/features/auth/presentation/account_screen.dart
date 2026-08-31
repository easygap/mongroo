import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/api_exception.dart';
import '../../expedition/presentation/expedition_combat_audio.dart';
import '../../expedition/presentation/expedition_settings.dart';
import '../data/auth_repository.dart';
import 'auth_controller.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _exporting = false;
  bool _deleting = false;
  bool _signingOutAll = false;

  /// 오래 걸리는 계정 작업이 도는 동안에는 다른 계정 작업을 열지 않는다.
  bool get _busy => _exporting || _deleting || _signingOutAll;

  Future<void> _exportAccount() async {
    if (_busy) return;
    setState(() => _exporting = true);
    try {
      final payload = await ref.read(authRepositoryProvider).exportAccount();
      final encoded = const JsonEncoder.withIndent('  ').convert(payload);
      if (!mounted) return;
      final copied = await showDialog<bool>(
        context: context,
        builder: (context) => _ExportReadyDialog(
          payload: encoded,
          byteLength: utf8.encode(encoded).length,
        ),
      );
      if (copied == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('내보낸 데이터를 클립보드에 복사했어요.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiException.from(error).message)),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _logoutAllDevices() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모든 기기에서 로그아웃할까요?'),
        content: const Text(
          '이 기기도 함께 로그아웃돼요. 기록과 캐릭터는 그대로 남고, 다시 로그인하면 이어서 볼 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('account-logout-all-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('모두 로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOutAll = true);
    final error =
        await ref.read(authControllerProvider.notifier).logoutAllDevices();
    if (!mounted) return;
    // 성공하면 라우터가 로그인 화면으로 옮기므로 여기서 상태를 되돌리지 않는다.
    if (error != null) {
      setState(() => _signingOutAll = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _deleteAccount() async {
    if (_busy) return;
    final credentials = await showDialog<_DeleteCredentials>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _DeleteAccountDialog(),
    );
    if (credentials == null || !mounted) return;
    setState(() => _deleting = true);
    final error = await ref.read(authControllerProvider.notifier).deleteAccount(
          password: credentials.password,
          confirmation: credentials.confirmation,
        );
    if (!mounted) return;
    if (error != null) {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_deleting && !_signingOutAll,
      child: Scaffold(
        appBar: AppBar(title: const Text('계정과 데이터')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.nickname ?? '몽그루 사용자',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? '',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '내 데이터',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '프로필, 마음 일기, 대화, 캐릭터 성장과 탐험 기록을 JSON으로 확인할 수 있어요. 비밀번호와 로그인 토큰은 포함하지 않아요.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _exportAccount,
                      icon: _exporting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined),
                      label: Text(_exporting ? '데이터 준비 중…' : '내 데이터 내보내기'),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      '로그인한 기기',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '다른 기기에 로그인한 채로 두고 왔다면 여기서 한 번에 끊을 수 있어요. 지금 이 기기도 함께 로그아웃돼요.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('account-logout-all'),
                      onPressed: _busy ? null : _logoutAllDevices,
                      icon: _signingOutAll
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.devices_other_outlined),
                      label: Text(
                        _signingOutAll ? '로그아웃하는 중…' : '모든 기기에서 로그아웃',
                      ),
                    ),
                    // 소리 설정은 전투 HUD 안에만 있었다. 그런데 그 값은 던전
                    // 발걸음·지도 확정음·모험 탭 cue·발견음까지 다스린다.
                    // 소리를 끄려고 전투에 들어가야 하는 건 설정이 아니다.
                    Text(
                      '소리',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '탐험 배경음과 효과음, 걸을 때 나는 소리와 발견 알림에 함께 적용돼요. 소리를 꺼도 판정과 결과는 화면에 그대로 남아요.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _SoundModeButton(),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      '앱 정보',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => context.push('/trial'),
                      icon: const Icon(Icons.school_outlined),
                      label: const Text('처음 사용 가이드 다시 보기'),
                    ),
                    const SizedBox(height: 8),
                    // 약관·처리방침은 가입 화면에서만 열 수 있었다. 가입하고
                    // 나면 내가 무엇에 동의했는지 다시 읽을 길이 앱에 없었고,
                    // 민감정보 동의는 특히 언제든 확인할 수 있어야 한다.
                    for (final legal in const [
                      ('terms', '이용약관'),
                      ('privacy', '개인정보처리방침'),
                      ('sensitive', '민감정보 처리 동의'),
                    ]) ...[
                      OutlinedButton.icon(
                        key: Key('account-legal-${legal.$1}'),
                        onPressed: _busy
                            ? null
                            : () => context.push('/legal/${legal.$1}'),
                        icon: const Icon(Icons.article_outlined),
                        label: Text(legal.$2),
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => showLicensePage(
                                context: context,
                                applicationName: '몽그루',
                              ),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('오픈소스 라이선스'),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      '계정 삭제',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '삭제하면 마음 일기, 대화, 정원, 캐릭터와 탐험 진행이 함께 삭제되며 되돌릴 수 없어요.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                        side: BorderSide(color: scheme.error),
                      ),
                      onPressed: _busy ? null : _deleteAccount,
                      icon: _deleting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_forever_outlined),
                      label: Text(_deleting ? '계정 삭제 중…' : '계정 영구 삭제'),
                    ),
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

/// 계정 화면에서 소리 단계를 바꾸는 버튼.
///
/// 전투 시트와 **같은 provider, 같은 순환**을 쓴다. 두 자리가 서로 다른 방식을
/// 쓰면 사용자가 두 가지를 배워야 하고, 한쪽에서 바꾼 값이 다른 쪽에 안
/// 보이는 것처럼 느껴진다.
class _SoundModeButton extends ConsumerWidget {
  const _SoundModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(expeditionBattleSettingsProvider);
    final notifier = ref.read(expeditionBattleSettingsProvider.notifier);
    return OutlinedButton.icon(
      key: const Key('account-sound-mode'),
      onPressed: notifier.cycleAudioMode,
      icon: Icon(switch (settings.audioMode) {
        ExpeditionAudioMode.all => Icons.volume_up_outlined,
        ExpeditionAudioMode.sfxOnly => Icons.music_off_outlined,
        ExpeditionAudioMode.muted => Icons.volume_off_outlined,
      }),
      label: Text('탐험 소리 · ${settings.audioLabel}'),
    );
  }
}

class _ExportReadyDialog extends StatelessWidget {
  const _ExportReadyDialog({required this.payload, required this.byteLength});

  final String payload;
  final int byteLength;

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        icon: const Icon(Icons.shield_outlined),
        title: const Text('내보내기 준비 완료'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            '약 ${_formatBytes(byteLength)}의 JSON 데이터예요. 클립보드에 복사하면 다른 앱이 읽을 수 있으니 개인 기기에서만 사용해 주세요.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: payload));
              if (context.mounted) Navigator.of(context).pop(true);
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('클립보드에 복사'),
          ),
        ],
      );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _DeleteCredentials {
  const _DeleteCredentials(this.password, this.confirmation);

  final String password;
  final String confirmation;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscure = true;

  bool get _canSubmit =>
      _password.text.isNotEmpty && _confirmation.text == '몽그루 탈퇴';

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        icon: Icon(Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error),
        title: const Text('계정을 영구 삭제할까요?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('이 작업은 되돌릴 수 없어요. 먼저 데이터를 내보냈는지 확인해 주세요.'),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: '현재 비밀번호',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? '비밀번호 표시' : '비밀번호 숨기기',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmation,
                decoration: const InputDecoration(
                  labelText: '확인 문구',
                  helperText: '몽그루 탈퇴라고 입력해 주세요.',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: _canSubmit
                ? () => Navigator.of(context).pop(
                      _DeleteCredentials(
                        _password.text,
                        _confirmation.text,
                      ),
                    )
                : null,
            child: const Text('영구 삭제'),
          ),
        ],
      );
}
