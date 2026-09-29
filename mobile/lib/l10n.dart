/// UI strings. English and Hindi ship with the app; a downloaded language pack
/// (from /content/language-packs/{lang}) overrides or adds strings, so regional
/// NER languages can be added without an app release.
class Strings {
  Strings(this.language, [Map<String, String> pack = const {}]) : _pack = pack;

  final String language;
  final Map<String, String> _pack;

  static const supported = {'en': 'English', 'hi': 'हिन्दी'};

  static const _builtIn = <String, Map<String, String>>{
    'en': {
      'app_name': 'NEURO-SATHI',
      'tagline': 'Your memory companion',
      'greeting_morning': 'Good morning',
      'greeting_afternoon': 'Good afternoon',
      'greeting_evening': 'Good evening',
      'play': 'Play',
      'memories': 'Memories',
      'reminders': 'Reminders',
      'talk_to_sathi': 'Talk to Sathi',
      'settings': 'Settings',
      'done': 'Done',
      'later': 'Later',
      'well_done': 'Well done!',
      'try_again': "Let's try again",
      'not_quite': 'Not quite. The answer was:',
      'next': 'Next',
      'back': 'Back',
      'yes': 'Yes',
      'no': 'No',
      'offline': 'Offline - everything is saved',
      'next_reminder': 'Next',
      'no_more_today': 'Nothing more today',
      'enter_phone': 'Your mobile number',
      'send_code': 'Send code',
      'enter_code': 'Enter the 6-digit code',
      'your_name': 'Your name',
      'continue': 'Continue',
      'choose_language': 'Choose your language',
      'tap_to_speak': 'Tap and speak',
      'listening': 'Listening…',
      'type_instead': 'Or type your question',
      'ask': 'Ask',
      'remember_these': 'Remember these',
      'ready': "I'm ready",
      'which_seen': 'Which one did you see?',
      'who_is_this': 'Who is this?',
      'odd_one_out': 'Which one is different?',
      'what_comes_next': 'What comes next?',
      'what_is_this': 'What is this?',
      'tap_when_you_see': 'Tap the button when you see',
      'tap': 'Tap!',
      'finished': 'All done!',
      'score': 'You got {correct} of {total}',
      'suggested_for_you': 'Suggested for you',
      'no_memories': 'Your family can add photos and names from their phone.',
      'link_caregiver': 'Link a caregiver',
      'link_code_help': 'Read this code to your family member or health worker. It works for 24 hours.',
      'voice_consent': 'Allow cloud voice',
      'voice_consent_help': 'Better speech recognition by sending your voice to our server. Off by default.',
      'text_size': 'Text size',
      'sign_out': 'Sign out',
      'mark_done': 'Mark as done',
      'medicine_time': 'Time for your medicine',
      'reminder': 'Reminder',
    },
    'hi': {
      'app_name': 'न्यूरो-साथी',
      'tagline': 'आपका याद साथी',
      'greeting_morning': 'सुप्रभात',
      'greeting_afternoon': 'नमस्कार',
      'greeting_evening': 'शुभ संध्या',
      'play': 'खेलें',
      'memories': 'यादें',
      'reminders': 'याद दिलाना',
      'talk_to_sathi': 'साथी से बात करें',
      'settings': 'सेटिंग्स',
      'done': 'हो गया',
      'later': 'बाद में',
      'well_done': 'बहुत बढ़िया!',
      'try_again': 'फिर से कोशिश करें',
      'not_quite': 'सही उत्तर था:',
      'next': 'आगे',
      'back': 'पीछे',
      'yes': 'हाँ',
      'no': 'नहीं',
      'offline': 'ऑफ़लाइन - सब कुछ सुरक्षित है',
      'next_reminder': 'अगला',
      'no_more_today': 'आज और कुछ नहीं',
      'enter_phone': 'आपका मोबाइल नंबर',
      'send_code': 'कोड भेजें',
      'enter_code': '6 अंकों का कोड डालें',
      'your_name': 'आपका नाम',
      'continue': 'आगे बढ़ें',
      'choose_language': 'अपनी भाषा चुनें',
      'tap_to_speak': 'दबाएँ और बोलें',
      'listening': 'सुन रहा हूँ…',
      'type_instead': 'या अपना सवाल लिखें',
      'ask': 'पूछें',
      'remember_these': 'इन्हें याद रखें',
      'ready': 'मैं तैयार हूँ',
      'which_seen': 'आपने इनमें से कौन सा देखा?',
      'who_is_this': 'यह कौन है?',
      'odd_one_out': 'कौन सा अलग है?',
      'what_comes_next': 'आगे क्या आएगा?',
      'what_is_this': 'यह क्या है?',
      'tap_when_you_see': 'जब यह दिखे तब दबाएँ',
      'tap': 'दबाएँ!',
      'finished': 'पूरा हुआ!',
      'score': '{total} में से {correct} सही',
      'suggested_for_you': 'आपके लिए',
      'no_memories': 'आपका परिवार अपने फ़ोन से फ़ोटो और नाम जोड़ सकता है।',
      'link_caregiver': 'देखभाल करने वाले को जोड़ें',
      'link_code_help': 'यह कोड अपने परिवार के सदस्य या स्वास्थ्य कार्यकर्ता को बताएँ। यह 24 घंटे चलेगा।',
      'voice_consent': 'क्लाउड आवाज़ की अनुमति',
      'voice_consent_help': 'बेहतर पहचान के लिए आपकी आवाज़ हमारे सर्वर पर भेजी जाएगी। शुरू में बंद।',
      'text_size': 'अक्षर का आकार',
      'sign_out': 'साइन आउट',
      'mark_done': 'हो गया',
      'medicine_time': 'दवा का समय',
      'reminder': 'याद दिलाना',
    },
  };

  String t(String key, [Map<String, Object> args = const {}]) {
    var s = _pack[key] ?? _builtIn[language]?[key] ?? _builtIn['en']![key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  String greeting(DateTime now) {
    if (now.hour < 12) return t('greeting_morning');
    if (now.hour < 17) return t('greeting_afternoon');
    return t('greeting_evening');
  }

  static const _days = {
    'en': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    'hi': ['सोमवार', 'मंगलवार', 'बुधवार', 'गुरुवार', 'शुक्रवार', 'शनिवार', 'रविवार'],
  };

  /// [weekday] is 0 = Monday, matching the backend.
  String dayName(int weekday) => (_days[language] ?? _days['en']!)[weekday];
}
