import 'dart:convert';

import 'package:flutter/services.dart';

import 'language_pack.dart';

/// All language packs bundled with the app (assets/lang, generated from
/// content/language-packs by tool/sync_language_packs.py), plus a newer
/// downloaded version of the user's pack when the server has one.
class LanguageCatalog {
  const LanguageCatalog(this.packs);

  /// Build with --dart-define=SHOW_PREVIEW_LANGUAGES=true to let reviewers try
  /// packs that have not been reviewed yet. Normal builds show public packs only.
  static const showPreview = bool.fromEnvironment('SHOW_PREVIEW_LANGUAGES');

  static const none = LanguageCatalog({});

  final Map<String, LanguagePack> packs;

  static Future<LanguageCatalog> load([AssetBundle? bundle]) async {
    final assets = bundle ?? rootBundle;
    final index = (jsonDecode(await assets.loadString('assets/lang/index.json')) as List<dynamic>).cast<String>();
    return LanguageCatalog({
      for (final code in index) code: LanguagePack.parse(await assets.loadString('assets/lang/$code.json')),
    });
  }

  LanguagePack get english => packs['en'] ?? LanguagePack.empty();

  LanguagePack pack(String code) => packs[code] ?? english;

  /// Languages offered to the user: English first, then by English name.
  List<LanguagePack> get visible {
    final list = packs.values.where((p) => p.isPublic || showPreview).toList()
      ..sort((a, b) => a.code == 'en' ? -1 : b.code == 'en' ? 1 : a.englishName.compareTo(b.englishName));
    return list;
  }

  /// Uses [downloaded] in place of the bundled pack if it is a newer version.
  LanguageCatalog withDownloaded(LanguagePack downloaded) {
    final bundled = packs[downloaded.code];
    if (bundled != null && bundled.version >= downloaded.version) return this;
    return LanguageCatalog({...packs, downloaded.code: downloaded});
  }
}
