import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/auth/data/auth_repository.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';
import 'package:vestimate/features/recommendation/domain/outfit_history_provider.dart';

// ── Preference state (persisted via Hive) ────────────────────────────────────
final _weatherEnabledProvider = StateProvider<bool>((ref) {
  final box = Hive.box('wardrobe_cache');
  return box.get('pref_weather', defaultValue: true) as bool;
});

final _notificationsEnabledProvider = StateProvider<bool>((ref) {
  final box = Hive.box('wardrobe_cache');
  return box.get('pref_notifications', defaultValue: true) as bool;
});

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobeState = ref.watch(wardrobeProvider);
    final historyState = ref.watch(outfitHistoryProvider);
    final weatherEnabled = ref.watch(_weatherEnabledProvider);
    final notificationsEnabled = ref.watch(_notificationsEnabledProvider);

    // Real counts from providers
    final itemCount = wardrobeState.maybeWhen(
        data: (items) => items.length, orElse: () => 0);
    final outfitCount = historyState.maybeWhen(
        data: (outfits) => outfits.length, orElse: () => 0);

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: V.s20),
        child: Column(
          children: [
            const SizedBox(height: V.s20),

            // ── Avatar + Name ───────────────────────────────────────────
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: V.gradientAccent),
                border: Border.all(color: V.border, width: 2),
              ),
              child: const Icon(Icons.person, size: 36, color: V.bg),
            ),
            const SizedBox(height: V.s16),
            Text('Vestimate User', style: V.h2),
            const SizedBox(height: V.s4),
            Text('Style Enthusiast', style: V.bodySmall),

            const SizedBox(height: V.s24),

            // ── Stats Row (Epic 5 — real data) ──────────────────────────
            Row(
              children: [
                _stat(context, '$itemCount', 'Items'),
                _stat(context, '$outfitCount', 'Outfits'),
                _stat(context, '—', 'Match'),
              ],
            ),

            const SizedBox(height: V.s32),

            // ── Preferences (Epic 5 — functional toggles) ───────────────
            _sectionTitle('Preferences'),
            const SizedBox(height: V.s8),
            _prefRow(
              icon: Icons.wb_sunny_outlined,
              title: 'Weather Integration',
              subtitle: weatherEnabled ? 'Auto-sync enabled' : 'Disabled',
              isOn: weatherEnabled,
              onToggle: (val) {
                ref.read(_weatherEnabledProvider.notifier).state = val;
                Hive.box('wardrobe_cache').put('pref_weather', val);
              },
            ),
            _prefRow(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              subtitle: notificationsEnabled ? 'Daily styling tips' : 'Muted',
              isOn: notificationsEnabled,
              onToggle: (val) {
                ref.read(_notificationsEnabledProvider.notifier).state = val;
                Hive.box('wardrobe_cache').put('pref_notifications', val);
              },
            ),
            _prefRow(
              icon: Icons.calendar_today_outlined,
              title: 'Calendar Sync',
              subtitle: 'Not connected',
              isOn: false,
              onToggle: (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Calendar sync coming soon!')),
                );
              },
            ),
            _prefRow(
              icon: Icons.palette_outlined,
              title: 'Style Profile',
              subtitle: 'Smart Casual',
              isOn: null,
              onToggle: null,
            ),

            const SizedBox(height: V.s24),

            // ── Style Analytics ───────────────────────────────────────────
            _sectionTitle('Style Analytics'),
            const SizedBox(height: V.s8),
            PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Most Worn Category', style: V.caption),
                  const SizedBox(height: V.s8),
                  _bar('Tops', 0.75),
                  const SizedBox(height: V.s6),
                  _bar('Bottoms', 0.6),
                  const SizedBox(height: V.s6),
                  _bar('Footwear', 0.4),
                  const SizedBox(height: V.s6),
                  _bar('Outerwear', 0.2),
                ],
              ),
            ),

            const SizedBox(height: V.s24),

            // ── Account Actions (Epic 5 — all wired) ────────────────────
            _sectionTitle('Account'),
            const SizedBox(height: V.s8),
            _actionRow(Icons.auto_awesome, 'AI Style Coach', () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('AI Style Coach coming soon!')),
              );
            }),
            _actionRow(Icons.download_outlined, 'Export Wardrobe Data', () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export feature coming soon!')),
              );
            }),
            _actionRow(Icons.info_outline_rounded, 'About Vestimate', () {
              showAboutDialog(
                context: context,
                applicationName: 'Vestimate',
                applicationVersion: 'v2.0',
                applicationLegalese: 'AI-Powered Wardrobe Management',
              );
            }),
            // Epic 5 — Sign Out properly wired
            _actionRow(
              Icons.logout_rounded,
              'Sign Out',
              () => _signOut(context, ref),
              isDanger: true,
            ),

            const SizedBox(height: V.s24),

            Text('Vestimate v2.0',
                style: V.caption.copyWith(color: V.textMuted)),
            const SizedBox(height: V.s4),
            Text('AI-Powered Wardrobe Management',
                style: V.caption
                    .copyWith(color: V.textMuted, fontSize: 9)),

            const SizedBox(height: V.s48),
          ],
        ),
      ),
    );
  }

  // Epic 5 — Sign Out: calls Supabase signOut then navigates to /login
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: V.bgCard,
        title: const Text('Sign Out', style: V.h3),
        content: const Text('Are you sure you want to sign out?',
            style: V.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL',
                style: TextStyle(color: V.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SIGN OUT',
                style: TextStyle(color: V.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(authRepositoryProvider).signOut();
      if (context.mounted) {
        context.go('/login');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e')),
        );
      }
    }
  }

  Widget _stat(BuildContext context, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: V.s16),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: V.bgCard,
          borderRadius: BorderRadius.circular(V.r16),
          border: Border.all(color: V.border, width: 0.5),
        ),
        child: Column(
          children: [
            Text(value, style: V.h2.copyWith(fontSize: 20)),
            const SizedBox(height: V.s4),
            Text(label, style: V.caption),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: V.h3),
    );
  }

  Widget _prefRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool? isOn,
    required void Function(bool)? onToggle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: V.s6),
      padding: const EdgeInsets.symmetric(horizontal: V.s16, vertical: V.s12),
      decoration: BoxDecoration(
        color: V.bgCard,
        borderRadius: BorderRadius.circular(V.r12),
        border: Border.all(color: V.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: V.accentSoft),
          const SizedBox(width: V.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: V.body.copyWith(fontSize: 14)),
                Text(subtitle, style: V.caption),
              ],
            ),
          ),
          if (isOn != null && onToggle != null)
            Switch(
              value: isOn,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                onToggle(val);
              },
              activeColor: V.accent,
              activeTrackColor: V.accent.withOpacity(0.3),
              inactiveThumbColor: V.textMuted,
              inactiveTrackColor: V.bgSurface,
            )
          else if (isOn == null)
            const Icon(Icons.chevron_right, size: 16, color: V.textMuted),
        ],
      ),
    );
  }

  Widget _bar(String label, double value) {
    return Row(
      children: [
        SizedBox(
            width: 70,
            child: Text(label,
                style: V.caption.copyWith(color: V.textSecondary))),
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: V.bgSurface,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: Container(
                decoration: BoxDecoration(
                  gradient:
                      const LinearGradient(colors: V.gradientAccent),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: V.s8),
        Text('${(value * 100).toInt()}%',
            style: V.caption.copyWith(color: V.textTertiary)),
      ],
    );
  }

  Widget _actionRow(IconData icon, String title, VoidCallback onTap,
      {bool isDanger = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: V.s6),
        padding: const EdgeInsets.symmetric(
            horizontal: V.s16, vertical: V.s12),
        decoration: BoxDecoration(
          color: V.bgCard,
          borderRadius: BorderRadius.circular(V.r12),
          border: Border.all(
              color: isDanger ? V.danger.withOpacity(0.2) : V.border,
              width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isDanger ? V.danger : V.accentSoft),
            const SizedBox(width: V.s12),
            Text(title,
                style: V.body.copyWith(
                    fontSize: 14,
                    color: isDanger ? V.danger : V.textPrimary)),
            const Spacer(),
            Icon(Icons.chevron_right,
                size: 16,
                color: isDanger
                    ? V.danger.withOpacity(0.5)
                    : V.textMuted),
          ],
        ),
      ),
    );
  }
}
