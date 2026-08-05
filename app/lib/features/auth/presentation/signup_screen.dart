import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';
import 'auth_scene.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _nicknameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _showValidationErrors = false;
  bool _ageOver18 = false;
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  bool _sensitiveConsent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    _nicknameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final valid = _formKey.currentState?.validate() ?? false;
    final agreementsAccepted =
        _ageOver18 && _termsAccepted && _privacyAccepted && _sensitiveConsent;
    if (!valid || !agreementsAccepted) {
      if (!_showValidationErrors) {
        setState(() => _showValidationErrors = true);
      }
      final nickname = _nicknameController.text.trim();
      final email = _emailController.text.trim();
      if (nickname.isEmpty || nickname.length > 30) {
        _nicknameFocusNode.requestFocus();
      } else if (email.isEmpty || !email.contains('@')) {
        _emailFocusNode.requestFocus();
      } else if (_passwordController.text.length < 8) {
        _passwordFocusNode.requestFocus();
      }
      if (!agreementsAccepted) {
        setState(() {
          _errorMessage = '필수 확인과 동의를 모두 선택해 주세요.';
        });
      }
      return;
    }
    final nickname = _nicknameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final error = await ref.read(authControllerProvider.notifier).signup(
          email: email,
          password: password,
          nickname: nickname,
          ageOver18: _ageOver18,
          termsAccepted: _termsAccepted,
          privacyAccepted: _privacyAccepted,
          sensitiveDataConsent: _sensitiveConsent,
        );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _errorMessage = error;
    });
  }

  void _clearServerError(String _) {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScene(
      showBack: true,
      navigationLocked: _submitting,
      title: '처음 시작하기',
      description: '계정을 만들고 첫 식물을 받으세요.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          autovalidateMode: _showValidationErrors
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nicknameController,
                focusNode: _nicknameFocusNode,
                enabled: !_submitting,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.nickname],
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '닉네임',
                  helperText: '1~30자',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  return name.isEmpty || name.length > 30
                      ? '닉네임은 1~30자로 입력해 주세요.'
                      : null;
                },
                onChanged: _clearServerError,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                enabled: !_submitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '이메일',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return email.isEmpty || !email.contains('@')
                      ? '올바른 이메일을 입력해 주세요.'
                      : null;
                },
                onChanged: _clearServerError,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                enabled: !_submitting,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  helperText: '8자 이상',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? '비밀번호 표시' : '비밀번호 숨기기',
                    onPressed: _submitting
                        ? null
                        : () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    (value ?? '').length < 8 ? '비밀번호는 8자 이상 입력해 주세요.' : null,
                onChanged: _clearServerError,
                onFieldSubmitted: (_) {
                  if (!_submitting) _submit();
                },
              ),
              const SizedBox(height: 20),
              Text(
                '시작 전 확인',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              _AgreementTile(
                value: _ageOver18,
                enabled: !_submitting,
                title: '만 18세 이상이에요',
                onChanged: (value) => setState(() {
                  _ageOver18 = value;
                  _errorMessage = null;
                }),
              ),
              _AgreementTile(
                value: _termsAccepted,
                enabled: !_submitting,
                title: '이용약관에 동의해요',
                links: [
                  _LegalLink(
                    label: '이용약관',
                    onTap: () => context.push('/legal/terms'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _termsAccepted = value;
                  _errorMessage = null;
                }),
              ),
              _AgreementTile(
                value: _privacyAccepted,
                enabled: !_submitting,
                title: '개인정보 수집·이용에 동의해요',
                links: [
                  _LegalLink(
                    label: '개인정보처리방침',
                    onTap: () => context.push('/legal/privacy'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _privacyAccepted = value;
                  _errorMessage = null;
                }),
              ),
              _AgreementTile(
                value: _sensitiveConsent,
                enabled: !_submitting,
                title: '마음 기록의 민감정보 처리에 동의해요',
                links: [
                  _LegalLink(
                    label: '민감정보 동의 내용',
                    onTap: () => context.push('/legal/sensitive'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _sensitiveConsent = value;
                  _errorMessage = null;
                }),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                AuthInlineError(message: _errorMessage!),
              ],
              const SizedBox(height: 22),
              Semantics(
                button: true,
                enabled: !_submitting,
                liveRegion: _submitting,
                label: _submitting ? '가입 중' : '가입하기',
                onTap: _submitting ? null : _submit,
                child: ExcludeSemantics(
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(_submitting ? '가입 중…' : '가입하기'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '가입하면 기본 식물과 아기 화분을 받아요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgreementTile extends StatelessWidget {
  const _AgreementTile({
    required this.value,
    required this.enabled,
    required this.title,
    required this.onChanged,
    this.links = const [],
  });

  final bool value;
  final bool enabled;
  final String title;
  final ValueChanged<bool> onChanged;
  final List<Widget> links;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: value,
            enabled: enabled,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            onChanged:
                enabled ? (checked) => onChanged(checked ?? false) : null,
          ),
          if (links.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44, bottom: 4),
              child: Wrap(spacing: 4, runSpacing: 4, children: links),
            ),
        ],
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        child: Text('$label 보기'),
      );
}
