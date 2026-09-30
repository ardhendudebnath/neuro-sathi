import 'dart:convert';

import '../data/database.dart';
import 'catalog.dart';
import 'language_pack.dart';

/// A pack downloaded from the server (a newer published version), if it parses.
LanguagePack? parseDownloadedPack(String? json) {
  if (json == null) return null;
  try {
    return LanguagePack.fromJson(jsonDecode(json) as Map<String, dynamic>);
  } on Object {
    return null; // keep using the bundled pack
  }
}

/// The bundled packs, with the user's downloaded pack applied if it is newer.
/// Used by the app at start-up and by the background sync worker.
Future<LanguageCatalog> loadCatalog(AppDb db) async {
  final catalog = await LanguageCatalog.load();
  final downloaded = parseDownloadedPack(await db.getValue('language_pack'));
  return downloaded == null ? catalog : catalog.withDownloaded(downloaded);
}

/// The user's language, falling back to English if its pack is not in [catalog].
Future<String> storedLanguage(AppDb db, LanguageCatalog catalog) async {
  final language = await db.getValue('language') ?? 'en';
  return catalog.packs.containsKey(language) ? language : 'en';
}
