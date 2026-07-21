import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/member_colors.dart';
import '../application/auth_controller.dart';

/// 명세 1. 회원관리 — 마이페이지 (닉네임 변경 / 로그아웃).
/// TODO(M2+): 회원 탈퇴 — 본인이 방장인 앨범은 위임/삭제 선택 필수 (B2, 앨범 기능 이후)
class MyPageScreen extends ConsumerWidget {
  const MyPageScreen({super.key});

  Future<void> _changeNickname(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('닉네임 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(helperText: '닉네임은 언제든 바꿀 수 있어요'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (next != null && next.isNotEmpty && next != current) {
      await ref.read(authControllerProvider.notifier).updateNickname(next);
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('로그아웃')),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(authControllerProvider.notifier).signOut();
      if (context.mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final color = MemberColors.fromHex(user?.color, fallbackSeed: user?.id ?? '');

    return Scaffold(
      appBar: AppBar(title: const Text('마이페이지')),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                CircleAvatar(radius: 36, backgroundColor: color, child: const Icon(Icons.person, size: 40, color: Colors.white)),
                const SizedBox(height: 12),
                Text(user?.nickname ?? '게스트', style: Theme.of(context).textTheme.titleLarge),
                Text('내 색상', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('닉네임 변경'),
            onTap: user == null ? null : () => _changeNickname(context, ref, user.nickname),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('로그아웃'),
            onTap: () => _logout(context, ref),
          ),
          const ListTile(
            leading: Icon(Icons.delete_forever),
            title: Text('회원 탈퇴'),
            subtitle: Text('앨범 기능과 함께 준비 중이에요 (B2)'),
            enabled: false,
          ),
        ],
      ),
    );
  }
}
