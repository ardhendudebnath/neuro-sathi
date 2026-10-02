import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../l10n.dart';
import '../services/background_sync.dart';
import '../state/app_state.dart';

/// What sign-in shows when the server cannot be reached. Tester builds name the
/// address they tried, because a fresh install points at the Android emulator's.
String unreachableMessage(Strings s, String server, {bool tester = AppConfig.testerBuild}) {
  if (!tester) return s.t('error_no_internet');
  final emulator = Uri.tryParse(server)?.host == '10.0.2.2' ? ' That address only works in the Android emulator.' : '';
  return 'Cannot reach the server at $server.$emulator Check the address in the Tester build box.';
}

/// Only in tester builds (--dart-define=TESTER_BUILD=true, the APK that CI
/// publishes). English only on purpose: this is for testers, not for users.
/// See docs/testing-on-a-phone.md.
class TesterTools extends ConsumerStatefulWidget {
  const TesterTools({super.key, this.signedIn = true});

  /// The background-sync button needs an account; the server setting does not.
  final bool signedIn;

  @override
  ConsumerState<TesterTools> createState() => _TesterToolsState();
}

class _TesterToolsState extends ConsumerState<TesterTools> {
  @override
  Widget build(BuildContext context) {
    if (!AppConfig.testerBuild) return const SizedBox.shrink();
    final server = ref.read(appProvider.notifier).serverUrl;
    return Card(
      elevation: 0,
      color: const Color(0xFFFFF4D6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tester build', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Server: $server'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _changeServer, child: const Text('Change server')),
            if (widget.signedIn) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _syncSoon, child: const Text('Background sync in 1 minute')),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _changeServer() async {
    var value = ref.read(appProvider.notifier).serverUrl;
    final input = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Server address'),
        content: TextFormField(
          initialValue: value,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'http://192.168.1.5:8000'),
          onChanged: (v) => value = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialog).pop(value), child: const Text('Save')),
        ],
      ),
    );
    if (input == null) return;
    final ok = await ref.read(appProvider.notifier).setServer(input);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Server saved' : 'That is not a usable address')));
  }

  Future<void> _syncSoon() async {
    await BackgroundSync.runSoon();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scheduled. Close the app now: the background job runs in about a minute.')),
    );
  }
}
