import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';

/// Large home-screen tile: one task per tile, emoji + label, 120+ dp tall.
class BigTile extends StatelessWidget {
  const BigTile({super.key, required this.emoji, required this.label, required this.onTap, this.color});
  final String emoji;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: color ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 130),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ExcludeSemantics(child: Text(emoji, style: const TextStyle(fontSize: 46))),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reads [text] aloud. Every screen has one so nothing depends on reading.
/// [foreground] and [background] restyle it, e.g. as glass on the home sky.
class SpeakButton extends ConsumerWidget {
  const SpeakButton(this.text, {super.key, this.foreground, this.background, this.border});
  final String text;
  final Color? foreground;
  final Color? background;
  final Color? border;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    void speak() {
      final voice = ref.read(voiceProvider);
      if (!voice.canSpeak) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s.t('voice_unavailable'))));
        return;
      }
      voice.speak(text);
    }

    if (foreground == null && background == null) {
      return IconButton.filledTonal(iconSize: 32, tooltip: s.t('read_aloud'), onPressed: speak, icon: const Icon(Icons.volume_up_rounded));
    }
    return IconButton(
      iconSize: 28,
      tooltip: s.t('read_aloud'),
      onPressed: speak,
      style: IconButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        side: border == null ? null : BorderSide(color: border!),
        minimumSize: const Size(52, 52),
      ),
      icon: const Icon(Icons.volume_up_rounded),
    );
  }
}

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(appProvider.select((s) => s.online));
    if (online) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4D6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFF9A6700)),
          const SizedBox(width: 10),
          Expanded(child: Text(ref.watch(stringsProvider).t('offline'), style: const TextStyle(color: Color(0xFF6B4A00)))),
        ],
      ),
    );
  }
}
