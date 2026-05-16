import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vestimate/core/theme/theme.dart';
import 'package:vestimate/features/wardrobe/domain/wardrobe_notifier.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobeState = ref.watch(wardrobeProvider);
    final itemCount = wardrobeState.maybeWhen(data: (items) => items.length, orElse: () => 0);

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
              width: 80, height: 80,
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

            // ── Stats Row ───────────────────────────────────────────────
            Row(
              children: [
                _stat(context, '$itemCount', 'Items'),
                _stat(context, '12', 'Outfits'),
                _stat(context, '94%', 'Match'),
              ],
            ),

            const SizedBox(height: V.s32),

            // ── Preferences ─────────────────────────────────────────────
            _sectionTitle('Preferences'),
            const SizedBox(height: V.s8),
            _prefRow(Icons.wb_sunny_outlined, 'Weather Integration', 'Auto-sync enabled', true),
            _prefRow(Icons.calendar_today_outlined, 'Calendar Sync', 'Not connected', false),
            _prefRow(Icons.notifications_none_rounded, 'Notifications', 'Daily styling tips', true),
            _prefRow(Icons.palette_outlined, 'Style Profile', 'Smart Casual', null),

            const SizedBox(height: V.s24),

            // ── Style Analytics ──────────────────────────────────────────
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

            // ── Actions ─────────────────────────────────────────────────
            _sectionTitle('Account'),
            const SizedBox(height: V.s8),
            _actionRow(Icons.auto_awesome, 'AI Style Coach', () {}),
            _actionRow(Icons.download_outlined, 'Export Wardrobe Data', () {}),
            _actionRow(Icons.info_outline_rounded, 'About Vestimate', () {}),
            _actionRow(Icons.logout_rounded, 'Sign Out', () {
              HapticFeedback.mediumImpact();
            }, isDanger: true),

            const SizedBox(height: V.s24),

            Text('Vestimate v2.0', style: V.caption.copyWith(color: V.textMuted)),
            const SizedBox(height: V.s4),
            Text('AI-Powered Wardrobe Management', style: V.caption.copyWith(color: V.textMuted, fontSize: 9)),

            const SizedBox(height: V.s48),
          ],
        ),
      ),
    );
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

  Widget _prefRow(IconData icon, String title, String subtitle, bool? isOn) {
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
          if (isOn != null)
            Container(
              width: 36, height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isOn ? V.success.withOpacity(0.2) : V.bgSurface,
                border: Border.all(color: isOn ? V.success.withOpacity(0.4) : V.border),
              ),
              child: Align(
                alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16, height: 16,
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOn ? V.success : V.textMuted,
                  ),
                ),
              ),
            )
          else
            const Icon(Icons.chevron_right, size: 16, color: V.textMuted),
        ],
      ),
    );
  }

  Widget _bar(String label, double value) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label, style: V.caption.copyWith(color: V.textSecondary))),
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
                  gradient: const LinearGradient(colors: V.gradientAccent),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: V.s8),
        Text('${(value * 100).toInt()}%', style: V.caption.copyWith(color: V.textTertiary)),
      ],
    );
  }

  Widget _actionRow(IconData icon, String title, VoidCallback onTap, {bool isDanger = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: V.s6),
        padding: const EdgeInsets.symmetric(horizontal: V.s16, vertical: V.s12),
        decoration: BoxDecoration(
          color: V.bgCard,
          borderRadius: BorderRadius.circular(V.r12),
          border: Border.all(color: isDanger ? V.danger.withOpacity(0.2) : V.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isDanger ? V.danger : V.accentSoft),
            const SizedBox(width: V.s12),
            Text(title, style: V.body.copyWith(
              fontSize: 14, color: isDanger ? V.danger : V.textPrimary,
            )),
            const Spacer(),
            Icon(Icons.chevron_right, size: 16, color: isDanger ? V.danger.withOpacity(0.5) : V.textMuted),
          ],
        ),
      ),
    );
  }
}
