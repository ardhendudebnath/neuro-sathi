import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/repository.dart';
import '../design/sathi_orb.dart';
import '../services/sathi_local.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class _Message {
  const _Message(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

/// "Sathi", the voice companion. Everyday questions are answered on the phone
/// from the user's own reminders and memory book (works offline, nothing leaves
/// the device); other questions go to the backend companion when online.
class SathiScreen extends ConsumerStatefulWidget {
  const SathiScreen({super.key});

  /// The deep sky behind Sathi; also the color the screen grows from.
  static const background = Color(0xFF152B42);

  @override
  ConsumerState<SathiScreen> createState() => _SathiScreenState();
}

class _SathiScreenState extends ConsumerState<SathiScreen> {
  final _messages = <_Message>[];
  final _input = TextEditingController();
  bool _listening = false;
  bool _thinking = false;
  late final _voice = ref.read(voiceProvider);

  @override
  void initState() {
    super.initState();
    _voice;
  }

  @override
  void dispose() {
    _input.dispose();
    _voice.stopListening();
    _voice.stop();
    super.dispose();
  }

  Future<String> _answer(String question) async {
    final repo = ref.read(repoProvider);
    final app = ref.read(appProvider);
    final lang = app.language;
    final pack = app.currentPack;
    final english = app.catalog.english;
    final reminders = (await repo.reminders()).map((r) {
      final p = r.timeOfDay.split(':').map(int.parse).toList();
      return LocalReminder(r.title, r.kind, p[0], p[1], daysOf(r), active: r.active);
    }).toList();
    final people = (await repo.memories())
        .map((m) => LocalPerson(title: m.title, name: m.personName, relationship: m.relationship, description: m.description))
        .toList();
    final local = answerLocally(question, pack, english, reminders, people, DateTime.now());
    if (local != null) {
      await repo.logActivity('sathi_ask', {'source': 'local', 'language': lang});
      return local;
    }
    try {
      // Only the question text is sent; the server logs no question text.
      final r = await ref.read(apiProvider).sathiAsk(question, lang);
      return r['answer'] as String;
    } on OfflineException {
      await repo.logActivity('sathi_ask', {'source': 'offline_fallback', 'language': lang});
      return fallbackAnswer(pack, english);
    } on ApiException {
      return fallbackAnswer(pack, english);
    }
  }

  Future<void> _ask(String question) async {
    if (question.trim().isEmpty) return;
    setState(() {
      _messages.add(_Message(question.trim(), fromUser: true));
      _thinking = true;
    });
    _input.clear();
    final answer = await _answer(question.trim());
    if (!mounted) return;
    setState(() {
      _messages.add(_Message(answer, fromUser: false));
      _thinking = false;
    });
    await _voice.speak(answer);
  }

  Future<void> _listen() async {
    if (_listening) {
      await _voice.stopListening();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _voice.listen(
      (words) => _ask(words),
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final animate = !MediaQuery.of(context).disableAnimations;
    final width = MediaQuery.sizeOf(context).width;
    // Big while there is nothing to read; it moves up once the conversation starts.
    final orbSize = _messages.isEmpty ? (width * 0.62).clamp(180.0, 280.0).toDouble() : 128.0;
    const white = Colors.white;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: SathiScreen.background,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(s.t('talk_to_sathi')),
          backgroundColor: Colors.transparent,
          foregroundColor: white,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: white),
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.45),
              radius: 1.25,
              colors: [Color(0xFF1E5367), SathiScreen.background, Color(0xFF0A1324)],
              stops: [0, 0.48, 1],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const OfflineBanner(),
                AnimatedContainer(
                  duration: animate ? const Duration(milliseconds: 450) : Duration.zero,
                  curve: Curves.easeOutCubic,
                  width: orbSize,
                  height: orbSize,
                  child: FittedBox(child: SathiOrb(size: 280, listening: _listening || _thinking, animate: animate)),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    itemCount: _messages.length + (_thinking ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _messages.length) {
                        return const Padding(padding: EdgeInsets.all(12), child: Text('…', style: TextStyle(fontSize: 32, color: white)));
                      }
                      final m = _messages[i];
                      return Align(
                        alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: EdgeInsets.fromLTRB(16, 12, m.fromUser ? 16 : 6, 12),
                          constraints: BoxConstraints(maxWidth: width * 0.84),
                          decoration: BoxDecoration(
                            color: m.fromUser ? white.withValues(alpha: 0.16) : null,
                            gradient: m.fromUser
                                ? null
                                : LinearGradient(colors: [const Color(0xFF68D8C5).withValues(alpha: 0.32), const Color(0xFF3D8BF0).withValues(alpha: 0.26)]),
                            border: Border.all(color: (m.fromUser ? white : const Color(0xFF7EE3D2)).withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(22),
                              topRight: const Radius.circular(22),
                              bottomLeft: Radius.circular(m.fromUser ? 22 : 8),
                              bottomRight: Radius.circular(m.fromUser ? 8 : 22),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: Text(m.text, style: const TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w600, color: white))),
                              if (!m.fromUser) SpeakButton(m.text, foreground: white, background: white.withValues(alpha: 0.14)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    children: [
                      _MicButton(
                        label: _listening ? s.t('listening') : s.t('tap_to_speak'),
                        listening: _listening,
                        enabled: !_thinking,
                        onTap: _listen,
                      ),
                      Text(_listening ? s.t('listening') : s.t('tap_to_speak'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: white)),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              style: const TextStyle(fontSize: 20, color: white),
                              cursorColor: white,
                              decoration: InputDecoration(
                                hintText: s.t('type_instead'),
                                hintStyle: TextStyle(color: white.withValues(alpha: 0.7)),
                                filled: true,
                                fillColor: white.withValues(alpha: 0.1),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                                  borderSide: BorderSide(color: white.withValues(alpha: 0.3)),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(18)),
                                  borderSide: BorderSide(color: Color(0xFF7EE3D2), width: 2),
                                ),
                              ),
                              onSubmitted: _ask,
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: _thinking ? null : () => _ask(_input.text),
                            style: OutlinedButton.styleFrom(foregroundColor: white, side: BorderSide(color: white.withValues(alpha: 0.6), width: 2)),
                            child: Text(s.t('ask')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A raised round button that sinks when pressed, like a real one.
class _MicButton extends StatefulWidget {
  const _MicButton({required this.label, required this.listening, required this.enabled, required this.onTap});

  final String label;
  final bool listening;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final lip = _down ? 2.0 : 8.0;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.enabled ? widget.onTap : null,
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          width: 96,
          height: 96,
          margin: const EdgeInsets.only(bottom: 8),
          transform: Matrix4.translationValues(0, 8 - lip, 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.32, -0.44),
              colors: widget.listening
                  ? const [Color(0xFFFFD9CF), Color(0xFFF0604F), Color(0xFFA8281C)]
                  : const [Color(0xFF9FF0E2), Color(0xFF2FC0A8), Color(0xFF0F6E66)],
              stops: const [0, 0.32, 1],
            ),
            boxShadow: [
              BoxShadow(color: widget.listening ? const Color(0xFF6E1A12) : const Color(0xFF07433E), offset: Offset(0, lip)),
              BoxShadow(color: const Color(0xCC2FC0A8).withValues(alpha: widget.enabled ? 0.8 : 0.2), offset: Offset(0, lip + 12), blurRadius: 30, spreadRadius: -14),
            ],
          ),
          child: Icon(widget.listening ? Icons.stop_rounded : Icons.mic_rounded, size: 48, color: Colors.white.withValues(alpha: widget.enabled ? 1 : 0.5)),
        ),
      ),
    );
  }
}
