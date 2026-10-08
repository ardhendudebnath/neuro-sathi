import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/games/trials.dart';
import 'package:neuro_sathi/l10n.dart';

import 'packs.dart';

void main() {
  final en = loadPack('en');

  test('every pack parses and covers every English string', () {
    for (final code in allPackCodes()) {
      final pack = loadPack(code);
      expect(pack.code, code);
      expect(en.strings.keys.toSet().difference(pack.strings.keys.toSet()), isEmpty, reason: code);
      expect(pack.days, hasLength(7), reason: code);
      expect(pack.routine, hasLength(en.routine.length), reason: code);
    }
  });

  test('regional drafts are hidden from normal builds', () {
    final catalog = LanguageCatalog({for (final c in allPackCodes()) c: loadPack(c)});
    final visible = catalog.visible.map((p) => p.code).toList();
    expect(visible.first, 'en');
    expect(visible, isNot(contains('as')));
    expect(visible, isNot(contains('bn')));
    expect(visible, isNot(contains('ne')));
    expect(visible, isNot(contains('mni-Beng')));
    expect(visible, isNot(contains('mni-Mtei')));
    expect(visible, isNot(contains('brx')));
  });

  test("time uses each language's day-parts and digits", () {
    expect(en.formatTime(20, 0), '8:00 PM');
    expect(loadPack('hi').formatTime(20, 0), 'रात 8:00');
    expect(loadPack('as').formatTime(20, 0), 'ৰাতি ৮:০০');
    expect(loadPack('bn').formatTime(7, 30), 'সকাল ৭:৩০');
    expect(loadPack('ne').formatTime(10, 0), 'बिहान १०:००');
    expect(loadPack('mni-Beng').formatTime(20, 0), 'অহিং ৮:০০');
    expect(loadPack('mni-Mtei').formatTime(20, 0), 'ꯑꯍꯤꯡ ꯸:꯰꯰');
    expect(loadPack('brx').formatTime(20, 0), 'हर नि 8:00');
  });

  test('numbers in messages use the pack digits; missing keys fall back to English', () {
    final bengali = Strings(loadPack('bn'), en);
    expect(bengali.t('score', {'correct': 3, 'total': 8}), '৮টির মধ্যে ৩টি ঠিক');
    expect(bengali.t('no_such_key'), 'no_such_key');
    expect(Strings(en).t('score', {'correct': 3, 'total': 8}), 'You got 3 of 8');
  });

  test('a newer downloaded pack replaces the bundled one, an older one does not', () {
    final catalog = LanguageCatalog({'en': en, 'hi': loadPack('hi')});
    final newer = LanguagePack.parse(
      '{"language":"hi","version":9,"meta":{"english_name":"Hindi","native_name":"हिन्दी","script":"Deva",'
      '"release":"public","review":{"status":"reviewed","reviewers":["x"]},"tts_locales":[],"stt_locales":[],"llm":true},'
      '"strings":{"play":"खेलो"},"voice_prompts":{},"days":[],"time":{"format":"{h}:{mm} {period}","periods":[]},'
      '"regions":{},"sathi":{"answers":{},"keywords":{}},"games":{"names":{},"foods":[],"routine":[],"objects":[]}}',
    );
    expect(catalog.withDownloaded(newer).pack('hi').strings['play'], 'खेलो');
    expect(LanguageCatalog({'hi': newer}).withDownloaded(loadPack('hi')).pack('hi').version, 9);
  });

  test('keywords: prefixes take suffixes, plain keywords need whole words', () {
    final bengali = loadPack('bn');
    expect(hasIntent('ওষুধটা কখন খাব?', bengali, en, 'medicine'), isTrue);
    expect(hasIntent('আজকে কী আছে?', bengali, en, 'schedule'), isTrue);
    expect(hasIntent('আজকে কী আছে?', bengali, en, 'who'), isFalse);
    // Precomposed and decomposed forms of য় are the same word.
    expect(hasIntent('সময়', loadPack('as'), en, 'time'), isTrue);
    expect(hasIntent('সময়', loadPack('as'), en, 'time'), isTrue);
  });

  test('the Meitei Mayek full stop ꯫ ends a word', () {
    expect(tokenize('ꯉꯁꯤ ꯀꯔꯤ ꯅꯨꯃꯤꯠꯅꯣ꯫'), ['ꯉꯁꯤ', 'ꯀꯔꯤ', 'ꯅꯨꯃꯤꯠꯅꯣ']);
  });

  test('games draw words and routines from the pack', () {
    final assamese = loadPack('as');
    final content = GameContent(foods: assamese.foods, routine: assamese.routine);
    for (final t in myDay(content, 3, Random(1))) {
      expect(assamese.routine, contains(t.options[t.answer]));
    }
    final market = marketList(content, 2, Random(1));
    expect(assamese.foods, containsAll(market.first.memorize!));
  });
}
