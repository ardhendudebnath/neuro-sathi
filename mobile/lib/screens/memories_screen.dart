import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// The personal memory book: family photos, names and stories added by caregivers.
class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});

  static String describe(MemoryEntry m, String language) {
    final name = m.personName ?? m.title;
    final parts = <String>[
      if (m.relationship != null) (language == 'hi' ? '$name, आपके ${m.relationship}' : '$name, your ${m.relationship}') else name,
      if (m.place != null) m.place!,
      if (m.description != null) m.description!,
    ];
    return parts.join('. ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(appProvider.select((a) => a.language));
    return Scaffold(
      appBar: AppBar(title: Text(s.t('memories'))),
      body: StreamBuilder<List<MemoryEntry>>(
        stream: ref.watch(repoProvider).watchMemories(),
        builder: (context, snap) {
          final items = snap.data ?? const <MemoryEntry>[];
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(s.t('no_memories'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              ),
            );
          }
          return PageView.builder(
            itemCount: items.length,
            controller: PageController(viewportFraction: 0.92),
            itemBuilder: (context, i) {
              final m = items[i];
              final text = describe(m, lang);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 20),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: m.localPhotoPath != null
                            ? Image.file(File(m.localPhotoPath!), fit: BoxFit.cover)
                            : Container(
                                color: Theme.of(context).colorScheme.secondaryContainer,
                                alignment: Alignment.center,
                                child: const Text('📷', style: TextStyle(fontSize: 80)),
                              ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(m.title, style: Theme.of(context).textTheme.headlineMedium)),
                                  SpeakButton(text),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(child: SingleChildScrollView(child: Text(text, style: Theme.of(context).textTheme.bodyLarge))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
