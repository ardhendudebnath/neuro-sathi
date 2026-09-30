import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../l10n.dart';
import '../state/app_state.dart';

// State names come from the language pack (regions section).
const _regions = ['assam', 'arunachal', 'manipur', 'meghalaya', 'mizoram', 'nagaland', 'sikkim', 'tripura'];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _linkCode;
  String? _error;
  bool _voiceConsent = false;
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).profile().then((p) {
      if (mounted) setState(() => _voiceConsent = p['voice_consent'] == true);
    }).catchError((Object _) {}); // offline: keep the safe default (off)
    // Written by both the app and the background sync worker.
    ref.read(dbProvider).getValue('last_sync_at').then((v) {
      final at = v == null ? null : DateTime.tryParse(v)?.toLocal();
      if (mounted && at != null) setState(() => _lastSync = at);
    }).catchError((Object _) {});
  }

  String _lastSyncText(Strings s) {
    final at = _lastSync;
    if (at == null) return s.t('never_synced');
    final now = DateTime.now();
    final time = s.formatTime(at.hour, at.minute);
    final today = at.year == now.year && at.month == now.month && at.day == now.day;
    return s.t('last_synced', {'time': today ? time : '${s.pack.localizeDigits('${at.day}/${at.month}')}, $time'});
  }

  Future<void> _getLinkCode() async {
    setState(() => _error = null);
    try {
      final r = await ref.read(apiProvider).linkCode();
      final code = r['code'] as String;
      setState(() => _linkCode = code);
      // Read it slowly, letter by letter.
      await ref.read(voiceProvider).speak(code.split('').join(', '));
    } on Exception catch (e) {
      setState(() => _error = _errorText(e));
    }
  }

  String _errorText(Exception e) {
    final s = ref.read(stringsProvider);
    if (e is OfflineException) return s.t('error_needs_internet');
    if (e is ApiException && e.status == 429) return s.t('error_try_later');
    return s.t('error_generic');
  }

  Future<void> _setVoiceConsent(bool value) async {
    try {
      await ref.read(apiProvider).updateProfile({'voice_consent': value});
      setState(() => _voiceConsent = value);
    } on Exception catch (e) {
      setState(() => _error = _errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final s = app.strings;
    final ctrl = ref.read(appProvider.notifier);
    final text = Theme.of(context).textTheme;
    final List<LanguagePack> languages = [
      ...app.catalog.visible,
      // Keep the current language selectable even if this build no longer offers it.
      if (!app.catalog.visible.any((p) => p.code == app.language)) app.currentPack,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          Text(s.t('choose_language'), style: text.titleLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: app.language,
            isExpanded: true,
            items: [
              for (final p in languages)
                DropdownMenuItem(
                  value: p.code,
                  child: Text(p.nativeName == p.englishName ? p.nativeName : '${p.nativeName}  (${p.englishName})'),
                ),
            ],
            onChanged: (v) => v == null ? null : ctrl.setLanguage(v),
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
            initialValue: _regions.contains(app.region) ? app.region : null,
            decoration: InputDecoration(labelText: s.t('region')),
            items: [for (final code in _regions) DropdownMenuItem(value: code, child: Text(s.region(code)))],
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
          Text(_lastSyncText(s), style: text.bodyMedium),
          const SizedBox(height: 12),
          Text(s.t('disclaimer'), style: text.bodyMedium),
        ],
      ),
    );
  }
}
