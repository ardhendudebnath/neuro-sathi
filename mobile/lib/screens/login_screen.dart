import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../widgets/tester_tools.dart';

enum _Step { language, phone, code }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.reauth = false});

  /// Signing in again after the session expired: the account and its data are
  /// already on the phone, so skip the language and name steps and offer "Later".
  final bool reauth;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  _Step step = _Step.language;
  final phone = TextEditingController();
  final code = TextEditingController();
  final name = TextEditingController();
  String? error;
  String? devCode;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.reauth) {
      step = _Step.phone;
      // Offer the same number, so the data on this phone stays with its owner.
      ref.read(dbProvider).getValue('phone').then((v) {
        if (mounted && v != null && phone.text.isEmpty) phone.text = v.startsWith('+91') ? v.substring(3) : v;
      }).catchError((Object _) {});
    } else if (ref.read(appProvider).catalog.visible.length <= 1) {
      step = _Step.phone; // nothing to choose when only one language is available in this build
    }
  }

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on OfflineException {
      setState(() => error = ref.read(stringsProvider).t('error_no_internet'));
    } on ApiException catch (e) {
      final s = ref.read(stringsProvider);
      setState(() => error = switch (e.status) {
            401 => s.t('error_wrong_code'),
            429 => s.t('error_try_later'),
            _ => s.t('error_generic'),
          });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
        final r = await ref.read(apiProvider).requestOtp(phone.text.trim());
        setState(() {
          devCode = r['dev_code'] as String?;
          step = _Step.code;
        });
      });

  Future<void> _verify() => _run(() async {
        final r = await ref.read(apiProvider).verifyOtp(
              phone.text.trim(),
              code.text.trim(),
              name: name.text.trim().isEmpty ? null : name.text.trim(),
            );
        await ref.read(appProvider.notifier).signedIn(r);
        if (widget.reauth && mounted) Navigator.of(context).pop();
      });

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Text('NEURO-SATHI', style: text.displaySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            Text(s.t('tagline'), style: text.titleLarge),
            const SizedBox(height: 32),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 18)),
              ),
            ...switch (step) {
              _Step.language => _languageStep(s),
              _Step.phone => _phoneStep(s),
              _Step.code => _codeStep(s),
            },
          ],
        ),
      ),
    );
  }

  /// Each language is shown in its own script, with its English name underneath.
  List<Widget> _languageStep(Strings s) {
    final languages = ref.read(appProvider).catalog.visible;
    return [
      for (final p in languages)
        Text(p.strings['choose_language'] ?? 'Choose your language', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 24),
      for (final p in languages) ...[
        FilledButton(
          onPressed: () async {
            await ref.read(appProvider.notifier).setLanguage(p.code);
            setState(() => step = _Step.phone);
          },
          child: Column(
            children: [
              Text(p.nativeName, style: const TextStyle(fontSize: 28)),
              if (p.nativeName != p.englishName) Text(p.englishName, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  List<Widget> _phoneStep(Strings s) => [
        if (widget.reauth) ...[
          Text(s.t('session_expired'), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 20),
        ],
        Text(s.t('enter_phone'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+]')), LengthLimitingTextInputFormatter(15)],
          style: const TextStyle(fontSize: 28, letterSpacing: 2),
          decoration: const InputDecoration(hintText: '98765 43210', prefixText: '+91 '),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: busy ? null : _sendCode, child: Text(s.t('send_code'))),
        if (widget.reauth) TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.t('later'))),
        const SizedBox(height: 24),
        const TesterTools(signedIn: false), // tester builds only
      ];

  List<Widget> _codeStep(Strings s) => [
        Text(s.t('enter_code'), style: Theme.of(context).textTheme.headlineMedium),
        if (devCode != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Development code: $devCode')),
        const SizedBox(height: 16),
        TextField(
          controller: code,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          style: const TextStyle(fontSize: 32, letterSpacing: 8),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (!widget.reauth)
          TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 22),
          decoration: InputDecoration(labelText: s.t('your_name')),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: busy ? null : _verify, child: Text(s.t('continue'))),
        TextButton(onPressed: () => setState(() => step = _Step.phone), child: Text(s.t('back'))),
      ];
}
