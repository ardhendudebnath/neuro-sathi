import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/repository.dart';
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('talk_to_sathi'))),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_thinking ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _messages.length) {
                  return const Padding(padding: EdgeInsets.all(12), child: Text('…', style: TextStyle(fontSize: 32)));
                }
                final m = _messages[i];
                return Align(
                  alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(16),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                    decoration: BoxDecoration(
                      color: m.fromUser ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text(m.text, style: Theme.of(context).textTheme.bodyLarge)),
                        if (!m.fromUser) SpeakButton(m.text),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 96,
                    child: FilledButton.icon(
                      onPressed: _thinking ? null : _listen,
                      icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, size: 44),
                      label: Text(_listening ? s.t('listening') : s.t('tap_to_speak'), style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          style: const TextStyle(fontSize: 20),
                          decoration: InputDecoration(hintText: s.t('type_instead')),
                          onSubmitted: _ask,
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(onPressed: _thinking ? null : () => _ask(_input.text), child: Text(s.t('ask'))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
