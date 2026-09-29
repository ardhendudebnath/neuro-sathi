import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../l10n.dart';
import '../state/app_state.dart';

const _regions = {
  'assam': 'Assam',
  'arunachal': 'Arunachal Pradesh',
  'manipur': 'Manipur',
  'meghalaya': 'Meghalaya',
  'mizoram': 'Mizoram',
  'nagaland': 'Nagaland',
  'sikkim': 'Sikkim',
  'tripura': 'Tripura',
};

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _linkCode;
  String? _error;
  bool _voiceConsent = false;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).profile().then((p) {
      if (mounted) setState(() => _voiceConsent = p['voice_consent'] == true);
    }).catchError((Object _) {}); // offline: keep the safe default (off)
  }

  Future<void> _getLinkCode() async {
    setState(() => _error = null);
    try {
      final r = await ref.read(apiProvider).linkCode();
      final code = r['code'] as String;
      setState(() => _linkCode = code);
      // Read it slowly, letter by letter.
      await ref.read(voiceProvider).speak(code.split('').join(', '));
    } on OfflineException {
      setState(() => _error = 'Please connect to the internet to create a code.');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _setVoiceConsent(bool value) async {
    try {
      await ref.read(apiProvider).updateProfile({'voice_consent': value});
      setState(() => _voiceConsent = value);
    } on OfflineException {
      setState(() => _error = 'Please connect to the internet to change this.');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final s = app.strings;
    final ctrl = ref.read(appProvider.notifier);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          Text(s.t('choose_language'), style: text.titleLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [for (final e in Strings.supported.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {app.language},
            onSelectionChanged: (v) => ctrl.setLanguage(v.first),
          ),
          const SizedBox(height: 24),
          Text(s.t('text_size'), style: text.titleLarge),
          Slider(
            value: app.fontScale,
            min: 1.2,
            max: 2.0,
            divisions: 4,
            label: '${(app.fontScale / 1.4 * 100).round()}%',
            onChanged: ctrl.setFontScale,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: app.region,
            decoration: const InputDecoration(labelText: 'State / Region'),
            items: [for (final e in _regions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => v == null ? null : ctrl.setRegion(v),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.t('link_caregiver'), style: text.titleLarge),
                  const SizedBox(height: 8),
                  Text(s.t('link_code_help'), style: text.bodyLarge),
                  const SizedBox(height: 12),
                  if (_linkCode != null)
                    SelectableText(_linkCode!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 40, letterSpacing: 6, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _getLinkCode, child: Text(s.t('link_caregiver'))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _voiceConsent,
            onChanged: _setVoiceConsent,
            title: Text(s.t('voice_consent'), style: text.titleLarge),
            subtitle: Text(s.t('voice_consent_help')),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () async {
              await ctrl.signOut();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: Text(s.t('sign_out')),
          ),
          const SizedBox(height: 24),
          Text(
            'NEURO-SATHI supports memory and daily routines. It does not diagnose. Please see a doctor for health concerns.',
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }
}
