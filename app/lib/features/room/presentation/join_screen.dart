import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/ui.dart';
import '../../auth/application/auth_controller.dart';
import '../data/room_repository.dart';

/// 명세 3. 실시간 방 — 초대 코드/링크로 참여 (게스트 포함, A10).
///
/// 로그인 유저면 닉네임 입력 없이 참여하고, 비로그인(게스트)이면 닉네임만 입력한다.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.invite});

  /// 초대 링크로 진입 시 쿼리로 넘어온 초대 토큰/코드.
  final String? invite;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  late final TextEditingController _invite;
  final _nickname = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _invite = TextEditingController(text: widget.invite ?? '');
  }

  @override
  void dispose() {
    _invite.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final invite = _invite.text.trim();
    if (invite.isEmpty) {
      setState(() => _error = '초대 코드를 입력해주세요');
      return;
    }
    final isGuest = !ref.read(authControllerProvider).isSignedIn;
    final nickname = _nickname.text.trim();
    if (isGuest && nickname.isEmpty) {
      setState(() => _error = '닉네임을 입력해주세요');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final joined = await ref.read(roomRepositoryProvider).join(
            invite: invite,
            nickname: isGuest ? nickname : null,
          );
      ref.read(memberTokenStoreProvider.notifier).save(joined.session.id, joined.memberToken);
      if (mounted) context.go('/rooms/${joined.session.id}');
    } catch (e) {
      if (mounted) setState(() => _error = '참여하지 못했어요. 코드를 확인해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = !ref.watch(authControllerProvider).isSignedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('방 참여')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadInput(
              controller: _invite,
              label: '초대 코드',
              hint: '예: 4N1XUV',
              error: isGuest ? null : _error,
            ),
            if (isGuest) ...[
              const SizedBox(height: 16),
              ShadInput(
                controller: _nickname,
                label: '닉네임',
                hint: '닉네임만 정하면 바로 들어갈 수 있어요',
                error: _error,
              ),
            ],
            const SizedBox(height: 24),
            ShadButton(
              onPressed: _join,
              loading: _busy,
              expanded: true,
              child: const Text('참여하기'),
            ),
          ],
        ),
      ),
    );
  }
}
