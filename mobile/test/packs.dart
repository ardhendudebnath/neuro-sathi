import 'dart:io';

import 'package:neuro_sathi/l10n/language_pack.dart';

/// Loads a pack straight from content/language-packs (tests run from mobile/).
LanguagePack loadPack(String code) => LanguagePack.parse(File('../content/language-packs/$code.json').readAsStringSync());

List<String> allPackCodes() => Directory('../content/language-packs')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.json'))
    .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
    .toList()
  ..sort();
