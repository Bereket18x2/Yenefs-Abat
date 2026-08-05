import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

const String googleApiKey = 'AIzaSyA-X9y5ouviMuzRZ0xGIrKpst5m0XpF2F8';

// ── EmailJS (free) — for sending real verification codes by email ──
// Create a free account at https://www.emailjs.com then fill these in:
const String emailjsServiceId = 'service_b0dal6k';
const String emailjsTemplateId = 'template_2wygczm';
const String emailjsPublicKey = 'f3q9dbEr5J5aicm4M';

Future<bool> sendEmailCode(String toEmail, String code, String purpose) async {
  if (emailjsServiceId.isEmpty || emailjsTemplateId.isEmpty || emailjsPublicKey.isEmpty) {
    return false; // not configured yet → caller falls back to on-screen code
  }
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    final req = await client.postUrl(Uri.parse('https://api.emailjs.com/api/v1.0/email/send'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'service_id': emailjsServiceId,
      'template_id': emailjsTemplateId,
      'user_id': emailjsPublicKey,
      'template_params': {
        'to_email': toEmail,
        'code': code,
        'purpose': purpose,
      },
    }));
    final resp = await req.close();
    final respBody = await resp.transform(const Utf8Decoder()).join();
    client.close();
    debugPrint('EMAILJS status: ${resp.statusCode} body: $respBody');
    lastEmailError = resp.statusCode == 200 ? '' : ('EmailJS ${resp.statusCode}: $respBody');
    return resp.statusCode == 200;
  } catch (e) {
    debugPrint('EMAILJS exception: $e');
    lastEmailError = 'Network error: $e';
    return false;
  }
}

String lastEmailError = '';


// ═══════════════════════════════════════════════
// NOTIFICATIONS
// ═══════════════════════════════════════════════

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

final ValueNotifier<double> fontSizeNotifier = ValueNotifier<double>(1.0);

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();
  // Set local timezone based on device's UTC offset
  final offset = DateTime.now().timeZoneOffset;
  final offsetHours = offset.inHours;
  try {
    if (offsetHours == 3) {
      tz.setLocalLocation(tz.getLocation('Africa/Addis_Ababa'));
    } else {
      // Fallback: find any timezone matching the current UTC offset
      final now = DateTime.now();
      tz.Location? match;
      for (final locName in tz.timeZoneDatabase.locations.keys) {
        final loc = tz.timeZoneDatabase.locations[locName]!;
        final tzNow = tz.TZDateTime.from(now.toUtc(), loc);
        if (tzNow.timeZoneOffset == offset) { match = loc; break; }
      }
      tz.setLocalLocation(match ?? tz.getLocation('Africa/Addis_Ababa'));
    }
  } catch (e) {
    tz.setLocalLocation(tz.getLocation('UTC'));
  }
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings settings =
      InitializationSettings(android: androidSettings);
  await notificationsPlugin.initialize(settings);
  final androidImpl = notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();
  await androidImpl?.requestExactAlarmsPermission();
}

Future<void> schedulePrayerNotification(int id, int hour, int minute, String label) async {
  await notificationsPlugin.cancel(id);

  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'prayer_channel', 'Prayer Reminders',
    channelDescription: 'Daily prayer time reminders',
    importance: Importance.max, priority: Priority.high,
    sound: const RawResourceAndroidNotificationSound('church_bell'),
    playSound: true,
    enableVibration: true,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
  );

  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }

  await notificationsPlugin.zonedSchedule(
    id,
    '🕯 $label',
    'It is time for your prayer — ጸሎት ጊዜ ነው',
    scheduled,
    NotificationDetails(android: androidDetails),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

Future<void> cancelNotification(int id) async =>
    await notificationsPlugin.cancel(id);

Future<void> showConfessionNotification() async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'confession_channel', 'Confession Reminder',
    channelDescription: 'Monthly confession reminder',
    importance: Importance.max, priority: Priority.high,
    sound: RawResourceAndroidNotificationSound('church_bell'), playSound: true,
  );
  await notificationsPlugin.show(999, '⛪ Confession Reminder',
      '30 days have passed. It is time to confess — ኑዛዜ ጊዜ ነው',
      const NotificationDetails(android: androidDetails));
}

// ═══════════════════════════════════════════════
// ETHIOPIAN CALENDAR
// ═══════════════════════════════════════════════

class EthiopianCalendar {
  static const List<String> months = [
    'Meskerem','Tikimt','Hidar','Tahisas','Tir','Yekatit',
    'Megabit','Miazia','Ginbot','Sene','Hamle','Nehase','Pagume',
  ];
  static const List<String> monthsAmharic = [
    'መስከረም','ጥቅምት','ህዳር','ታህሳስ','ጥር','የካቲት',
    'መጋቢት','ሚያዚያ','ግንቦት','ሰኔ','ሐምሌ','ነሐሴ','ጳጉሜ',
  ];
  static const List<String> zemeneNames = [
    'Zemene Yohannes','Zemene Matewos','Zemene Markos','Zemene Lukas',
  ];
  static const List<String> zemeneNamesAmharic = [
    'ዘመነ ዮሐንስ','ዘመነ ማቴዎስ','ዘመነ ማርቆስ','ዘመነ ሉቃስ',
  ];
  static bool isLeapYear(int y) => y % 4 == 3;
  static String getZemene(int y, {bool amharic = false}) =>
      amharic ? zemeneNamesAmharic[y % 4] : zemeneNames[y % 4];
  static int daysInMonth(int m, int y) => m == 13 ? (isLeapYear(y) ? 6 : 5) : 30;
  static int daysInYear(int y) => isLeapYear(y) ? 366 : 365;
  static int dayOfYear(int d, int m, int y) {
    int t = 0;
    for (int i = 1; i < m; i++) {
      t += daysInMonth(i, y);
    }
    return t + d;
  }
  static EthiopianDate fromGregorian(DateTime g) {
    final bool gL = (g.year % 4 == 0 && g.year % 100 != 0) || g.year % 400 == 0;
    final int nyD = gL ? 12 : 11;
    int eY = (g.month > 9 || (g.month == 9 && g.day >= nyD)) ? g.year - 7 : g.year - 8;
    final int nyGY = eY + 7;
    final bool nyGL = (nyGY % 4 == 0 && nyGY % 100 != 0) || nyGY % 400 == 0;
    final DateTime ethNY = DateTime(nyGY, 9, nyGL ? 12 : 11);
    final int diff = g.difference(ethNY).inDays;
    int eM = (diff ~/ 30) + 1;
    int eD = (diff % 30) + 1;
    if (eM > 13) { eM = 13; eD = diff - 360 + 1; }
    return EthiopianDate(day: eD, month: eM, year: eY);
  }
  static DateTime toGregorian(int d, int m, int y) {
    final int gY = y + 7;
    final bool gL = (gY % 4 == 0 && gY % 100 != 0) || gY % 400 == 0;
    final DateTime ethNY = DateTime(gY, 9, gL ? 12 : 11);
    return ethNY.add(Duration(days: (m - 1) * 30 + (d - 1)));
  }
  static EthiopianDate today() => fromGregorian(DateTime.now());
}

class EthiopianDate {
  final int day, month, year;
  const EthiopianDate({required this.day, required this.month, required this.year});
  String get monthName => EthiopianCalendar.months[month - 1];
  String get monthNameAmharic => EthiopianCalendar.monthsAmharic[month - 1];
  String get zemene => EthiopianCalendar.getZemene(year);
  bool get isLeapYear => EthiopianCalendar.isLeapYear(year);
  int get dayOfYear => EthiopianCalendar.dayOfYear(day, month, year);
  int get totalDaysInYear => EthiopianCalendar.daysInYear(year);
}

// ═══════════════════════════════════════════════
// USER MODEL
// ═══════════════════════════════════════════════

class UserProfile {
  final String name;
  final String contact;
  final int age;
  final String gender;
  final String role;
  final String password;
  final bool verified;
  UserProfile({
    required this.name, required this.contact,
    required this.age, required this.gender, required this.role,
    this.password = '', this.verified = false,
  });
  Map<String, dynamic> toJson() => {
    'name': name, 'contact': contact, 'age': age, 'gender': gender,
    'role': role, 'password': password, 'verified': verified,
  };
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    name: j['name'] ?? '', contact: j['contact'] ?? '',
    age: j['age'] ?? 0, gender: j['gender'] ?? '', role: j['role'] ?? '',
    password: j['password'] ?? '', verified: j['verified'] ?? false,
  );
}

// ═══════════════════════════════════════════════
// SINS DATA
// ═══════════════════════════════════════════════

class Sin {
  final String english;
  final String amharic;
  Sin(this.english, this.amharic);
}

final List<Sin> sins = [
  Sin('Fornication / Sexual immorality', 'ዝሙት'),
  Sin('Adultery', 'ምንዝርና'),
  Sin('Homosexuality', 'ግብረ ሰዶም'),
  Sin('Masturbation', 'ራስን ማርከስ'),
  Sin('Drunkenness', 'ስካር'),
  Sin('Drug use', 'የዕፅ አጠቃቀም'),
  Sin('Gluttony', 'የምግብ ስስት'),
  Sin('Pride and arrogance', 'ትዕቢትና እብሪት'),
  Sin('Murder', 'ነፍስ መግደል'),
  Sin('Theft', 'መስረቅ'),
  Sin('Lying / False testimony', 'ውሸት መናገር'),
  Sin('Envy and jealousy', 'ቅናትና ምቀኝነት'),
  Sin('Slander and gossip', 'ስም ማጥፋትና ሐሜት'),
  Sin('Hatred', 'ጥላቻ'),
  Sin('Dishonoring parents', 'ወላጆችን አለማክበር'),
  Sin('Oppressing the poor', 'ድሆችን መጨቆን'),
  Sin('Bribery', 'ጉቦ መቀበልና መስጠት'),
  Sin('Anger and wrath', 'ቁጣና ጠበኝነት'),
  Sin('Despair of God\'s mercy', 'የእግዚአብሔርን ምህረት መተው'),
  Sin('Not repenting after sinning', 'ከኃጢአት በኋላ አለመጸጸት'),
  Sin('Neglecting prayer', 'ጸሎትን መተው'),
  Sin('Breaking fasting days', 'ጾምን መስበር'),
  Sin('Not attending church', 'ቤተክርስቲያን አለመሄድ'),
  Sin('Witchcraft and sorcery', 'ጥንቆላና ድግምት'),
  Sin('Usury / Charging interest', 'ወለድ መጠቀም'),
  Sin('Receiving Communion unworthily', 'ሳይዘጋጁ ቁርባን መቀበል'),
  Sin('Greed', 'ስስት'),
  Sin('Sloth in spiritual life', 'በሃይማኖት ሕይወት መስነፍ'),
];

// ═══════════════════════════════════════════════
// PENANCE DATA
// ═══════════════════════════════════════════════

class PenanceType {
  final String name;
  final String amharic;
  final String icon;
  PenanceType(this.name, this.amharic, this.icon);
}

final List<PenanceType> penanceTypes = [
  PenanceType('Segdet (Prostrations)', 'ስግደት', '🙇'),
  PenanceType('Fasting', 'ጾም', '🕊'),
  PenanceType('Reading Psalms (Dawit)', 'መዝሙረ ዳዊት ማንበብ', '📖'),
  PenanceType('Reading Prayers', 'ጸሎት ማንበብ', '🙏'),
  PenanceType('Attending Liturgy (Qidase)', 'ቅዳሴ መካፈል', '⛪'),
  PenanceType('Almsgiving', 'ምጽዋት መስጠት', '🤲'),
  PenanceType('Pilgrimage', 'ጉዞ ወደ ቅዱስ ቦታ', '🚶'),
  PenanceType('Abstinence from meat', 'ከስጋ መታቀብ', '🥬'),
  PenanceType('Night Vigil Prayer', 'የሌሊት ጸሎት', '🌙'),
  PenanceType('Reciting Wudase Mariam', 'ውዳሴ ማርያም ማንበብ', '✝️'),
];

class PenanceItem {
  String type;
  String amharic;
  String icon;
  int totalCount;
  int completedCount;
  String frequency;
  bool finished;
  PenanceItem({
    required this.type, required this.amharic, required this.icon,
    required this.totalCount, required this.completedCount,
    required this.frequency, this.finished = false,
  });
  Map<String, dynamic> toJson() => {
    'type': type, 'amharic': amharic, 'icon': icon,
    'totalCount': totalCount, 'completedCount': completedCount,
    'frequency': frequency, 'finished': finished,
  };
  factory PenanceItem.fromJson(Map<String, dynamic> j) => PenanceItem(
    type: j['type'], amharic: j['amharic'], icon: j['icon'],
    totalCount: j['totalCount'], completedCount: j['completedCount'],
    frequency: j['frequency'], finished: j['finished'] ?? false,
  );
}

// ═══════════════════════════════════════════════
// THEME
// ═══════════════════════════════════════════════

class AppColors {
  final bool dark;
  const AppColors(this.dark);
  Color get gold => dark ? const Color(0xFFC4A55A) : const Color(0xFFC9A84C);
  Color get bg => dark ? const Color(0xFF0F0505) : const Color(0xFFFAF8F4);
  Color get card => dark ? const Color(0xFF1E0A0A) : const Color(0xFFFFFFFF);
  Color get hero => dark ? const Color(0xFF1A0808) : const Color(0xFFFFFFFF);
  Color get border => dark ? const Color(0xFF3A1A1A) : const Color(0xFFE8DDD0);
  Color get text => dark ? const Color(0xFFE8D5A0) : const Color(0xFF2C1810);
  Color get muted => dark ? const Color(0xFF8A6A4A) : const Color(0xFFA09080);
  Color get label => dark ? const Color(0xFF6A4A2A) : const Color(0xFFB0A090);
  Color get strip => dark ? const Color(0xFF2A1010) : const Color(0xFFF0EBE0);
  Color get goldBg => dark ? const Color(0xFF2A1010) : const Color(0xFFFDF6E8);
  Color get green => const Color(0xFF4CAF50);
  Color get red => const Color(0xFFE57373);
}

// ═══════════════════════════════════════════════
// APP
// ═══════════════════════════════════════════════

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }
  await initNotifications();
  runApp(const YenefsAbatApp());
}

class YenefsAbatApp extends StatefulWidget {
  const YenefsAbatApp({super.key});
  @override
  State<YenefsAbatApp> createState() => _YenefsAbatAppState();
}

class _YenefsAbatAppState extends State<YenefsAbatApp> {
  bool _isDark = false;
  bool _profileLoaded = false;
  UserProfile? _profile;
  bool _needsLogin = false;
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // Onboarding is tracked per-account (per Firebase uid), not per-device —
  // otherwise, once any account dismisses the tour, a brand new account
  // signing up on the same phone would never see it.
  Future<bool> _tourNotSeenBy(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('onboarding_done_$uid') ?? false);
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    fontSizeNotifier.value = prefs.getDouble('font_size') ?? 1.0;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Reload to get latest emailVerified status
        await user.reload();
        final fresh = FirebaseAuth.instance.currentUser;
        if (fresh != null && !fresh.emailVerified) {
          // Not verified → do not grant access
          setState(() { _profileLoaded = true; _needsLogin = true; _profile = null; });
          return;
        }
        final doc = await FirebaseFirestore.instance.collection('users').doc(fresh!.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          final showTour = await _tourNotSeenBy(fresh.uid);
          setState(() {
            _profile = UserProfile(
              name: data['name'] ?? '',
              contact: fresh.email ?? data['contact'] ?? '',
              age: data['age'] ?? 0,
              gender: data['gender'] ?? '',
              role: data['role'] ?? '',
              password: '',
              verified: fresh.emailVerified,
            );
            _needsLogin = false;
            _showOnboarding = showTour;
            _profileLoaded = true;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('loadProfile error: $e');
    }
    setState(() { _profileLoaded = true; _needsLogin = false; _profile = null; });
  }

  void _onProfileSaved(UserProfile p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final showTour = uid != null && await _tourNotSeenBy(uid);
    setState(() { _profile = p; _needsLogin = false; _showOnboarding = showTour; });
  }

  Future<void> _finishOnboarding() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_done_$uid', true);
    }
    setState(() => _showOnboarding = false);
  }

  void _toggleTheme() => setState(() => _isDark = !_isDark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yenefs Abat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFAF8F4),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC9A84C)),
        useMaterial3: true,
        fontFamily: 'NotoSansEthiopic',
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0505),
        colorScheme: const ColorScheme.dark(primary: Color(0xFFC4A55A)),
      ),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: !_profileLoaded
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _showOnboarding
              ? OnboardingScreen(isDark: _isDark, onFinish: _finishOnboarding)
              : _profile == null || _needsLogin
                  ? SignInScreen(onSaved: _onProfileSaved, isDark: _isDark)
                  : MainScreen(isDark: _isDark, onToggleTheme: _toggleTheme, profile: _profile!),
      builder: (context, child) => ValueListenableBuilder<double>(
        valueListenable: fontSizeNotifier,
        builder: (context, scale, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// SIGN IN SCREEN
// ═══════════════════════════════════════════════

// ═══════════════════════════════════════════════
// AUTH SCREENS
// ═══════════════════════════════════════════════

class SignInScreen extends StatefulWidget {
  final Function(UserProfile) onSaved;
  final bool isDark;
  const SignInScreen({super.key, required this.onSaved, required this.isDark});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  // 0 = login, 1 = register step1, 2 = verify
  int _step = 0;
  final _loginContactCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  bool _loginPassVisible = false;

  // Register fields
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String _gender = '';
  String _role = '';
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _passVisible = false;
  bool _confirmPassVisible = false;
  final _forgotContactCtrl = TextEditingController();

  // Verification
  final _verifyCtrl = TextEditingController();
  UserProfile? _pendingProfile;

  final List<Map<String, String>> _roles = [
    {'en': 'Memen (Believer)', 'am': 'ምዕመን'},
    {'en': 'Deacon', 'am': 'ዲያቆን'},
    {'en': 'Priest', 'am': 'ካህን'},
    {'en': 'Sunday School Student', 'am': 'የሰንበት ትምህርት ቤት ተማሪ'},
    {'en': 'Zemari (Singer)', 'am': 'ዘማሪ'},
    {'en': 'Mergeta (Scholar)', 'am': 'መርጌታ'},
    {'en': 'Teacher', 'am': 'አስተማሪ'},
  ];

  @override
  void dispose() {
    _loginContactCtrl.dispose(); _loginPassCtrl.dispose();
    _nameCtrl.dispose(); _contactCtrl.dispose(); _ageCtrl.dispose();
    _passCtrl.dispose(); _confirmPassCtrl.dispose(); _verifyCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.red.shade800,
      duration: const Duration(seconds: 3),
    ));
  }

  bool _loading = false;

  Future<void> _tryLogin() async {
    final email = _loginContactCtrl.text.trim();
    final pass = _loginPassCtrl.text.trim();

    if (email.isEmpty) { _showError('Please enter your email'); return; }
    if (!email.contains('@')) { _showError('Please sign in with your email address'); return; }
    if (pass.isEmpty) { _showError('Please enter your password'); return; }

    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      final user = cred.user!;
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      if (!user.emailVerified) {
        // Block access until verified — resend link and route to verify screen
        await user.sendEmailVerification();
        _pendingProfile = UserProfile(
          name: data['name'] ?? '', contact: user.email ?? email,
          age: data['age'] ?? 0, gender: data['gender'] ?? '',
          role: data['role'] ?? '', password: '', verified: false,
        );
        _contactCtrl.text = user.email ?? email;
        if (!mounted) return;
        setState(() { _loading = false; _step = 2; });
        _showError('Please verify your email first. We sent you a new link.');
        return;
      }
      final profile = UserProfile(
        name: data['name'] ?? '',
        contact: user.email ?? email,
        age: data['age'] ?? 0,
        gender: data['gender'] ?? '',
        role: data['role'] ?? '',
        password: '',
        verified: true,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSaved(profile);
    } on FirebaseAuthException catch (e) {
      setState(() => _loading = false);
      String msg;
      switch (e.code) {
        case 'user-not-found': msg = 'No account found with that email. Please register first.'; break;
        case 'wrong-password':
        case 'invalid-credential': msg = 'Incorrect email or password. Tap "Forgot password?" to reset.'; break;
        case 'invalid-email': msg = 'That email address is not valid.'; break;
        case 'user-disabled': msg = 'This account has been disabled.'; break;
        case 'too-many-requests': msg = 'Too many attempts. Please wait a moment and try again.'; break;
        case 'network-request-failed': msg = 'No internet connection. Please check your network.'; break;
        default: msg = 'Sign in failed: ${e.message ?? e.code}';
      }
      _showError(msg);
    } catch (e) {
      setState(() => _loading = false);
      _showError('Something went wrong. Please try again.');
    }
  }

  void _goToRegister() {
    setState(() => _step = 1);
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }

  bool _isValidPhone(String phone) {
    final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
    return phoneRegex.hasMatch(phone.replaceAll(' ', '').replaceAll('-', ''));
  }

  bool _isValidContact(String contact) {
    return _isValidEmail(contact) || _isValidPhone(contact);
  }

  Future<void> _submitRegister() async {
    final name = _nameCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    final age = _ageCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final confirm = _confirmPassCtrl.text.trim();

    if (name.isEmpty) { _showError('Please enter your full name'); return; }
    if (name.length < 2) { _showError('Name must be at least 2 characters'); return; }
    if (contact.isEmpty) { _showError('Please enter your phone number or email'); return; }
    if (!_isValidContact(contact)) {
      if (contact.contains('@')) {
        _showError('Invalid email format. Example: name@gmail.com');
      } else {
        _showError('Invalid phone number. Use format: +251912345678 or 0912345678');
      }
      return;
    }
    if (age.isNotEmpty && (int.tryParse(age) == null || int.parse(age) < 5 || int.parse(age) > 120)) {
      _showError('Please enter a valid age (5-120)'); return;
    }
    if (_gender.isEmpty) { _showError('Please select your gender'); return; }
    if (_role.isEmpty) { _showError('Please select your church role'); return; }
    if (pass.isEmpty) { _showError('Please enter a password'); return; }
    if (pass.length < 6) { _showError('Password must be at least 6 characters'); return; }
    if (!RegExp(r'[A-Za-z]').hasMatch(pass) && !RegExp(r'[0-9]').hasMatch(pass)) {
      _showError('Password must contain letters and numbers'); return;
    }
    if (confirm.isEmpty) { _showError('Please confirm your password'); return; }
    if (pass != confirm) { _showError('Passwords do not match. Please re-enter'); return; }

    if (!contact.contains('@')) {
      _showError('Please register with an email address so we can secure and recover your account.');
      return;
    }

    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: contact, password: pass);
      final user = cred.user!;
      // Save profile in Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'contact': contact,
        'age': int.tryParse(age) ?? 0,
        'gender': _gender,
        'role': _role,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Send Firebase's official verification LINK (from Google servers — less Spam)
      await user.sendEmailVerification();
      _pendingProfile = UserProfile(
        name: name, contact: contact, age: int.tryParse(age) ?? 0,
        gender: _gender, role: _role, password: '', verified: false,
      );
      if (!mounted) return;
      setState(() { _loading = false; _step = 2; });
    } on FirebaseAuthException catch (e) {
      setState(() => _loading = false);
      String msg;
      switch (e.code) {
        case 'email-already-in-use': msg = 'An account with this email already exists. Please sign in or reset your password.'; break;
        case 'invalid-email': msg = 'That email address is not valid.'; break;
        case 'weak-password': msg = 'Password is too weak. Use at least 6 characters.'; break;
        case 'network-request-failed': msg = 'No internet connection. Please check your network.'; break;
        default: msg = 'Registration failed: ${e.message ?? e.code}';
      }
      _showError(msg);
    } catch (e) {
      setState(() => _loading = false);
      _showError('Something went wrong. Please try again.');
    }
  }

  Future<void> _submitVerify() async {
    // Firebase-link flow: reload user, check emailVerified
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      setState(() => _loading = false);
      if (fresh != null && fresh.emailVerified) {
        final p = _pendingProfile ?? UserProfile(
          name: '', contact: fresh.email ?? '', age: 0, gender: '', role: '', password: '', verified: true);
        widget.onSaved(UserProfile(
          name: p.name, contact: p.contact, age: p.age,
          gender: p.gender, role: p.role, password: '', verified: true));
      } else {
        _showError('Not verified yet. Open the link in your email (check Spam), then tap this again.');
      }
    } catch (_) {
      setState(() => _loading = false);
      _showError('Something went wrong. Please try again.');
    }
  }

  Future<void> _resendCode() async {
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Verification email sent again. Check your inbox and Spam.'),
        duration: Duration(seconds: 4)));
    } catch (_) {
      setState(() => _loading = false);
      _showError('Could not resend. Please wait a moment and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            // Logo
            Center(child: Column(children: [
              Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.gold.withAlpha(60), blurRadius: 20, spreadRadius: 2)]),
                child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.cover))),
              const SizedBox(height: 14),
              Text('YENEFS_ABAT', style: TextStyle(fontSize: 22, color: c.text, letterSpacing: 0, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('የነፍስ አባት', style: TextStyle(fontSize: 14, color: c.muted, fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
              Container(width: 50, height: 2, color: c.gold),
            ])),
            const SizedBox(height: 28),

            if (_step == 0) _buildLogin(c),
            if (_step == 1) _buildRegister(c),
            if (_step == 2) _buildVerify(c),
            if (_step == 3) _buildForgot(c),
          ]),
        ),
      ),
    );
  }

  Future<void> _submitForgotContact() async {
    final contact = _forgotContactCtrl.text.trim();
    if (contact.isEmpty) { _showError('Please enter your email'); return; }
    if (!contact.contains('@')) { _showError('Enter the email you registered with.'); return; }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: contact);
      if (!mounted) return;
      setState(() => _loading = false);
      showDialog(context: context, builder: (ctx) {
        final cc = AppColors(widget.isDark);
        return AlertDialog(
          backgroundColor: cc.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Check Your Email 📬', style: TextStyle(color: cc.gold, fontWeight: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('We sent a password reset link to:', style: TextStyle(color: cc.muted, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(contact, style: TextStyle(color: cc.text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text('Open the link in your email to set a new password, then come back and sign in. Check Spam too.', style: TextStyle(color: cc.muted, fontSize: 11, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
          ]),
          actions: [
            GestureDetector(
              onTap: () { Navigator.pop(ctx); setState(() => _step = 0); _loginContactCtrl.text = contact; },
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(color: cc.gold, borderRadius: BorderRadius.circular(10)),
                child: Text('Back to Sign In', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700))),
            ),
          ],
        );
      });
    } on FirebaseAuthException catch (e) {
      setState(() => _loading = false);
      if (e.code == 'user-not-found') {
        _showError('No account found with that email.');
      } else {
        _showError('Could not send reset email: ${e.message ?? e.code}');
      }
    } catch (e) {
      setState(() => _loading = false);
      _showError('Something went wrong. Please try again.');
    }
  }

  Widget _buildLogin(AppColors c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Center(child: Text('Welcome Back', style: TextStyle(fontSize: 20, color: c.text, fontWeight: FontWeight.w800))),
    const SizedBox(height: 4),
    Center(child: Text('Sign in to your account', style: TextStyle(fontSize: 13, color: c.muted))),
    const SizedBox(height: 24),
    _label('Phone or Email', 'ስልክ ወይም ኢሜል', c),
    const SizedBox(height: 8),
    _inputField('Enter your phone or email', _loginContactCtrl, c),
    const SizedBox(height: 16),
    _label('Password', 'የይለፍ ቃል', c),
    const SizedBox(height: 8),
    _passwordField('Enter your password', _loginPassCtrl, _loginPassVisible, (v) => setState(() => _loginPassVisible = v), c),
    const SizedBox(height: 28),
    _goldBtn('SIGN IN', () => _tryLogin(), c, loading: _loading),
    const SizedBox(height: 12),
    Center(child: GestureDetector(
      onTap: () { _forgotContactCtrl.text = _loginContactCtrl.text; setState(() => _step = 3); },
      child: Text('Forgot password?', style: TextStyle(color: c.gold, fontSize: 13, fontWeight: FontWeight.w700)),
    )),
    const SizedBox(height: 12),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text("Don't have an account? ", style: TextStyle(color: c.muted, fontSize: 13)),
      GestureDetector(onTap: _goToRegister, child: Text('Register', style: TextStyle(color: c.gold, fontSize: 13, fontWeight: FontWeight.w700))),
    ]),
    const SizedBox(height: 24),
  ]);

  Widget _buildRegister(AppColors c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      GestureDetector(onTap: () => setState(() => _step = 0), child: Icon(Icons.arrow_back_ios, color: c.gold, size: 20)),
      const SizedBox(width: 8),
      Text('Create Account', style: TextStyle(fontSize: 20, color: c.text, fontWeight: FontWeight.w800)),
    ]),
    const SizedBox(height: 4),
    Text('Fill in your details to register', style: TextStyle(fontSize: 13, color: c.muted)),
    const SizedBox(height: 20),
    _label('Full Name *', 'ሙሉ ስም', c), const SizedBox(height: 8),
    _inputField('Enter your full name', _nameCtrl, c),
    const SizedBox(height: 14),
    _label('Phone or Email *', 'ስልክ ወይም ኢሜል', c), const SizedBox(height: 8),
    _inputField('Phone number or email address', _contactCtrl, c),
    const SizedBox(height: 14),
    _label('Age', 'እድሜ', c), const SizedBox(height: 8),
    _inputField('Your age', _ageCtrl, c, isNumber: true),
    const SizedBox(height: 14),
    _label('Gender *', 'ጾታ', c), const SizedBox(height: 8),
    Row(children: ['Male', 'Female'].map((g) => Expanded(child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _gender = g),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: _gender == g ? c.gold : c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _gender == g ? c.gold : c.border, width: 0.5)),
          child: Center(child: Text(g, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _gender == g ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.text))),
        ),
      ),
    ))).toList()),
    const SizedBox(height: 14),
    _label('Church Role *', 'በቤተክርስቲያን ያለዎት ሚና', c), const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: _roles.map((r) => GestureDetector(
      onTap: () => setState(() => _role = r['en']!),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: _role == r['en'] ? c.gold : c.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: _role == r['en'] ? c.gold : c.border, width: 0.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(r['am']!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _role == r['en'] ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.text)),
          Text(r['en']!, style: TextStyle(fontSize: 10, color: _role == r['en'] ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white).withAlpha(180) : c.muted)),
        ]),
      ),
    )).toList()),
    const SizedBox(height: 14),
    _label('Password *', 'የይለፍ ቃል', c), const SizedBox(height: 8),
    _passwordField('At least 6 characters', _passCtrl, _passVisible, (v) => setState(() => _passVisible = v), c),
    const SizedBox(height: 14),
    _label('Confirm Password *', 'ይለፍ ቃል አረጋግጥ', c), const SizedBox(height: 8),
    _passwordField('Re-enter your password', _confirmPassCtrl, _confirmPassVisible, (v) => setState(() => _confirmPassVisible = v), c),
    const SizedBox(height: 28),
    _goldBtn('REGISTER & VERIFY', _submitRegister, c, loading: _loading),
    const SizedBox(height: 16),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('Already have an account? ', style: TextStyle(color: c.muted, fontSize: 13)),
      GestureDetector(onTap: () => setState(() => _step = 0), child: Text('Sign In', style: TextStyle(color: c.gold, fontSize: 13, fontWeight: FontWeight.w700))),
    ]),
    const SizedBox(height: 24),
  ]);

  Widget _buildVerify(AppColors c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Center(child: Column(children: [
      Container(width: 74, height: 74, decoration: BoxDecoration(color: c.goldBg, shape: BoxShape.circle, border: Border.all(color: c.gold, width: 2)),
        child: Center(child: Icon(Icons.mark_email_read_outlined, color: c.gold, size: 38))),
      const SizedBox(height: 16),
      Text('Verify Your Email', style: TextStyle(fontSize: 20, color: c.text, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text('We sent a verification link to', style: TextStyle(fontSize: 13, color: c.muted)),
      const SizedBox(height: 4),
      Text(_contactCtrl.text.trim(), style: TextStyle(fontSize: 14, color: c.gold, fontWeight: FontWeight.w700)),
    ])),
    const SizedBox(height: 24),
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepRow('1', 'Open your email inbox', c),
        const SizedBox(height: 10),
        _stepRow('2', 'Tap the verification link from Yenefs Abat', c),
        const SizedBox(height: 10),
        _stepRow('3', 'Come back here and tap the button below', c),
        const SizedBox(height: 8),
        Text('Tip: check your Spam folder too, and mark it "Not Spam".',
          style: TextStyle(fontSize: 11, color: c.muted, fontStyle: FontStyle.italic)),
      ]),
    ),
    const SizedBox(height: 24),
    _goldBtn("I'VE VERIFIED — CONTINUE", _submitVerify, c, loading: _loading),
    const SizedBox(height: 14),
    Center(child: GestureDetector(
      onTap: _resendCode,
      child: Text('Didn\'t get it? Resend email', style: TextStyle(color: c.gold, fontSize: 13, fontWeight: FontWeight.w700)),
    )),
    const SizedBox(height: 10),
    Center(child: GestureDetector(
      onTap: () => setState(() => _step = 0),
      child: Text('Back to Sign In', style: TextStyle(color: c.muted, fontSize: 13)),
    )),
    const SizedBox(height: 24),
  ]);

  Widget _stepRow(String n, String text, AppColors c) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 22, height: 22, decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle),
      child: Center(child: Text(n, style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontSize: 12, fontWeight: FontWeight.w800)))),
    const SizedBox(width: 10),
    Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.text, height: 1.4))),
  ]);

  Widget _buildForgot(AppColors c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      GestureDetector(onTap: () => setState(() => _step = 0), child: Icon(Icons.arrow_back_ios, color: c.gold, size: 20)),
      const SizedBox(width: 8),
      Text('Forgot Password', style: TextStyle(fontSize: 20, color: c.text, fontWeight: FontWeight.w800)),
    ]),
    const SizedBox(height: 4),
    Text('የይለፍ ቃል ረሱ? — Enter your registered phone or email and we will send you a recovery code.', style: TextStyle(fontSize: 13, color: c.muted, height: 1.5)),
    const SizedBox(height: 20),
    _label('Phone or Email', 'ስልክ ወይም ኢሜል', c),
    const SizedBox(height: 8),
    _inputField('Enter your registered phone or email', _forgotContactCtrl, c),
    const SizedBox(height: 28),
    _goldBtn('SEND RECOVERY CODE', () => _submitForgotContact(), c, loading: _loading),
    const SizedBox(height: 24),
  ]);

  Widget _label(String en, String am, AppColors c) => Row(children: [
    Text(en, style: TextStyle(fontSize: 12, color: c.text, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    const SizedBox(width: 8),
    Text(am, style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic)),
  ]);

  Widget _inputField(String hint, TextEditingController ctrl, AppColors c, {bool isNumber = false}) => TextField(
    controller: ctrl, keyboardType: isNumber ? TextInputType.number : TextInputType.text,
    style: TextStyle(color: c.text, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint, hintStyle: TextStyle(color: c.muted, fontSize: 13),
      filled: true, fillColor: c.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border, width: 0.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border, width: 0.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.gold, width: 1.5)),
    ),
  );

  Widget _passwordField(String hint, TextEditingController ctrl, bool visible, Function(bool) onToggle, AppColors c) => TextField(
    controller: ctrl, obscureText: !visible,
    style: TextStyle(color: c.text, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint, hintStyle: TextStyle(color: c.muted, fontSize: 13),
      filled: true, fillColor: c.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border, width: 0.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border, width: 0.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.gold, width: 1.5)),
      suffixIcon: GestureDetector(
        onTap: () => onToggle(!visible),
        child: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: c.muted, size: 20),
      ),
    ),
  );

  Widget _goldBtn(String label, VoidCallback onTap, AppColors c, {bool loading = false}) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: c.gold.withAlpha(loading ? 160 : 255), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: c.gold.withAlpha(80), blurRadius: 16, offset: const Offset(0, 4))]),
      child: Center(
        child: loading
          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white))
          : Text(label, style: TextStyle(fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w800, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white)),
      ),
    ),
  );
}

class MainScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  final UserProfile profile;
  const MainScreen({super.key, required this.isDark, required this.onToggleTheme, required this.profile});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _idx = 0;
  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    final screens = [
      HomeScreen(isDark: widget.isDark, onToggleTheme: widget.onToggleTheme, profile: widget.profile, onNavigate: (i) => setState(() => _idx = i)),
      ConfessScreen(isDark: widget.isDark),
      CalendarScreen(isDark: widget.isDark),
      PenanceScreen(isDark: widget.isDark),
      PriestScreen(isDark: widget.isDark),
      MoreScreen(isDark: widget.isDark),
    ];
    final items = [
      {'icon': Icons.home_outlined, 'label': 'HOME'},
      {'icon': Icons.church_outlined, 'label': 'CONFESS'},
      {'icon': Icons.calendar_month_outlined, 'label': 'CALENDAR'},
      {'icon': Icons.auto_stories_outlined, 'label': 'PENANCE'},
      {'icon': Icons.location_on_outlined, 'label': 'CHURCH'},
      {'icon': Icons.more_horiz, 'label': 'MORE'},
    ];
    return Scaffold(
      body: screens[_idx],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.hero,
          border: Border(top: BorderSide(color: c.border, width: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 8)],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (i) {
                final active = _idx == i;
                return GestureDetector(
                  onTap: () => setState(() => _idx = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? c.goldBg : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: active ? Border.all(color: c.gold.withAlpha(80), width: 0.5) : null,
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(items[i]['icon'] as IconData, color: active ? c.gold : c.muted, size: 22),
                      const SizedBox(height: 3),
                      Text(items[i]['label'] as String,
                          style: TextStyle(fontSize: 8, color: active ? c.gold : c.muted,
                              letterSpacing: 1, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// HOME SCREEN
// ═══════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  final UserProfile profile;
  final Function(int)? onNavigate;
  const HomeScreen({super.key, required this.isDark, required this.onToggleTheme, required this.profile, this.onNavigate});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _fa;
  late EthiopianDate _today;
  String _morningTime = '', _noonTime = '', _eveningTime = '', _nightTime = '';
  int _daysSinceConfession = 0;
  DateTime? _lastConfessionDate;
  int _streak = 0;
  int _longestStreak = 0;
  bool _checkedInToday = false;

  @override
  void initState() {
    super.initState();
    _today = EthiopianCalendar.today();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fa = CurvedAnimation(parent: _ac, curve: Curves.easeInOut);
    _ac.forward();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final lastConfStr = prefs.getString('last_confession');
    final lastCheckIn = prefs.getString('streak_last_checkin');
    final streak = prefs.getInt('streak_count') ?? 0;
    final longest = prefs.getInt('streak_longest') ?? 0;

    final todayStr = _dateKey(DateTime.now());
    bool checkedToday = lastCheckIn == todayStr;
    int currentStreak = streak;

    // If last check-in wasn't today or yesterday, streak is broken
    if (lastCheckIn != null && !checkedToday) {
      final lastDate = DateTime.parse(lastCheckIn);
      final daysSince = DateTime.now().difference(lastDate).inDays;
      if (daysSince > 1) {
        currentStreak = 0;
        await prefs.setInt('streak_count', 0);
      }
    }

    setState(() {
      _morningTime = prefs.getString('prayer_morning') ?? '';
      _noonTime = prefs.getString('prayer_noon') ?? '';
      _eveningTime = prefs.getString('prayer_evening') ?? '';
      _nightTime = prefs.getString('prayer_night') ?? '';
      if (lastConfStr != null) {
        _lastConfessionDate = DateTime.parse(lastConfStr);
        _daysSinceConfession = DateTime.now().difference(_lastConfessionDate!).inDays;
      }
      _streak = currentStreak;
      _longestStreak = longest;
      _checkedInToday = checkedToday;
    });
    if (_daysSinceConfession >= 30) await showConfessionNotification();
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Future<void> _checkInToday() async {
    if (_checkedInToday) return;
    final prefs = await SharedPreferences.getInstance();
    final newStreak = _streak + 1;
    final newLongest = newStreak > _longestStreak ? newStreak : _longestStreak;
    await prefs.setInt('streak_count', newStreak);
    await prefs.setInt('streak_longest', newLongest);
    await prefs.setString('streak_last_checkin', _dateKey(DateTime.now()));
    setState(() {
      _streak = newStreak;
      _longestStreak = newLongest;
      _checkedInToday = true;
    });
    if (!mounted) return;
    String msg = '🔥 Day $newStreak! Keep it going.';
    if (newStreak == 7) msg = '🎉 7 day streak! A full week of devotion!';
    if (newStreak == 30) msg = '🏆 30 days! Amazing dedication!';
    if (newStreak == 100) msg = '👑 100 days! You are truly faithful!';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: AppColors(widget.isDark).text)),
      backgroundColor: AppColors(widget.isDark).card,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _savePrayerTime(String key, String time, int notifId, String label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, time);
    if (time.isNotEmpty) {
      final parts = time.split(':');
      await schedulePrayerNotification(notifId, int.parse(parts[0]), int.parse(parts[1]), label);
    } else {
      await cancelNotification(notifId);
    }
  }

  void _showTimeDialog(String label, String current, Function(String) onSave) async {
    final c = AppColors(widget.isDark);
    TimeOfDay initial = TimeOfDay.now();
    if (current.isNotEmpty) {
      final parts = current.split(':');
      if (parts.length == 2) {
        initial = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
      }
    }
    if (current.isNotEmpty) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(label, style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
          content: Text('Current: $current. What would you like to do?', style: TextStyle(color: c.muted, fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'remove'), child: Text('Remove', style: TextStyle(color: c.red))),
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text('Cancel', style: TextStyle(color: c.muted))),
            GestureDetector(
              onTap: () => Navigator.pop(ctx, 'change'),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(8)),
                child: Text('Change', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700))),
            ),
          ],
        ),
      );
      if (action == 'remove') { onSave(''); return; }
      if (action == 'cancel' || action == null) return;
    }
    if (!mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          timePickerTheme: TimePickerThemeData(
            backgroundColor: c.card,
            hourMinuteColor: c.goldBg,
            hourMinuteTextColor: c.text,
            dayPeriodColor: c.goldBg,
            dayPeriodTextColor: c.gold,
            dialBackgroundColor: c.strip,
            dialHandColor: c.gold,
            dialTextColor: c.text,
            entryModeIconColor: c.gold,
            confirmButtonStyle: ButtonStyle(foregroundColor: WidgetStateProperty.all(c.gold)),
            cancelButtonStyle: ButtonStyle(foregroundColor: WidgetStateProperty.all(c.muted)),
          ),
          colorScheme: ColorScheme.dark(primary: c.gold, onPrimary: widget.isDark ? const Color(0xFF0F0505) : Colors.white, surface: c.card, onSurface: c.text),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      onSave('$h:$m');
    }
  }

  Future<void> _markConfessed() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_confession', now.toIso8601String());
    setState(() { _lastConfessionDate = now; _daysSinceConfession = 0; });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✝  Confession recorded. God bless you, ${widget.profile.name}.',
          style: TextStyle(color: AppColors(widget.isDark).text)),
      backgroundColor: AppColors(widget.isDark).card,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.isDark != widget.isDark) _ac.forward(from: 0);
  }

  @override
  void dispose() { _ac.dispose(); super.dispose(); }

  String _mn(int m) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m-1];

  String _firstName() {
    final parts = widget.profile.name.trim().split(' ');
    return parts.isNotEmpty ? parts[0] : widget.profile.name;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    return FadeTransition(
      opacity: _fa,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _hero(c), _dateStrip(c),
              _streakCard(c),
              _label('TODAY\'S SAINT', c), _saintCard(c),
              _label('PRAYER REMINDERS', c), _prayerSection(c),
              _label('CONFESSION', c), _confCard(c),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _hero(AppColors c) => Container(
    width: double.infinity, color: c.hero,
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        GestureDetector(
          onTap: widget.onToggleTheme,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 56, height: 30,
            decoration: BoxDecoration(
              color: widget.isDark ? const Color(0xFF2A1010) : const Color(0xFFF0EBE0),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: c.gold, width: 1),
            ),
            child: Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300), curve: Curves.easeInOut,
                left: widget.isDark ? 28 : 2, top: 2,
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle),
                  child: Center(child: Text(widget.isDark ? '🌙' : '☀️', style: const TextStyle(fontSize: 13))),
                ),
              ),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Container(
        width: 110, height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: c.gold.withAlpha(60), blurRadius: 20, spreadRadius: 2)],
        ),
        child: ClipOval(
          child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
        ),
      ),
      const SizedBox(height: 14),
      Text('YENEFS_ABAT', style: TextStyle(fontSize: 22, color: c.text, letterSpacing: 0, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('የነፍስ አባት', style: TextStyle(fontSize: 15, color: c.muted, fontStyle: FontStyle.italic)),
      const SizedBox(height: 12),
      Container(width: 60, height: 1.5, color: c.gold),
      const SizedBox(height: 12),
      Text('Peace be upon you, ${_firstName()}', style: TextStyle(fontSize: 13, color: c.muted)),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.gold.withAlpha(80), width: 0.5)),
        child: Text(widget.profile.role, style: TextStyle(fontSize: 11, color: c.gold, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 6),
      Text(_today.zemene, style: TextStyle(fontSize: 11, color: c.gold, letterSpacing: 1, fontStyle: FontStyle.italic)),
    ]),
  );

  Widget _dateStrip(AppColors c) {
    final now = DateTime.now();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border, width: 0.5),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_today.monthName} ${_today.day}, ${_today.year}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c.text)),
          const SizedBox(height: 3),
          Text('${_mn(now.month)} ${now.day}, ${now.year}',
              style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic)),
          const SizedBox(height: 3),
          Text('Day ${_today.dayOfYear} of ${_today.totalDaysInYear}',
              style: TextStyle(fontSize: 11, color: c.muted)),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.gold, width: 0.5)),
          child: Text('✦ Fasting Day', style: TextStyle(fontSize: 11, color: c.gold, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _label(String t, AppColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
    child: Row(children: [
      Container(width: 3, height: 14, color: c.gold, margin: const EdgeInsets.only(right: 8)),
      Text(t, style: TextStyle(fontSize: 10, color: c.label, letterSpacing: 3, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _streakCard(AppColors c) {
    final flameColor = _streak >= 30 ? const Color(0xFFFF6B35) : _streak >= 7 ? const Color(0xFFFFA726) : c.gold;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _checkedInToday
              ? [c.goldBg, c.goldBg]
              : [c.card, c.card],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _checkedInToday ? c.gold : c.border, width: _checkedInToday ? 1.5 : 0.5),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.card,
            border: Border.all(color: flameColor, width: 2),
            boxShadow: _streak > 0 ? [BoxShadow(color: flameColor.withAlpha(80), blurRadius: 12, spreadRadius: 1)] : [],
          ),
          child: Center(child: Text(_streak > 0 ? '🔥' : '🕊️', style: const TextStyle(fontSize: 26))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('$_streak', style: TextStyle(fontSize: 26, color: c.text, fontWeight: FontWeight.w900)),
            const SizedBox(width: 6),
            Text(_streak == 1 ? 'day streak' : 'day streak', style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 2),
          Text(
            _longestStreak > _streak ? 'Best: $_longestStreak days' : (_streak == 0 ? 'Start your streak today' : 'Personal best!'),
            style: TextStyle(fontSize: 11, color: c.muted, fontStyle: FontStyle.italic),
          ),
        ])),
        GestureDetector(
          onTap: _checkInToday,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _checkedInToday ? c.green.withAlpha(30) : c.gold,
              borderRadius: BorderRadius.circular(14),
              border: _checkedInToday ? Border.all(color: c.green, width: 1) : null,
            ),
            child: _checkedInToday
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle, color: c.green, size: 18),
                    const SizedBox(width: 4),
                    Text('Done', style: TextStyle(fontSize: 12, color: c.green, fontWeight: FontWeight.w700)),
                  ])
                : Text('Check In', style: TextStyle(fontSize: 12, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }

  Widget _saintCard(AppColors c) {
    final todayFeast = getEotcDay(_today.month, _today.day);
    final isAnnual = todayFeast?.isAnnual ?? false;
    final synaxarium = getSynaxarium(_today.month, _today.day);

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => SaintStoryScreen(
            isDark: widget.isDark,
            feastName: todayFeast?.name ?? 'No feast today',
            dateLabel: '${_today.monthNameAmharic} ${_today.day}, ${_today.year}',
            isAnnual: isAnnual,
            story: synaxarium?.fullStory,
          ),
        ));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isAnnual ? c.goldBg : c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isAnnual ? c.gold : c.border, width: isAnnual ? 1.5 : 0.5),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.gold, width: 0.5)),
              child: Center(child: Text(isAnnual ? '⭐' : '☩', style: TextStyle(fontSize: 20, color: c.gold))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                todayFeast != null ? todayFeast.name : 'No feast today',
                style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${_today.monthNameAmharic} ${_today.day}, ${_today.year}',
                style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic),
              ),
              if (isAnnual) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: c.gold.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                  child: Text('ዓመታዊ በዓል', style: TextStyle(fontSize: 10, color: c.gold, fontWeight: FontWeight.w700)),
                ),
              ],
            ])),
            Icon(Icons.chevron_right, color: c.muted, size: 20),
          ]),
          if (synaxarium != null) ...[
            const SizedBox(height: 10),
            Container(height: 0.5, color: c.border),
            const SizedBox(height: 10),
            Text(
              synaxarium.snippet,
              style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text('Tap to read more →', style: TextStyle(fontSize: 11, color: c.gold, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }

  Widget _prayerSection(AppColors c) {
    final slots = [
      {'label': 'Morning Prayer', 'amharic': 'የጥዋት ጸሎት', 'icon': '🌅', 'time': _morningTime, 'key': 'prayer_morning', 'id': 0},
      {'label': 'Noon Prayer', 'amharic': 'የቀትር ጸሎት', 'icon': '☀️', 'time': _noonTime, 'key': 'prayer_noon', 'id': 1},
      {'label': 'Evening Prayer', 'amharic': 'የሰዓት ጸሎት', 'icon': '🌇', 'time': _eveningTime, 'key': 'prayer_evening', 'id': 2},
      {'label': 'Night Prayer', 'amharic': 'የሌሊት ጸሎት', 'icon': '🌙', 'time': _nightTime, 'key': 'prayer_night', 'id': 3},
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      decoration: BoxDecoration(
        color: c.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border, width: 0.5),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: slots.asMap().entries.map((entry) {
        final i = entry.key;
        final slot = entry.value;
        final label = slot['label'] as String;
        final amharic = slot['amharic'] as String;
        final icon = slot['icon'] as String;
        final time = slot['time'] as String;
        final key = slot['key'] as String;
        final id = slot['id'] as int;
        final isLast = i == slots.length - 1;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Text(icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w600)),
                Text(amharic, style: TextStyle(fontSize: 12, color: c.muted)),
              ])),
              GestureDetector(
                onTap: () => _showTimeDialog(label, time, (newTime) async {
                  setState(() {
                    if (key == 'prayer_morning') {
                      _morningTime = newTime;
                    } else if (key == 'prayer_noon') {
                      _noonTime = newTime;
                    } else if (key == 'prayer_evening') {
                      _eveningTime = newTime;
                    } else {
                      _nightTime = newTime;
                    }
                  });
                  await _savePrayerTime(key, newTime, id, label);
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: time.isNotEmpty ? c.goldBg : c.strip,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: time.isNotEmpty ? c.gold : c.border, width: 0.5),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(time.isNotEmpty ? Icons.alarm_on : Icons.alarm_add,
                        color: time.isNotEmpty ? c.gold : c.muted, size: 14),
                    const SizedBox(width: 6),
                    Text(time.isNotEmpty ? time : 'Set Time',
                        style: TextStyle(fontSize: 12, color: time.isNotEmpty ? c.gold : c.muted, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
          ),
          if (!isLast) Divider(color: c.border, height: 0.5, indent: 16, endIndent: 16),
        ]);
      }).toList()),
    );
  }

  Widget _confCard(AppColors c) {
    final isOverdue = _daysSinceConfession >= 30;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.goldBg, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isOverdue ? c.red : c.gold.withAlpha(76), width: isOverdue ? 1.5 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.gold, width: 0.5)),
            child: const Center(child: Text('📿', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PREPARE FOR CONFESSION', style: TextStyle(fontSize: 12, color: c.text, letterSpacing: 0.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _lastConfessionDate == null ? 'No confession recorded yet'
                  : 'Last confession $_daysSinceConfession day${_daysSinceConfession == 1 ? '' : 's'} ago',
              style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic),
            ),
            if (_lastConfessionDate != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_daysSinceConfession / 30).clamp(0.0, 1.0),
                  backgroundColor: c.border,
                  valueColor: AlwaysStoppedAnimation<Color>(isOverdue ? c.red : c.gold),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                isOverdue ? '⚠  30 days passed — time to confess!' : '${30 - _daysSinceConfession} days until 30-day reminder',
                style: TextStyle(fontSize: 11, color: isOverdue ? c.red : c.gold, fontWeight: FontWeight.w600),
              ),
            ],
          ])),
        ]),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _markConfessed,
          child: Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text('✝  I just confessed today',
                style: TextStyle(fontSize: 13, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700))),
          ),
        ),
      ]),
    );
  }

}

// ═══════════════════════════════════════════════
// CONFESS SCREEN
// ═══════════════════════════════════════════════

class ConfessScreen extends StatefulWidget {
  final bool isDark;
  const ConfessScreen({super.key, required this.isDark});
  @override
  State<ConfessScreen> createState() => _ConfessScreenState();
}

class _ConfessScreenState extends State<ConfessScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final Map<int, bool> _checked = {};
  final Map<int, TextEditingController> _notes = {};
  bool _saved = false;
  DateTime? _savedAt;
  // History: list of saved confession snapshots
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAtStr = prefs.getString('confession_saved_at');
    final historyRaw = prefs.getString('confession_history');
    setState(() {
      for (int i = 0; i < sins.length; i++) {
        _checked[i] = prefs.getBool('sin_$i') ?? false;
        _notes[i] = TextEditingController(text: prefs.getString('sin_note_$i') ?? '');
      }
      _saved = prefs.getBool('confession_saved') ?? false;
      if (savedAtStr != null) _savedAt = DateTime.parse(savedAtStr);
      if (historyRaw != null) {
        _history = List<Map<String, dynamic>>.from(jsonDecode(historyRaw));
      }
    });
  }

  Future<void> _saveCheck(int i, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sin_$i', val);
    setState(() => _checked[i] = val);
  }

  Future<void> _saveNote(int i, String val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sin_note_$i', val);
  }

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (int i = 0; i < sins.length; i++) {
      await prefs.setBool('sin_$i', _checked[i] ?? false);
      await prefs.setString('sin_note_$i', _notes[i]?.text ?? '');
    }
    final now = DateTime.now();
    await prefs.setBool('confession_saved', true);
    await prefs.setString('confession_saved_at', now.toIso8601String());
    // Save snapshot to history
    final checkedSins = <Map<String, String>>[];
    for (int i = 0; i < sins.length; i++) {
      if (_checked[i] == true) {
        checkedSins.add({
          'amharic': sins[i].amharic,
          'english': sins[i].english,
          'note': _notes[i]?.text ?? '',
        });
      }
    }
    if (checkedSins.isNotEmpty) {
      final historyRaw = prefs.getString('confession_history') ?? '[]';
      final history = jsonDecode(historyRaw) as List;
      history.insert(0, {
        'date': now.toIso8601String(),
        'sins': checkedSins,
      });
      // Keep only last 50 saves
      if (history.length > 50) history.removeRange(50, history.length);
      await prefs.setString('confession_history', jsonEncode(history));
    }
    setState(() { _saved = true; _savedAt = now; });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✝  Saved. You can add more sins anytime.',
          style: TextStyle(color: AppColors(widget.isDark).text)),
      backgroundColor: AppColors(widget.isDark).card,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _markConfessedAndClear() async {
    final prefs = await SharedPreferences.getInstance();
    // Save final snapshot to history before clearing
    final now = DateTime.now();
    final snapshot = <String, dynamic>{
      'savedAt': now.toIso8601String(),
      'confessedAt': now.toIso8601String(),
      'sins': List.generate(sins.length, (i) => {
        'english': sins[i].english,
        'amharic': sins[i].amharic,
        'checked': _checked[i] ?? false,
        'note': _notes[i]?.text ?? '',
      }),
    };
    _history.insert(0, snapshot);
    await prefs.setString('confession_history', jsonEncode(_history));

    for (int i = 0; i < sins.length; i++) {
      await prefs.setBool('sin_$i', false);
      await prefs.setString('sin_note_$i', '');
      _notes[i]?.clear();
    }
    await prefs.setBool('confession_saved', false);
    await prefs.remove('confession_saved_at');
    await prefs.setString('last_confession', now.toIso8601String());
    setState(() {
      for (int i = 0; i < sins.length; i++) {
        _checked[i] = false;
      }
      _saved = false; _savedAt = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✝  Confession recorded. God bless you.',
          style: TextStyle(color: AppColors(widget.isDark).text)),
      backgroundColor: AppColors(widget.isDark).card,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (int i = 0; i < sins.length; i++) {
      await prefs.setBool('sin_$i', false);
      await prefs.setString('sin_note_$i', '');
      _notes[i]?.clear();
    }
    await prefs.setBool('confession_saved', false);
    await prefs.remove('confession_saved_at');
    setState(() {
      for (int i = 0; i < sins.length; i++) {
        _checked[i] = false;
      }
      _saved = false; _savedAt = null;
    });
  }

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month-1]} ${d.day}, ${d.year} at ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    final checkedCount = _checked.values.where((v) => v).length;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          Container(
            color: c.hero, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 4, height: 20, color: c.gold, margin: const EdgeInsets.only(right: 10)),
                Expanded(child: Text('CONFESSION GUIDE', style: TextStyle(fontSize: 16, color: c.text, letterSpacing: 2, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ConfessionGuideScreen(isDark: widget.isDark))),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [c.gold.withAlpha(70), c.goldBg]), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.gold, width: 1)),
                  child: Row(children: [
                    Icon(Icons.menu_book_rounded, color: c.gold, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Why We Confess', style: TextStyle(fontSize: 15, color: c.gold, fontWeight: FontWeight.w900)),
                      Text('ስለ ንስሐ — Learn the meaning & verses', style: TextStyle(fontSize: 11, color: c.muted)),
                    ])),
                    Icon(Icons.chevron_right, color: c.gold, size: 20),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ConfessionHistoryScreen(isDark: widget.isDark))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.gold, width: 0.5)),
                    child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.history, color: c.gold, size: 14),
                      const SizedBox(width: 4),
                      Text('History', style: TextStyle(fontSize: 12, color: c.gold, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: () => showDialog(context: context, builder: (ctx) => AlertDialog(
                    backgroundColor: c.card,
                    title: Text('Clear All', style: TextStyle(color: c.text)),
                    content: Text('Clear all checked sins and notes?', style: TextStyle(color: c.muted)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: c.muted))),
                      TextButton(onPressed: () { Navigator.pop(ctx); _clearAll(); }, child: Text('Clear', style: TextStyle(color: c.red))),
                    ],
                  )),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: c.strip, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.delete_outline, color: c.muted, size: 14),
                      const SizedBox(width: 4),
                      Text('Clear All', style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                )),
              ]),
              const SizedBox(height: 10),
              Text('ኑዛዜ ዝርዝር — Review before confessing', style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.gold, width: 0.5)),
                  child: Text('$checkedCount of ${sins.length} checked', style: TextStyle(fontSize: 12, color: c.gold, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                if (_saved && _savedAt != null)
                  Expanded(child: Text('Saved ${_formatDate(_savedAt!)}',
                      style: TextStyle(fontSize: 10, color: c.muted, fontStyle: FontStyle.italic))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: _saveAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.gold, width: 0.5)),
                    child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.save_outlined, color: c.gold, size: 16),
                      const SizedBox(width: 6),
                      Text('Save', style: TextStyle(fontSize: 13, color: c.gold, fontWeight: FontWeight.w700)),
                    ])),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: () => showDialog(context: context, builder: (ctx) => AlertDialog(
                    backgroundColor: c.card,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text('I Have Confessed', style: TextStyle(color: c.gold, fontWeight: FontWeight.w700)),
                    content: Text('This will record your confession and clear all saved sins. Are you sure?', style: TextStyle(color: c.muted, fontSize: 13)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: c.muted))),
                      GestureDetector(
                        onTap: () { Navigator.pop(ctx); _markConfessedAndClear(); },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(8)),
                          child: Text('Yes, Confessed', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  )),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.church_outlined, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text('Confessed ✝', style: TextStyle(fontSize: 13, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700)),
                    ])),
                  ),
                )),
              ]),
            ]),
          ),
          Divider(color: c.border, height: 0.5),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: sins.length,
              itemBuilder: (context, i) {
                final sin = sins[i];
                final isChecked = _checked[i] ?? false;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isChecked ? c.goldBg : c.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isChecked ? c.gold : c.border, width: isChecked ? 1 : 0.5),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(sin.amharic, style: TextStyle(fontSize: 15, color: c.text, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(sin.english, style: TextStyle(fontSize: 12, color: c.muted)),
                        ])),
                        Transform.scale(
                          scale: 1.2,
                          child: Checkbox(
                            value: isChecked,
                            onChanged: (v) => _saveCheck(i, v ?? false),
                            activeColor: c.gold,
                            checkColor: widget.isDark ? const Color(0xFF0F0505) : Colors.white,
                            side: BorderSide(color: c.muted, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: TextField(
                        controller: _notes[i],
                        onChanged: (v) => _saveNote(i, v),
                        maxLines: 2,
                        style: TextStyle(fontSize: 12, color: c.text),
                        decoration: InputDecoration(
                          hintText: 'Add personal notes here...',
                          hintStyle: TextStyle(fontSize: 11, color: c.muted),
                          filled: true, fillColor: c.bg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border, width: 0.5)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border, width: 0.5)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.gold, width: 1.5)),
                        ),
                      ),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// PENANCE SCREEN
// ═══════════════════════════════════════════════

class PenanceScreen extends StatefulWidget {
  final bool isDark;
  const PenanceScreen({super.key, required this.isDark});
  @override
  State<PenanceScreen> createState() => _PenanceScreenState();
}

class _PenanceScreenState extends State<PenanceScreen> {
  List<PenanceItem> _items = [];

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('penance_items');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      setState(() => _items = list.map((e) => PenanceItem.fromJson(e)).toList());
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('penance_items', jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  void _addPenance() {
    final c = AppColors(widget.isDark);
    PenanceType? selected;
    final countCtrl = TextEditingController();
    String frequency = 'Daily';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Add Penance', style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Type of Penance', style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PenanceType>(
                    value: selected, isExpanded: true,
                    hint: Text('Select penance type', style: TextStyle(color: c.muted, fontSize: 13)),
                    dropdownColor: c.card,
                    items: penanceTypes.map((p) => DropdownMenuItem(
                      value: p,
                      child: Row(children: [
                        Text(p.icon, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, style: TextStyle(color: c.text, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(p.amharic, style: TextStyle(color: c.muted, fontSize: 11)),
                        ])),
                      ]),
                    )).toList(),
                    onChanged: (v) => setLocal(() => selected = v),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('How many times ordered?', style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: countCtrl, keyboardType: TextInputType.number,
                style: TextStyle(color: c.text),
                decoration: InputDecoration(
                  hintText: 'e.g. 100', hintStyle: TextStyle(color: c.muted),
                  filled: true, fillColor: c.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.gold, width: 1.5)),
                ),
              ),
              const SizedBox(height: 16),
              Text('How often?', style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: ['Daily', 'Weekly', 'Once total'].map((f) =>
                GestureDetector(
                  onTap: () => setLocal(() => frequency = f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: frequency == f ? c.gold : c.strip,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(f, style: TextStyle(
                      color: frequency == f ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.muted,
                      fontSize: 12, fontWeight: FontWeight.w600,
                    )),
                  ),
                )
              ).toList()),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: c.muted))),
            GestureDetector(
              onTap: () {
                if (selected == null || countCtrl.text.isEmpty) return;
                final count = int.tryParse(countCtrl.text) ?? 0;
                if (count <= 0) return;
                setState(() => _items.add(PenanceItem(
                  type: selected!.name, amharic: selected!.amharic,
                  icon: selected!.icon, totalCount: count,
                  completedCount: 0, frequency: frequency,
                )));
                _saveData();
                Navigator.pop(ctx);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(8)),
                child: Text('Add', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _incrementPenance(int index) {
    setState(() {
      final item = _items[index];
      if (item.completedCount < item.totalCount) {
        item.completedCount++;
        if (item.completedCount >= item.totalCount) {
          item.finished = true;
          _showFinishedDialog(item);
        }
      }
    });
    _saveData();
  }

  void _showFinishedDialog(PenanceItem item) {
    final c = AppColors(widget.isDark);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('🎉 Penance Complete!', style: TextStyle(color: c.gold, fontWeight: FontWeight.w700, fontSize: 18), textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(item.icon, style: const TextStyle(fontSize: 48), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text('You have completed your penance of:', style: TextStyle(color: c.muted, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('${item.type}\n${item.amharic}', style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 15), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold, width: 0.5)),
            child: Text('Go to your priest and tell him you have completed your penance.\n\nወደ አባ ሂደህ ፍቃደ እግዚአብሔርን ተቀበል።',
                style: TextStyle(color: c.text, fontSize: 13, height: 1.6), textAlign: TextAlign.center),
          ),
        ]),
        actions: [
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(10)),
              child: Text('Understood ✝', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700, fontSize: 14), textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteItem(int index) {
    setState(() => _items.removeAt(index));
    _saveData();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          Container(
            color: c.hero, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 4, height: 20, color: c.gold, margin: const EdgeInsets.only(right: 10)),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('PENANCE TRACKER', style: TextStyle(fontSize: 16, color: c.text, letterSpacing: 2, fontWeight: FontWeight.w800)),
                  Text('የተሠጦት ቅኖና', style: TextStyle(fontSize: 13, color: c.muted, fontStyle: FontStyle.italic)),
                ]),
                const Spacer(),
                GestureDetector(
                  onTap: _addPenance,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.gold, width: 0.5)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add, color: c.gold, size: 16),
                      const SizedBox(width: 4),
                      Text('Add', style: TextStyle(fontSize: 12, color: c.gold, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),
            ]),
          ),
          Divider(color: c.border, height: 0.5),
          Expanded(
            child: _items.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('📜', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 16),
                    Text('No penance assigned yet', style: TextStyle(fontSize: 15, color: c.muted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('Tap + Add after visiting your priest', style: TextStyle(fontSize: 13, color: c.muted, fontStyle: FontStyle.italic)),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      final progress = item.totalCount > 0 ? item.completedCount / item.totalCount : 0.0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: item.finished ? c.goldBg : c.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: item.finished ? c.gold : c.border, width: item.finished ? 1.5 : 0.5),
                          boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(item.icon, style: const TextStyle(fontSize: 28)),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(item.type, style: TextStyle(fontSize: 15, color: c.text, fontWeight: FontWeight.w700)),
                                Text(item.amharic, style: TextStyle(fontSize: 12, color: c.muted)),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(color: c.strip, borderRadius: BorderRadius.circular(10)),
                                    child: Text(item.frequency, style: TextStyle(fontSize: 11, color: c.muted, fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(width: 8),
                                  if (item.finished)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                      decoration: BoxDecoration(color: c.green.withAlpha(30), borderRadius: BorderRadius.circular(10)),
                                      child: Text('✓ Complete', style: TextStyle(fontSize: 11, color: c.green, fontWeight: FontWeight.w700)),
                                    ),
                                ]),
                              ])),
                              GestureDetector(
                                onTap: () => _deleteItem(i),
                                child: Icon(Icons.delete_outline, color: c.muted, size: 20),
                              ),
                            ]),
                            const SizedBox(height: 14),
                            Row(children: [
                              Expanded(child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: c.border,
                                  valueColor: AlwaysStoppedAnimation<Color>(item.finished ? c.green : c.gold),
                                  minHeight: 8,
                                ),
                              )),
                              const SizedBox(width: 12),
                              Text('${item.completedCount}/${item.totalCount}',
                                  style: TextStyle(fontSize: 13, color: c.gold, fontWeight: FontWeight.w700)),
                            ]),
                            const SizedBox(height: 14),
                            if (!item.finished)
                              GestureDetector(
                                onTap: () => _incrementPenance(i),
                                child: Container(
                                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 11),
                                  decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(10)),
                                  child: Center(child: Text('+ Mark One Done',
                                      style: TextStyle(fontSize: 13, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700))),
                                ),
                              )
                            else
                              Container(
                                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(color: c.green.withAlpha(30), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.green, width: 0.5)),
                                child: Center(child: Text('✓ Go tell your priest you are done!',
                                    style: TextStyle(fontSize: 13, color: c.green, fontWeight: FontWeight.w700))),
                              ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// CALENDAR SCREEN
// ═══════════════════════════════════════════════



// ═══════════════════════════════════════════════
// SYNAXARIUM (ስንክሳር) - Teaching snippets & stories
// ═══════════════════════════════════════════════

class SynaxariumEntry {
  final String snippet;
  final String fullStory;
  const SynaxariumEntry({required this.snippet, required this.fullStory});
}

final Map<String, SynaxariumEntry> synaxariumStories = {
  '1-1': SynaxariumEntry(
    snippet: 'የዘመን መለወጫ በዓል፤ መጥምቁ ዮሐንስ የጌታን መንገድ ለመጥረግ በምድረ በዳ የጮኸበትን ስብከትና አዲስ ዘመንን ማሰብ።',
    fullStory: 'የዘመን መለወጫ በዓል፤ መጥምቁ ዮሐንስ የጌታን መንገድ ለመጥረግ በምድረ በዳ የጮኸበትን ስብከትና አዲስ ዘመንን ማሰብ።',
  ),
  '1-2': SynaxariumEntry(
    snippet: 'መጥምቁ ዮሐንስ በሄሮድስ እጅ አንገቱ የተሰየመበትና ስለ እውነት ሰማዕት የሆነበት ዕለት።',
    fullStory: 'መጥምቁ ዮሐንስ በሄሮድስ እጅ አንገቱ የተሰየመበትና ስለ እውነት ሰማዕት የሆነበት ዕለት።',
  ),
  '1-3': SynaxariumEntry(
    snippet: 'እመቤታችን በሦስት ዓመቷ ወደ ቤተ መቅደስ የገባችበት ወርሃዊ መታሰቢያ።',
    fullStory: 'እመቤታችን በሦስት ዓመቷ ወደ ቤተ መቅደስ የገባችበት ወርሃዊ መታሰቢያ።',
  ),
  '1-4': SynaxariumEntry(
    snippet: 'የፍቅር ሐዋርያና ወንጌላዊው ቅዱስ ዮሐንስ ያሳየው ረቂቅ ሥነ-መለኮትና ተጋድሎ።',
    fullStory: 'የፍቅር ሐዋርያና ወንጌላዊው ቅዱስ ዮሐንስ ያሳየው ረቂቅ ሥነ-መለኮትና ተጋድሎ።',
  ),
  '1-5': SynaxariumEntry(
    snippet: 'ጻድቁ አባታችን በምድረ በዳ የኖሩት የቅድስና ሕይወትና ለፍጥረት ያሳዩት ታላቅ ርኅራኄ።',
    fullStory: 'ጻድቁ አባታችን በምድረ በዳ የኖሩት የቅድስና ሕይወትና ለፍጥረት ያሳዩት ታላቅ ርኅራኄ።',
  ),
  '1-6': SynaxariumEntry(
    snippet: 'ቅድስት ቤተሰብ በስደት ዘመን በግብፅ ቁስቋም ተራራ ያረፉበት ወርሃዊ መታሰቢያ።',
    fullStory: 'ቅድስት ቤተሰብ በስደት ዘመን በግብፅ ቁስቋም ተራራ ያረፉበት ወርሃዊ መታሰቢያ።',
  ),
  '1-7': SynaxariumEntry(
    snippet: 'የአብ፣ የወልድ፣ የመንፈስ ቅዱስ አንድነትና ሦስትነት የሚመሰገንበት ታላቅ ዕለት።',
    fullStory: 'የአብ፣ የወልድ፣ የመንፈስ ቅዱስ አንድነትና ሦስትነት የሚመሰገንበት ታላቅ ዕለት።',
  ),
  '1-8': SynaxariumEntry(
    snippet: 'በትሕትናና በታላቅ ተጋድሎ የኖሩት የቅዱስ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'በትሕትናና በታላቅ ተጋድሎ የኖሩት የቅዱስ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
  ),
  '1-9': SynaxariumEntry(
    snippet: 'በኒቅያ ጉባኤ ተገኝተው አርዮስን ያወገዙት 318ቱ ኦርቶዶክሳውያን ሊቃውንት።',
    fullStory: 'በኒቅያ ጉባኤ ተገኝተው አርዮስን ያወገዙት 318ቱ ኦርቶዶክሳውያን ሊቃውንት።',
  ),
  '1-10': SynaxariumEntry(
    snippet: 'የጌታችን የኢየሱስ ክርስቶስ ክቡርና ሕያው መስቀል የሚታሰብበት ወርሃዊ ዕለት።',
    fullStory: 'የጌታችን የኢየሱስ ክርስቶስ ክቡርና ሕያው መስቀል የሚታሰብበት ወርሃዊ ዕለት።',
  ),
  '1-11': SynaxariumEntry(
    snippet: 'የእመቤታችን የቅድስት ድንግል ማርያም ደጋግ ወላጆች የሚታሰቡበት ዕለት።',
    fullStory: 'የእመቤታችን የቅድስት ድንግል ማርያም ደጋግ ወላጆች የሚታሰቡበት ዕለት።',
  ),
  '1-12': SynaxariumEntry(
    snippet: 'የመላእክት አለቃ የቅዱስ ሚካኤል ጥበቃና ለሰዎች የሚያቀርበው የምሕረት ልመና።',
    fullStory: 'የመላእክት አለቃ የቅዱስ ሚካኤል ጥበቃና ለሰዎች የሚያቀርበው የምሕረት ልመና።',
  ),
  '1-13': SynaxariumEntry(
    snippet: 'ለልዑል እግዚአብሔር አብ የሚቀርብ ልዩ የወርሃዊ አምልኮና የምስጋና ዕለት።',
    fullStory: 'ለልዑል እግዚአብሔር አብ የሚቀርብ ልዩ የወርሃዊ አምልኮና የምስጋና ዕለት።',
  ),
  '1-14': SynaxariumEntry(
    snippet: 'ከዘጠኙ ቅዱሳን አንዱ የሆኑት የታላቁ አባታችን የአቡነ አረጋዊ ገድልና ክብር።',
    fullStory: 'ከዘጠኙ ቅዱሳን አንዱ የሆኑት የታላቁ አባታችን የአቡነ አረጋዊ ገድልና ክብር።',
  ),
  '1-15': SynaxariumEntry(
    snippet: 'ሕፃኑ ቅዱስ ቂርቆስና እናቱ ኢየሉጣ በእሳት ውስጥ የጸኑበት የሰማዕትነት ታሪክ።',
    fullStory: 'ሕፃኑ ቅዱስ ቂርቆስና እናቱ ኢየሉጣ በእሳት ውስጥ የጸኑበት የሰማዕትነት ታሪክ።',
  ),
  '1-16': SynaxariumEntry(
    snippet: 'እግዚአብሔር ለእመቤታችን የዓለምን ምሕረት የሰጠበት ታላቅ የቃልኪዳን ዕለት።',
    fullStory: 'እግዚአብሔር ለእመቤታችን የዓለምን ምሕረት የሰጠበት ታላቅ የቃልኪዳን ዕለት።',
  ),
  '1-17': SynaxariumEntry(
    snippet: 'ንግሥት ዕሌኒ የጌታን መስቀል በእጣን ጢስ ምልክትነት ያገኘችበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ንግሥት ዕሌኒ የጌታን መስቀል በእጣን ጢስ ምልክትነት ያገኘችበት ታላቅ ዓመታዊ በዓል።',
  ),
  '1-18': SynaxariumEntry(
    snippet: 'ስለ ሰንበት ቅድስናና ስለ ኦርቶዶክስ ሥርዓት የተጋደሉት ጻድቅ አባት መታሰቢያ።',
    fullStory: 'ስለ ሰንበት ቅድስናና ስለ ኦርቶዶክስ ሥርዓት የተጋደሉት ጻድቅ አባት መታሰቢያ።',
  ),
  '1-19': SynaxariumEntry(
    snippet: 'የምሥራች አብሳሪውና ቅዱሳንን ከሚነድ እሳት የሚያድነው መልአክ ወርሃዊ በዓል።',
    fullStory: 'የምሥራች አብሳሪውና ቅዱሳንን ከሚነድ እሳት የሚያድነው መልአክ ወርሃዊ በዓል።',
  ),
  '1-20': SynaxariumEntry(
    snippet: 'በሰማይና በምድር ያሉ ቅዱሳንና ጻድቃን ሁሉ በአንድነት የሚታሰቡበት ዕለት።',
    fullStory: 'በሰማይና በምድር ያሉ ቅዱሳንና ጻድቃን ሁሉ በአንድነት የሚታሰቡበት ዕለት።',
  ),
  '1-21': SynaxariumEntry(
    snippet: 'የጌታችን ግማደ መስቀል በግሸን ደብረ ከርቤ ተራራ በክብር የተቀመጠበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'የጌታችን ግማደ መስቀል በግሸን ደብረ ከርቤ ተራራ በክብር የተቀመጠበት ታላቅ ዓመታዊ በዓል።',
  ),
  '1-22': SynaxariumEntry(
    snippet: 'ለእመቤታችን ምስጋና በመጻፉ ምክንያት ከእሷ የብርሃን ልብስ የተቀበለ አባት።',
    fullStory: 'ለእመቤታችን ምስጋና በመጻፉ ምክንያት ከእሷ የብርሃን ልብስ የተቀበለ አባት።',
  ),
  '1-23': SynaxariumEntry(
    snippet: 'የሰማዕታት አለቃ የልዳው ኮከብ ቅዱስ ጊዮርጊስ ተጋድሎና ድል ወርሃዊ መታሰቢያ።',
    fullStory: 'የሰማዕታት አለቃ የልዳው ኮከብ ቅዱስ ጊዮርጊስ ተጋድሎና ድል ወርሃዊ መታሰቢያ።',
  ),
  '1-24': SynaxariumEntry(
    snippet: 'ታላቁ የሀገራችን ብርሃንና ሐዋርያዊ አባት አቡነ ተክለሃይማኖት የሚታሰቡበት።',
    fullStory: 'ታላቁ የሀገራችን ብርሃንና ሐዋርያዊ አባት አቡነ ተክለሃይማኖት የሚታሰቡበት።',
  ),
  '1-25': SynaxariumEntry(
    snippet: 'በመልአክ ሰይፍ ጠላትን ድል ያደረገው ባለ ሁለት ሰይፉ ሰማዕት ወርሃዊ በዓል።',
    fullStory: 'በመልአክ ሰይፍ ጠላትን ድል ያደረገው ባለ ሁለት ሰይፉ ሰማዕት ወርሃዊ በዓል።',
  ),
  '1-26': SynaxariumEntry(
    snippet: 'የማኅበረ ቅዱሳንና የምዕመናን የእመቤታችንን ስደት የሚያስቡበት የ45 ቀናት ጾም መግቢያ።',
    fullStory: 'የማኅበረ ቅዱሳንና የምዕመናን የእመቤታችንን ስደት የሚያስቡበት የ45 ቀናት ጾም መግቢያ።',
  ),
  '1-27': SynaxariumEntry(
    snippet: 'ጌታችን ዓለምን ለማዳን በጎልጎታ የከፈለውን ታላቅ መሥዋዕትነት ማሰብ።',
    fullStory: 'ጌታችን ዓለምን ለማዳን በጎልጎታ የከፈለውን ታላቅ መሥዋዕትነት ማሰብ።',
  ),
  '1-28': SynaxariumEntry(
    snippet: 'እግዚአብሔር ከእኛ ጋር መሆኑንና ምስጢረ ሥጋዌ የሚወደስበት ወርሃዊ ዕለት።',
    fullStory: 'እግዚአብሔር ከእኛ ጋር መሆኑንና ምስጢረ ሥጋዌ የሚወደስበት ወርሃዊ ዕለት።',
  ),
  '1-29': SynaxariumEntry(
    snippet: 'ስለ ንጽሕናዋና ስለ ክርስቶስ ፍቅር ድርጣድስን ያሸነፈችበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ስለ ንጽሕናዋና ስለ ክርስቶስ ፍቅር ድርጣድስን ያሸነፈችበት ታላቅ ዓመታዊ በዓል።',
  ),
  '1-30': SynaxariumEntry(
    snippet: 'የእስክንድርያ መንበር መሥራችና የመጀመሪያው ወንጌል ጸሐፊ ወርሃዊ መታሰቢያ።',
    fullStory: 'የእስክንድርያ መንበር መሥራችና የመጀመሪያው ወንጌል ጸሐፊ ወርሃዊ መታሰቢያ።',
  ),
  '2-1': SynaxariumEntry(
    snippet: 'የእመቤታችን ልደትና ነቢዩ ኤልያስ በብርሃን ሰረገላ ወደ ሰማይ ያረገበት ታላቅ በዓል።',
    fullStory: 'የእመቤታችን ልደትና ነቢዩ ኤልያስ በብርሃን ሰረገላ ወደ ሰማይ ያረገበት ታላቅ በዓል።',
  ),
  '2-2': SynaxariumEntry(
    snippet: 'የቅዱስ ታዴዎስ ሐዋርያዊ አገልግሎት፣ ተጋድሎና ሰማዕትነት መታሰቢያ።',
    fullStory: 'የቅዱስ ታዴዎስ ሐዋርያዊ አገልግሎት፣ ተጋድሎና ሰማዕትነት መታሰቢያ።',
  ),
  '2-3': SynaxariumEntry(
    snippet: 'እመቤታችን ወደ ቤተ መቅደስ የገባችበት ወርሃዊ መታሰቢያ።',
    fullStory: 'እመቤታችን ወደ ቤተ መቅደስ የገባችበት ወርሃዊ መታሰቢያ።',
  ),
  '2-4': SynaxariumEntry(
    snippet: 'የቅዱስ ዮሐንስ ወንጌላዊ የፍቅርና ረቂቅ መለኮት ትምህርት ምስጋና።',
    fullStory: 'የቅዱስ ዮሐንስ ወንጌላዊ የፍቅርና ረቂቅ መለኮት ትምህርት ምስጋና።',
  ),
  '2-5': SynaxariumEntry(
    snippet: 'ጻድቁ አባታችን በዝቋላ የጸለዩት ታላቅ ጸሎትና ገድል መታሰቢያ።',
    fullStory: 'ጻድቁ አባታችን በዝቋላ የጸለዩት ታላቅ ጸሎትና ገድል መታሰቢያ።',
  ),
  '2-6': SynaxariumEntry(
    snippet: 'የቅድስት ቤተሰብ በስደት ወቅት ያሳለፉት መከራና በረከት መታሰቢያ።',
    fullStory: 'የቅድስት ቤተሰብ በስደት ወቅት ያሳለፉት መከራና በረከት መታሰቢያ።',
  ),
  '2-7': SynaxariumEntry(
    snippet: 'የቅድስት ሥላሴ መለኮታዊ ክብርና ቸርነት የሚወደስበት ዕለት።',
    fullStory: 'የቅድስት ሥላሴ መለኮታዊ ክብርና ቸርነት የሚወደስበት ዕለት።',
  ),
  '2-8': SynaxariumEntry(
    snippet: 'የቅዱስ አባ ኪሮስ ገዳማዊ ሕይወትና የጽናት ተጋድሎ ማሰብ።',
    fullStory: 'የቅዱስ አባ ኪሮስ ገዳማዊ ሕይወትና የጽናት ተጋድሎ ማሰብ።',
  ),
  '2-9': SynaxariumEntry(
    snippet: 'የሃይማኖትን ቀና ሥርዓት የደነገጉት 318ቱ ሊቃውንት መታሰቢያ።',
    fullStory: 'የሃይማኖትን ቀና ሥርዓት የደነገጉት 318ቱ ሊቃውንት መታሰቢያ።',
  ),
  '2-10': SynaxariumEntry(
    snippet: 'የጌታችን የኢየሱስ ክርስቶስ የማዳን መሣሪያ የሆነው መስቀል ምስጋና።',
    fullStory: 'የጌታችን የኢየሱስ ክርስቶስ የማዳን መሣሪያ የሆነው መስቀል ምስጋና።',
  ),
  '2-11': SynaxariumEntry(
    snippet: 'የእመቤታችን ድንግል ማርያም ወላጆች ቅድስና የሚታሰብበት ዕለት።',
    fullStory: 'የእመቤታችን ድንግል ማርያም ወላጆች ቅድስና የሚታሰብበት ዕለት።',
  ),
  '2-12': SynaxariumEntry(
    snippet: 'ቅዱስ ሚካኤል ሕዝበ ክርስቲያንን ከጠላት ውግያ የሚጠብቅበት ወርሃዊ በዓል።',
    fullStory: 'ቅዱስ ሚካኤል ሕዝበ ክርስቲያንን ከጠላት ውግያ የሚጠብቅበት ወርሃዊ በዓል።',
  ),
  '2-13': SynaxariumEntry(
    snippet: 'ለእግዚአብሔር አብ የሚቀርብ የፍጥረት ሁሉ ፈጣሪነቱ ምስጋና።',
    fullStory: 'ለእግዚአብሔር አብ የሚቀርብ የፍጥረት ሁሉ ፈጣሪነቱ ምስጋና።',
  ),
  '2-14': SynaxariumEntry(
    snippet: 'የአቡነ አረጋዊ ገድልና የንጉሥ ልጅ ሆኖ ሳለ ሰርጉን ትቶ በሰው ደጅ የለመነው የቅዱስ ገብረ ክርስቶስ ታላቅ ዕረፍት።',
    fullStory: 'የአቡነ አረጋዊ ገድልና የንጉሥ ልጅ ሆኖ ሳለ ሰርጉን ትቶ በሰው ደጅ የለመነው የቅዱስ ገብረ ክርስቶስ ታላቅ ዕረፍት።',
  ),
  '2-15': SynaxariumEntry(
    snippet: 'የሕፃኑ ቅዱስ ቂርቆስና የኢየሉጣ የጽናትና የሰማዕትነት ክብር።',
    fullStory: 'የሕፃኑ ቅዱስ ቂርቆስና የኢየሉጣ የጽናትና የሰማዕትነት ክብር።',
  ),
  '2-16': SynaxariumEntry(
    snippet: 'እመቤታችን ለምልመናን የምታቀርበው አማላጅነትና ቃልኪዳን።',
    fullStory: 'እመቤታችን ለምልመናን የምታቀርበው አማላጅነትና ቃልኪዳን።',
  ),
  '2-17': SynaxariumEntry(
    snippet: 'የመጀመሪያው ሰማዕትና የዲያቆናት አለቃ የቅዱስ እስጢፋኖስ ክብር።',
    fullStory: 'የመጀመሪያው ሰማዕትና የዲያቆናት አለቃ የቅዱስ እስጢፋኖስ ክብር።',
  ),
  '2-18': SynaxariumEntry(
    snippet: 'የጻድቁ አባታችን የአቡነ ኤዎስጣቴዎስን ወርሃዊ ገድል ማሰብ።',
    fullStory: 'የጻድቁ አባታችን የአቡነ ኤዎስጣቴዎስን ወርሃዊ ገድል ማሰብ።',
  ),
  '2-19': SynaxariumEntry(
    snippet: 'ቅዱስ ገብርኤል ሰዎችን ከጭንቅና ከመከራ የሚያድንበት ወርሃዊ ዕለት።',
    fullStory: 'ቅዱስ ገብርኤል ሰዎችን ከጭንቅና ከመከራ የሚያድንበት ወርሃዊ ዕለት።',
  ),
  '2-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ማኅበርና የሰማይ በረከታቸው የሚታሰብበት።',
    fullStory: 'የቅዱሳን ሁሉ ማኅበርና የሰማይ በረከታቸው የሚታሰብበት።',
  ),
  '2-21': SynaxariumEntry(
    snippet: 'የእመቤታችን የቅድስት ድንግል ማርያም ታላቅ ወርሃዊ የምስጋና በዓል።',
    fullStory: 'የእመቤታችን የቅድስት ድንግል ማርያም ታላቅ ወርሃዊ የምስጋና በዓል።',
  ),
  '2-22': SynaxariumEntry(
    snippet: 'ሐኪምና ሰዓሊ የነበረው፣ የእመቤታችንን ሥዕል መጀመሪያ የሳለው ሐዋርያ ዓመታዊ ዕረፍት።',
    fullStory: 'ሐኪምና ሰዓሊ የነበረው፣ የእመቤታችንን ሥዕል መጀመሪያ የሳለው ሐዋርያ ዓመታዊ ዕረፍት።',
  ),
  '2-23': SynaxariumEntry(
    snippet: 'የኮከበ ልዳው የቅዱስ ጊዮርጊስ ወርሃዊ የድል መታሰቢያ።',
    fullStory: 'የኮከበ ልዳው የቅዱስ ጊዮርጊስ ወርሃዊ የድል መታሰቢያ።',
  ),
  '2-24': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ ተክለ ሃይማኖት ሐዋርያዊ አገልግሎት ምስጋና።',
    fullStory: 'የአባታችን የአቡነ ተክለ ሃይማኖት ሐዋርያዊ አገልግሎት ምስጋና።',
  ),
  '2-25': SynaxariumEntry(
    snippet: 'የሰማዕቱ የቅዱስ መርቆሬዎስ ወርሃዊ የጋሻና የሰይፍ ረድኤት።',
    fullStory: 'የሰማዕቱ የቅዱስ መርቆሬዎስ ወርሃዊ የጋሻና የሰይፍ ረድኤት።',
  ),
  '2-26': SynaxariumEntry(
    snippet: 'የቅዱስ ቶማስ ሐዋርያ ወርሃዊ መታሰቢያና የህንድ ስብከቱ።',
    fullStory: 'የቅዱስ ቶማስ ሐዋርያ ወርሃዊ መታሰቢያና የህንድ ስብከቱ።',
  ),
  '2-27': SynaxariumEntry(
    snippet: 'የመድኃኔዓለም (የዓለም መድኃኒት) ታላቁ ዓመታዊ የቅዳሴና የምስጋና በዓል።',
    fullStory: 'የመድኃኔዓለም (የዓለም መድኃኒት) ታላቁ ዓመታዊ የቅዳሴና የምስጋና በዓል።',
  ),
  '2-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ጥበቃና መለኮታዊ ፍቅር።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ጥበቃና መለኮታዊ ፍቅር።',
  ),
  '2-29': SynaxariumEntry(
    snippet: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎችና ስብከቱ የሚታሰብበት።',
    fullStory: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎችና ስብከቱ የሚታሰብበት።',
  ),
  '2-30': SynaxariumEntry(
    snippet: 'የወንጌላዊው ማርቆስ ወርሃዊ የቅድስናና የስብከት ታሪክ።',
    fullStory: 'የወንጌላዊው ማርቆስ ወርሃዊ የቅድስናና የስብከት ታሪክ።',
  ),
  '3-1': SynaxariumEntry(
    snippet: 'የእመቤታችን የልደት በዓል ወርሃዊ የምስጋና ቅዳሴ።',
    fullStory: 'የእመቤታችን የልደት በዓል ወርሃዊ የምስጋና ቅዳሴ።',
  ),
  '3-2': SynaxariumEntry(
    snippet: 'የሐዋርያው የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የሐዋርያው የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
  ),
  '3-3': SynaxariumEntry(
    snippet: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
  ),
  '3-4': SynaxariumEntry(
    snippet: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ መታሰቢያ።',
  ),
  '3-5': SynaxariumEntry(
    snippet: 'የጻድቁ አባታችን የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ በረከት።',
    fullStory: 'የጻድቁ አባታችን የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ በረከት።',
  ),
  '3-6': SynaxariumEntry(
    snippet: 'የቅድስት ቤተሰብ ስደት ማብቂያና የ45 ቀናት የጽጌ ጾም ፍጻሜ ዓመታዊ በዓል።',
    fullStory: 'የቅድስት ቤተሰብ ስደት ማብቂያና የ45 ቀናት የጽጌ ጾም ፍጻሜ ዓመታዊ በዓል።',
  ),
  '3-7': SynaxariumEntry(
    snippet: 'የቅድስት ሥላሴ ወርሃዊ የምስጋናና የውዳሴ ጸሎት።',
    fullStory: 'የቅድስት ሥላሴ ወርሃዊ የምስጋናና የውዳሴ ጸሎት።',
  ),
  '3-8': SynaxariumEntry(
    snippet: 'የእግዚአብሔርን መንበር የሚሸከሙት አራቱ ኪሩቤል ታላቅ ዓመታዊ በዓል።',
    fullStory: 'የእግዚአብሔርን መንበር የሚሸከሙት አራቱ ኪሩቤል ታላቅ ዓመታዊ በዓል።',
  ),
  '3-9': SynaxariumEntry(
    snippet: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ መታሰቢያ።',
    fullStory: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ መታሰቢያ።',
  ),
  '3-10': SynaxariumEntry(
    snippet: 'የክርስቶስ መስቀል ወርሃዊ የድል አክሊል ማሰብ።',
    fullStory: 'የክርስቶስ መስቀል ወርሃዊ የድል አክሊል ማሰብ።',
  ),
  '3-11': SynaxariumEntry(
    snippet: 'የእመቤታችን እናት የቅድስት ሐና ወርሃዊ መታሰቢያ።',
    fullStory: 'የእመቤታችን እናት የቅድስት ሐና ወርሃዊ መታሰቢያ።',
  ),
  '3-12': SynaxariumEntry(
    snippet: 'ቅዱስ ሚካኤል ሳጥናኤልን ድል አድርጎ ከሰማይ የጣለበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ቅዱስ ሚካኤል ሳጥናኤልን ድል አድርጎ ከሰማይ የጣለበት ታላቅ ዓመታዊ በዓል።',
  ),
  '3-13': SynaxariumEntry(
    snippet: 'ለእግዚአብሔር አብ የሚቀርብ የወርሃዊ ስግደትና ምስጋና።',
    fullStory: 'ለእግዚአብሔር አብ የሚቀርብ የወርሃዊ ስግደትና ምስጋና።',
  ),
  '3-14': SynaxariumEntry(
    snippet: 'የጻድቁ የአቡነ አረጋዊ ወርሃዊ የረድኤት በዓል።',
    fullStory: 'የጻድቁ የአቡነ አረጋዊ ወርሃዊ የረድኤት በዓል።',
  ),
  '3-15': SynaxariumEntry(
    snippet: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ ተራዳኢነት።',
    fullStory: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ ተራዳኢነት።',
  ),
  '3-16': SynaxariumEntry(
    snippet: 'የእመቤታችን የቃልኪዳን ወርሃዊ የምሕረት በዓል።',
    fullStory: 'የእመቤታችን የቃልኪዳን ወርሃዊ የምሕረት በዓል።',
  ),
  '3-17': SynaxariumEntry(
    snippet: 'የሊቀ ዲያቆናት የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የሊቀ ዲያቆናት የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
  ),
  '3-18': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ ኤዎስጣቴዎስ ወርሃዊ በረከት።',
    fullStory: 'የአባታችን የአቡነ ኤዎስጣቴዎስ ወርሃዊ በረከት።',
  ),
  '3-19': SynaxariumEntry(
    snippet: 'የቅዱስ ገብርኤል ወርሃዊ የጥበቃና የብስራት በዓል።',
    fullStory: 'የቅዱስ ገብርኤል ወርሃዊ የጥበቃና የብስራት በዓል።',
  ),
  '3-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ማኅበርና ጸሎት ማሰብ።',
    fullStory: 'የቅዱሳን ሁሉ ማኅበርና ጸሎት ማሰብ።',
  ),
  '3-21': SynaxariumEntry(
    snippet: 'ታቦተ ጽዮን ወደ አክሱም የገባችበትና እመቤታችን የሕያው ቃል ኪዳን ታቦት መሆኗ ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ታቦተ ጽዮን ወደ አክሱም የገባችበትና እመቤታችን የሕያው ቃል ኪዳን ታቦት መሆኗ ታላቅ ዓመታዊ በዓል።',
  ),
  '3-22': SynaxariumEntry(
    snippet: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያና ክብር።',
    fullStory: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያና ክብር።',
  ),
  '3-23': SynaxariumEntry(
    snippet: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ የቃልኪዳን በዓል።',
    fullStory: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ የቃልኪዳን በዓል።',
  ),
  '3-24': SynaxariumEntry(
    snippet: 'በሰማይ ዙፋን ዙሪያ የወርቅ ማዕጠንት ይዘው የሚቆሙ 24ቱ ካህናተ ሰማይ ዓመታዊ በዓል።',
    fullStory: 'በሰማይ ዙፋን ዙሪያ የወርቅ ማዕጠንት ይዘው የሚቆሙ 24ቱ ካህናተ ሰማይ ዓመታዊ በዓል።',
  ),
  '3-25': SynaxariumEntry(
    snippet: 'የሰማዕቱ የቅዱስ መርቆሬዎስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የሰማዕቱ የቅዱስ መርቆሬዎስ ወርሃዊ መታሰቢያ።',
  ),
  '3-26': SynaxariumEntry(
    snippet: 'የሐዋርያው የቅዱስ ቶማስ ወርሃዊ ተጋድሎ ማሰብ።',
    fullStory: 'የሐዋርያው የቅዱስ ቶማስ ወርሃዊ ተጋድሎ ማሰብ።',
  ),
  '3-27': SynaxariumEntry(
    snippet: 'የመድኃኔዓለም ወርሃዊ የይቅርታና የምሕረት በዓል።',
    fullStory: 'የመድኃኔዓለም ወርሃዊ የይቅርታና የምሕረት በዓል።',
  ),
  '3-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
  ),
  '3-29': SynaxariumEntry(
    snippet: 'የታላቁ ሰማዕት የቅዱስ መርቆሬዎስ ዓመታዊ የዕረፍትና የሰማዕትነት በዓል።',
    fullStory: 'የታላቁ ሰማዕት የቅዱስ መርቆሬዎስ ዓመታዊ የዕረፍትና የሰማዕትነት በዓል።',
  ),
  '3-30': SynaxariumEntry(
    snippet: 'የወንጌላዊው የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የወንጌላዊው የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
  ),
  '4-1': SynaxariumEntry(
    snippet: 'የእመቤታችን የልደት ወርሃዊ ምስጋና።',
    fullStory: 'የእመቤታችን የልደት ወርሃዊ ምስጋና።',
  ),
  '4-2': SynaxariumEntry(
    snippet: 'የቅዱስ ታዴዎስ ወርሃዊ የሐዋርያነት ክብር።',
    fullStory: 'የቅዱስ ታዴዎስ ወርሃዊ የሐዋርያነት ክብር።',
  ),
  '4-3': SynaxariumEntry(
    snippet: 'እመቤታችን በሦስት ዓመቷ ወደ ቤተ መቅደስ የገባችበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'እመቤታችን በሦስት ዓመቷ ወደ ቤተ መቅደስ የገባችበት ታላቅ ዓመታዊ በዓል።',
  ),
  '4-4': SynaxariumEntry(
    snippet: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
    fullStory: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
  ),
  '4-5': SynaxariumEntry(
    snippet: 'የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ ጸሎት ማሰብ።',
    fullStory: 'የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ ጸሎት ማሰብ።',
  ),
  '4-6': SynaxariumEntry(
    snippet: 'የእመቤታችንና የልጇ የቁስቋም ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችንና የልጇ የቁስቋም ወርሃዊ በዓል።',
  ),
  '4-7': SynaxariumEntry(
    snippet: 'የቅድስት ሥላሴ መለኮታዊ ክብር ምስጋና።',
    fullStory: 'የቅድስት ሥላሴ መለኮታዊ ክብር ምስጋና።',
  ),
  '4-8': SynaxariumEntry(
    snippet: 'የጻድቁ የአባ ኪሮስ ወርሃዊ የዕረፍት መታሰቢያ።',
    fullStory: 'የጻድቁ የአባ ኪሮስ ወርሃዊ የዕረፍት መታሰቢያ።',
  ),
  '4-9': SynaxariumEntry(
    snippet: 'የኒቅያ አባቶች የሃይማኖት ውሳኔ ማሰብ።',
    fullStory: 'የኒቅያ አባቶች የሃይማኖት ውሳኔ ማሰብ።',
  ),
  '4-10': SynaxariumEntry(
    snippet: 'የክርስቶስ ክቡር መስቀል ወርሃዊ በዓል።',
    fullStory: 'የክርስቶስ ክቡር መስቀል ወርሃዊ በዓል።',
  ),
  '4-11': SynaxariumEntry(
    snippet: 'የእመቤታችን ወላጆች ወርሃዊ መታሰቢያ።',
    fullStory: 'የእመቤታችን ወላጆች ወርሃዊ መታሰቢያ።',
  ),
  '4-12': SynaxariumEntry(
    snippet: 'የቅዱስ ሚካኤል ወርሃዊ የረዳትነት በዓል።',
    fullStory: 'የቅዱስ ሚካኤል ወርሃዊ የረዳትነት በዓል።',
  ),
  '4-13': SynaxariumEntry(
    snippet: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ምስጋና።',
    fullStory: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ምስጋና።',
  ),
  '4-14': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
    fullStory: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
  ),
  '4-15': SynaxariumEntry(
    snippet: 'የቅዱስ ቂርቆስ ወርሃዊ የሕፃናት ጠባቂነት።',
    fullStory: 'የቅዱስ ቂርቆስ ወርሃዊ የሕፃናት ጠባቂነት።',
  ),
  '4-16': SynaxariumEntry(
    snippet: 'የእመቤታችን የቃልኪዳን ወርሃዊ ምስጋና።',
    fullStory: 'የእመቤታችን የቃልኪዳን ወርሃዊ ምስጋና።',
  ),
  '4-17': SynaxariumEntry(
    snippet: 'የቅዱስ እስጢፋኖስ ወርሃዊ የዲያቆናት በዓል።',
    fullStory: 'የቅዱስ እስጢፋኖስ ወርሃዊ የዲያቆናት በዓል።',
  ),
  '4-18': SynaxariumEntry(
    snippet: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ የገድል ታሪክ።',
    fullStory: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ የገድል ታሪክ።',
  ),
  '4-19': SynaxariumEntry(
    snippet: 'የቁልቢው ቅዱስ ገብርኤል ታላቅና ታሪካዊ ዓመታዊ የቃልኪዳን በዓል።',
    fullStory: 'የቁልቢው ቅዱስ ገብርኤል ታላቅና ታሪካዊ ዓመታዊ የቃልኪዳን በዓል።',
  ),
  '4-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
  ),
  '4-21': SynaxariumEntry(
    snippet: 'የእመቤታችን የቅድስት ድንግል ማርያም ወርሃዊ ውዳሴ።',
    fullStory: 'የእመቤታችን የቅድስት ድንግል ማርያም ወርሃዊ ውዳሴ።',
  ),
  '4-22': SynaxariumEntry(
    snippet: 'መልአኩ ቅዱስ ገብርኤል ለእመቤታችን አምላክን እንደምትወልድ ያበሰረበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'መልአኩ ቅዱስ ገብርኤል ለእመቤታችን አምላክን እንደምትወልድ ያበሰረበት ታላቅ ዓመታዊ በዓል።',
  ),
  '4-23': SynaxariumEntry(
    snippet: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
    fullStory: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
  ),
  '4-24': SynaxariumEntry(
    snippet: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
    fullStory: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
  ),
  '4-25': SynaxariumEntry(
    snippet: 'የሰማዕቱ የቅዱስ መርቆሬዎስ ወርሃዊ ውዳሴ።',
    fullStory: 'የሰማዕቱ የቅዱስ መርቆሬዎስ ወርሃዊ ውዳሴ።',
  ),
  '4-26': SynaxariumEntry(
    snippet: 'የቅዱስ ቶማስ ወርሃዊ የሐዋርያነት ታሪክ።',
    fullStory: 'የቅዱስ ቶማስ ወርሃዊ የሐዋርያነት ታሪክ።',
  ),
  '4-27': SynaxariumEntry(
    snippet: 'የመድኃኔዓለም ወርሃዊ የስቅለት መታሰቢያ።',
    fullStory: 'የመድኃኔዓለም ወርሃዊ የስቅለት መታሰቢያ።',
  ),
  '4-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ምስጋና።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ምስጋና።',
  ),
  '4-29': SynaxariumEntry(
    snippet: 'ጌታችንና መድኃኒታችን ኢየሱስ ክርስቶስ በቤተልሔም በሥጋ የተወለደበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ጌታችንና መድኃኒታችን ኢየሱስ ክርስቶስ በቤተልሔም በሥጋ የተወለደበት ታላቅ ዓመታዊ በዓል።',
  ),
  '4-30': SynaxariumEntry(
    snippet: 'የቅዱስ ማርቆስ ወርሃዊ የወንጌል አገልግሎት።',
    fullStory: 'የቅዱስ ማርቆስ ወርሃዊ የወንጌል አገልግሎት።',
  ),
  '5-1': SynaxariumEntry(
    snippet: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
  ),
  '5-2': SynaxariumEntry(
    snippet: 'የቅዱስ ታዴዎስ ወርሃዊ የሰማዕትነት ክብር።',
    fullStory: 'የቅዱስ ታዴዎስ ወርሃዊ የሰማዕትነት ክብር።',
  ),
  '5-3': SynaxariumEntry(
    snippet: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ መታሰቢያ።',
    fullStory: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ መታሰቢያ።',
  ),
  '5-4': SynaxariumEntry(
    snippet: 'የፍቅር ሐዋርያና ወንጌላዊው ቅዱስ ዮሐንስ በሰላም ተሰውሮ ያረፈበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'የፍቅር ሐዋርያና ወንጌላዊው ቅዱስ ዮሐንስ በሰላም ተሰውሮ ያረፈበት ታላቅ ዓመታዊ በዓል።',
  ),
  '5-5': SynaxariumEntry(
    snippet: 'የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ ተጋድሎ።',
    fullStory: 'የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ ተጋድሎ።',
  ),
  '5-6': SynaxariumEntry(
    snippet: 'የቅድስት ቤተሰብ የስደት ወርሃዊ በዓል።',
    fullStory: 'የቅድስት ቤተሰብ የስደት ወርሃዊ በዓል።',
  ),
  '5-7': SynaxariumEntry(
    snippet: 'ሥላሴ በአብርሃም ቤት ተገኝተው በረከትንና ልጅን የሰጡበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ሥላሴ በአብርሃም ቤት ተገኝተው በረከትንና ልጅን የሰጡበት ታላቅ ዓመታዊ በዓል።',
  ),
  '5-8': SynaxariumEntry(
    snippet: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
  ),
  '5-9': SynaxariumEntry(
    snippet: 'የ318ቱ የኒቅያ ሊቃውንት ወርሃዊ ክብር።',
    fullStory: 'የ318ቱ የኒቅያ ሊቃውንት ወርሃዊ ክብር።',
  ),
  '5-10': SynaxariumEntry(
    snippet: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
    fullStory: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
  ),
  '5-11': SynaxariumEntry(
    snippet: 'ጌታችን በዮርዳኖስ ወንዝ በዮሐንስ እጅ የተጠመቀበትና ምስጢረ ሥላሴ የተገለጠበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ጌታችን በዮርዳኖስ ወንዝ በዮሐንስ እጅ የተጠመቀበትና ምስጢረ ሥላሴ የተገለጠበት ታላቅ ዓመታዊ በዓል።',
  ),
  '5-12': SynaxariumEntry(
    snippet: 'ጌታችን ውሃውን ወደ ወይን የለወጠበት የመጀመሪያው ተአምርና የቅዱስ ሚካኤል ጥበቃ ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ጌታችን ውሃውን ወደ ወይን የለወጠበት የመጀመሪያው ተአምርና የቅዱስ ሚካኤል ጥበቃ ታላቅ ዓመታዊ በዓል።',
  ),
  '5-13': SynaxariumEntry(
    snippet: 'ለእግዚአብሔር አብ የሚቀርብ የወርሃዊ ቅዳሴ።',
    fullStory: 'ለእግዚአብሔር አብ የሚቀርብ የወርሃዊ ቅዳሴ።',
  ),
  '5-14': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ ተአምራት።',
    fullStory: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ ተአምራት።',
  ),
  '5-15': SynaxariumEntry(
    snippet: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ ረድኤት።',
    fullStory: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ ረድኤት።',
  ),
  '5-16': SynaxariumEntry(
    snippet: 'የእመቤታችን የቃልኪዳን ወርሃዊ በረከት።',
    fullStory: 'የእመቤታችን የቃልኪዳን ወርሃዊ በረከት።',
  ),
  '5-17': SynaxariumEntry(
    snippet: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
  ),
  '5-18': SynaxariumEntry(
    snippet: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ የቅድስና ገድል።',
    fullStory: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ የቅድስና ገድል።',
  ),
  '5-19': SynaxariumEntry(
    snippet: 'የቅዱስ ገብርኤል ወርሃዊ የብስራት በዓል።',
    fullStory: 'የቅዱስ ገብርኤል ወርሃዊ የብስራት በዓል።',
  ),
  '5-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ማኅበርና ጸሎት ማሰብ።',
    fullStory: 'የቅዱሳን ሁሉ ማኅበርና ጸሎት ማሰብ።',
  ),
  '5-21': SynaxariumEntry(
    snippet: 'የእመቤታችን የቅድስት ድንግል ማርያም የዕረፍት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'የእመቤታችን የቅድስት ድንግል ማርያም የዕረፍት ታላቅ ዓመታዊ በዓል።',
  ),
  '5-22': SynaxariumEntry(
    snippet: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
  ),
  '5-23': SynaxariumEntry(
    snippet: 'የቅዱስ ጊዮርጊስ ክቡር ዓጽም ወደ ልዳ የፈለሰበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'የቅዱስ ጊዮርጊስ ክቡር ዓጽም ወደ ልዳ የፈለሰበት ታላቅ ዓመታዊ በዓል።',
  ),
  '5-24': SynaxariumEntry(
    snippet: 'የአቡነ ተክለ ሃይማኖት ወርሃዊ ገድል።',
    fullStory: 'የአቡነ ተክለ ሃይማኖት ወርሃዊ ገድል።',
  ),
  '5-25': SynaxariumEntry(
    snippet: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
    fullStory: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
  ),
  '5-26': SynaxariumEntry(
    snippet: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
  ),
  '5-27': SynaxariumEntry(
    snippet: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
    fullStory: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
  ),
  '5-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
  ),
  '5-29': SynaxariumEntry(
    snippet: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
    fullStory: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
  ),
  '5-30': SynaxariumEntry(
    snippet: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
  ),
  '6-1': SynaxariumEntry(
    snippet: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
  ),
  '6-2': SynaxariumEntry(
    snippet: 'የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
  ),
  '6-3': SynaxariumEntry(
    snippet: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
  ),
  '6-4': SynaxariumEntry(
    snippet: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
    fullStory: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
  ),
  '6-5': SynaxariumEntry(
    snippet: 'የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ ረድኤት።',
    fullStory: 'የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ ረድኤት።',
  ),
  '6-6': SynaxariumEntry(
    snippet: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
  ),
  '6-7': SynaxariumEntry(
    snippet: 'የቅድስት ሥላሴ መለኮታዊ ምስጋና።',
    fullStory: 'የቅድስት ሥላሴ መለኮታዊ ምስጋና።',
  ),
  '6-8': SynaxariumEntry(
    snippet: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
  ),
  '6-9': SynaxariumEntry(
    snippet: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
    fullStory: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
  ),
  '6-10': SynaxariumEntry(
    snippet: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
    fullStory: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
  ),
  '6-11': SynaxariumEntry(
    snippet: 'ታላቁ መኮንን ቅዱስ ፋሲለደስ ስለ ክርስቶስ እምነት ሰማዕት የሆነበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ታላቁ መኮንን ቅዱስ ፋሲለደስ ስለ ክርስቶስ እምነት ሰማዕት የሆነበት ታላቅ ዓመታዊ በዓል።',
  ),
  '6-12': SynaxariumEntry(
    snippet: 'የቅዱስ ሚካኤል ወርሃዊ የጥበቃ በዓል።',
    fullStory: 'የቅዱስ ሚካኤል ወርሃዊ የጥበቃ በዓል።',
  ),
  '6-13': SynaxariumEntry(
    snippet: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ጸሎት።',
    fullStory: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ጸሎት።',
  ),
  '6-14': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
    fullStory: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
  ),
  '6-15': SynaxariumEntry(
    snippet: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
  ),
  '6-16': SynaxariumEntry(
    snippet: 'እመቤታችን ከልጇ ታላቅ የይቅርታና የምሕረት ቃልኪዳን የተቀበለችበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'እመቤታችን ከልጇ ታላቅ የይቅርታና የምሕረት ቃልኪዳን የተቀበለችበት ታላቅ ዓመታዊ በዓል።',
  ),
  '6-17': SynaxariumEntry(
    snippet: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
  ),
  '6-18': SynaxariumEntry(
    snippet: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ ገድል።',
    fullStory: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ ገድል።',
  ),
  '6-19': SynaxariumEntry(
    snippet: 'የቅዱስ ገብርኤል ወርሃዊ የረዳትነት በዓል።',
    fullStory: 'የቅዱስ ገብርኤል ወርሃዊ የረዳትነት በዓል።',
  ),
  '6-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
  ),
  '6-21': SynaxariumEntry(
    snippet: 'የእመቤታችን የቅድስት ድንግል ማርያም ወርሃዊ ውዳሴ።',
    fullStory: 'የእመቤታችን የቅድስት ድንግል ማርያም ወርሃዊ ውዳሴ።',
  ),
  '6-22': SynaxariumEntry(
    snippet: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
  ),
  '6-23': SynaxariumEntry(
    snippet: 'ቅዱስ ጊዮርጊስ በረዳትነት የተገለጠበትና ታላቁ የዓድዋ ድል የተገኘበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ቅዱስ ጊዮርጊስ በረዳትነት የተገለጠበትና ታላቁ የዓድዋ ድል የተገኘበት ታላቅ ዓመታዊ በዓል።',
  ),
  '6-24': SynaxariumEntry(
    snippet: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
    fullStory: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
  ),
  '6-25': SynaxariumEntry(
    snippet: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
    fullStory: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
  ),
  '6-26': SynaxariumEntry(
    snippet: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
  ),
  '6-27': SynaxariumEntry(
    snippet: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
    fullStory: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
  ),
  '6-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
  ),
  '6-29': SynaxariumEntry(
    snippet: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
    fullStory: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
  ),
  '6-30': SynaxariumEntry(
    snippet: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
  ),
  '7-1': SynaxariumEntry(
    snippet: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
  ),
  '7-2': SynaxariumEntry(
    snippet: 'የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
  ),
  '7-3': SynaxariumEntry(
    snippet: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
  ),
  '7-4': SynaxariumEntry(
    snippet: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
    fullStory: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
  ),
  '7-5': SynaxariumEntry(
    snippet: 'የታላቁ ጻድቅ አባታችን የአቡነ ገብረ መንፈስ ቅዱስ ታላቅ ዓመታዊ የዕረፍት በዓል።',
    fullStory: 'የታላቁ ጻድቅ አባታችን የአቡነ ገብረ መንፈስ ቅዱስ ታላቅ ዓመታዊ የዕረፍት በዓል።',
  ),
  '7-6': SynaxariumEntry(
    snippet: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
  ),
  '7-7': SynaxariumEntry(
    snippet: 'የቅድስት ሥላሴ መለኮታዊ ምስጋና።',
    fullStory: 'የቅድስት ሥላሴ መለኮታዊ ምስጋና።',
  ),
  '7-8': SynaxariumEntry(
    snippet: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
  ),
  '7-9': SynaxariumEntry(
    snippet: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
    fullStory: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
  ),
  '7-10': SynaxariumEntry(
    snippet: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
    fullStory: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
  ),
  '7-11': SynaxariumEntry(
    snippet: 'የእመቤታችን ወላጆች ወርሃዊ መታሰቢያ።',
    fullStory: 'የእመቤታችን ወላጆች ወርሃዊ መታሰቢያ።',
  ),
  '7-12': SynaxariumEntry(
    snippet: 'የቅዱስ ሚካኤል ወርሃዊ የጥበቃ በዓል።',
    fullStory: 'የቅዱስ ሚካኤል ወርሃዊ የጥበቃ በዓል።',
  ),
  '7-13': SynaxariumEntry(
    snippet: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ጸሎት።',
    fullStory: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ጸሎት።',
  ),
  '7-14': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
    fullStory: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
  ),
  '7-15': SynaxariumEntry(
    snippet: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
  ),
  '7-16': SynaxariumEntry(
    snippet: 'የእመቤታችን የቃልኪዳን ወርሃዊ በረከት።',
    fullStory: 'የእመቤታችን የቃልኪዳን ወርሃዊ በረከት።',
  ),
  '7-17': SynaxariumEntry(
    snippet: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
  ),
  '7-18': SynaxariumEntry(
    snippet: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ ገድል።',
    fullStory: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ ገድል።',
  ),
  '7-19': SynaxariumEntry(
    snippet: 'የቅዱስ ገብርኤል ወርሃዊ የረዳትነት በዓል።',
    fullStory: 'የቅዱስ ገብርኤል ወርሃዊ የረዳትነት በዓል።',
  ),
  '7-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
  ),
  '7-21': SynaxariumEntry(
    snippet: 'የእመቤታችን የቅድስት ድንግል ማርያም ወርሃዊ ውዳሴ።',
    fullStory: 'የእመቤታችን የቅድስት ድንግል ማርያም ወርሃዊ ውዳሴ።',
  ),
  '7-22': SynaxariumEntry(
    snippet: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
  ),
  '7-23': SynaxariumEntry(
    snippet: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
    fullStory: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
  ),
  '7-24': SynaxariumEntry(
    snippet: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
    fullStory: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
  ),
  '7-25': SynaxariumEntry(
    snippet: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
    fullStory: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
  ),
  '7-26': SynaxariumEntry(
    snippet: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
  ),
  '7-27': SynaxariumEntry(
    snippet: 'ጌታችን ስለ አዳምና ስለ ልጆቹ በጎልጎታ የተሰቀለበት ታላቅ ዓመታዊ ዕለት።',
    fullStory: 'ጌታችን ስለ አዳምና ስለ ልጆቹ በጎልጎታ የተሰቀለበት ታላቅ ዓመታዊ ዕለት።',
  ),
  '7-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
  ),
  '7-29': SynaxariumEntry(
    snippet: 'መልአኩ ቅዱስ ገብርኤል እመቤታችንን አምላክን እንደምትወልድ ያበሰረበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'መልአኩ ቅዱስ ገብርኤል እመቤታችንን አምላክን እንደምትወልድ ያበሰረበት ታላቅ ዓመታዊ በዓል።',
  ),
  '7-30': SynaxariumEntry(
    snippet: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
  ),
  '8-1': SynaxariumEntry(
    snippet: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
  ),
  '8-2': SynaxariumEntry(
    snippet: 'የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
  ),
  '8-3': SynaxariumEntry(
    snippet: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
  ),
  '8-4': SynaxariumEntry(
    snippet: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
    fullStory: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
  ),
  '8-5': SynaxariumEntry(
    snippet: 'ቅዱስ ዮሐንስ አፈወርቅ ስለ እውነት በመቆሙ ምክንያት በግዞት ያረፈበት ታላቅ መታሰቢያ።',
    fullStory: 'ቅዱስ ዮሐንስ አፈወርቅ ስለ እውነት በመቆሙ ምክንያት በግዞት ያረፈበት ታላቅ መታሰቢያ።',
  ),
  '8-6': SynaxariumEntry(
    snippet: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
  ),
  '8-7': SynaxariumEntry(
    snippet: 'የቅድስት ሥላሴ መለኮታዊ ምስጋና።',
    fullStory: 'የቅድስት ሥላሴ መለኮታዊ ምስጋና።',
  ),
  '8-8': SynaxariumEntry(
    snippet: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
  ),
  '8-9': SynaxariumEntry(
    snippet: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
    fullStory: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
  ),
  '8-10': SynaxariumEntry(
    snippet: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
    fullStory: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
  ),
  '8-11': SynaxariumEntry(
    snippet: 'የእመቤታችን ወላጆች ወርሃዊ መታሰቢያ።',
    fullStory: 'የእመቤታችን ወላጆች ወርሃዊ መታሰቢያ።',
  ),
  '8-12': SynaxariumEntry(
    snippet: 'የቅዱስ ሚካኤል ወርሃዊ የጥበቃ በዓል።',
    fullStory: 'የቅዱስ ሚካኤል ወርሃዊ የጥበቃ በዓል።',
  ),
  '8-13': SynaxariumEntry(
    snippet: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ጸሎት።',
    fullStory: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ጸሎት።',
  ),
  '8-14': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
    fullStory: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
  ),
  '8-15': SynaxariumEntry(
    snippet: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
  ),
  '8-16': SynaxariumEntry(
    snippet: 'የእመቤታችን የቃልኪዳን ወርሃዊ በረከት።',
    fullStory: 'የእመቤታችን የቃልኪዳን ወርሃዊ በረከት።',
  ),
  '8-17': SynaxariumEntry(
    snippet: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
  ),
  '8-18': SynaxariumEntry(
    snippet: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ ገድል።',
    fullStory: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ ገድል።',
  ),
  '8-19': SynaxariumEntry(
    snippet: 'የቅዱስ ገብርኤል ወርሃዊ የረዳትነት በዓል።',
    fullStory: 'የቅዱስ ገብርኤል ወርሃዊ የረዳትነት በዓል።',
  ),
  '8-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
  ),
  '8-21': SynaxariumEntry(
    snippet: 'ማርያም ግብፃዊት ቀድሞ ኃጢአተኛ የነበረችና በበረሃ 47 ዓመት በንሥሐ የኖረች ታላቅ ጻድቅ ናት።',
    fullStory: 'ማርያም ግብፃዊት ቀድሞ ኃጢአተኛ የነበረችና በበረሃ 47 ዓመት በንሥሐ የኖረች ታላቅ ጻድቅ ናት።',
  ),
  '8-22': SynaxariumEntry(
    snippet: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
  ),
  '8-23': SynaxariumEntry(
    snippet: 'ቅዱስ ጊዮርጊስ ለሰባት ዓመታት መከራን ታግሦ በሰይፍ የተሰየመበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ቅዱስ ጊዮርጊስ ለሰባት ዓመታት መከራን ታግሦ በሰይፍ የተሰየመበት ታላቅ ዓመታዊ በዓል።',
  ),
  '8-24': SynaxariumEntry(
    snippet: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
    fullStory: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
  ),
  '8-25': SynaxariumEntry(
    snippet: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
    fullStory: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
  ),
  '8-26': SynaxariumEntry(
    snippet: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
  ),
  '8-27': SynaxariumEntry(
    snippet: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
    fullStory: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
  ),
  '8-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
  ),
  '8-29': SynaxariumEntry(
    snippet: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
    fullStory: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
  ),
  '8-30': SynaxariumEntry(
    snippet: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
  ),
  '9-1': SynaxariumEntry(
    snippet: 'የእመቤታችን የቅድስት ድንግል ማርያም ታላቅ ወርሃዊ የልደት በዓል።',
    fullStory: 'የእመቤታችን የቅድስት ድንግል ማርያም ታላቅ ወርሃዊ የልደት በዓል።',
  ),
  '9-2': SynaxariumEntry(
    snippet: 'የቅዱስ ታዴዎስ ሐዋርያ ወርሃዊ የሰማዕትነት ክብር።',
    fullStory: 'የቅዱስ ታዴዎስ ሐዋርያ ወርሃዊ የሰማዕትነት ክብር።',
  ),
  '9-3': SynaxariumEntry(
    snippet: 'የእመቤታችን ወደ ቤተ መቅደስ መግባት ወርሃዊ መታሰቢያ።',
    fullStory: 'የእመቤታችን ወደ ቤተ መቅደስ መግባት ወርሃዊ መታሰቢያ።',
  ),
  '9-4': SynaxariumEntry(
    snippet: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብርና ውዳሴ።',
    fullStory: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብርና ውዳሴ።',
  ),
  '9-5': SynaxariumEntry(
    snippet: 'የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ የረድኤት በዓል።',
    fullStory: 'የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ የረድኤት በዓል።',
  ),
  '9-6': SynaxariumEntry(
    snippet: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
  ),
  '9-7': SynaxariumEntry(
    snippet: 'የቅድስት ሥላሴ መለኮታዊ ክብር ምስጋና።',
    fullStory: 'የቅድስት ሥላሴ መለኮታዊ ክብር ምስጋና።',
  ),
  '9-8': SynaxariumEntry(
    snippet: 'የጻድቁ አባ ኪሮስ ወርሃዊ የዕረፍት መታሰቢያ።',
    fullStory: 'የጻድቁ አባ ኪሮስ ወርሃዊ የዕረፍት መታሰቢያ።',
  ),
  '9-9': SynaxariumEntry(
    snippet: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
    fullStory: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
  ),
  '9-10': SynaxariumEntry(
    snippet: 'የክርስቶስ ክቡር መስቀል ወርሃዊ በዓልና ምስጋና።',
    fullStory: 'የክርስቶስ ክቡር መስቀል ወርሃዊ በዓልና ምስጋና።',
  ),
  '9-11': SynaxariumEntry(
    snippet: 'የኢትዮጵያ ሰማያዊ ዜማ ደራሲ ቅዱስ ያሬድ የተሰወረበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'የኢትዮጵያ ሰማያዊ ዜማ ደራሲ ቅዱስ ያሬድ የተሰወረበት ታላቅ ዓመታዊ በዓል።',
  ),
  '9-12': SynaxariumEntry(
    snippet: 'የጻድቁ አባታችን የአቡነ ተክለ ሃይማኖት ክቡር ዓጽም የፈለሰበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'የጻድቁ አባታችን የአቡነ ተክለ ሃይማኖት ክቡር ዓጽም የፈለሰበት ታላቅ ዓመታዊ በዓል።',
  ),
  '9-13': SynaxariumEntry(
    snippet: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ምስጋና።',
    fullStory: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ምስጋና።',
  ),
  '9-14': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
    fullStory: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
  ),
  '9-15': SynaxariumEntry(
    snippet: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
  ),
  '9-16': SynaxariumEntry(
    snippet: 'የእመቤታችን የቃልኪዳን ወርሃዊ የምሕረት በዓል።',
    fullStory: 'የእመቤታችን የቃልኪዳን ወርሃዊ የምሕረት በዓል።',
  ),
  '9-17': SynaxariumEntry(
    snippet: 'የቅዱስ እስጢፋኖስ ወርሃዊ የሰማዕትነት ክብር።',
    fullStory: 'የቅዱስ እስጢፋኖስ ወርሃዊ የሰማዕትነት ክብር።',
  ),
  '9-18': SynaxariumEntry(
    snippet: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ የገድል ታሪክ።',
    fullStory: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ የገድል ታሪክ።',
  ),
  '9-19': SynaxariumEntry(
    snippet: 'የቅዱስ ገብርኤል ወርሃዊ የረዳትነት በዓል።',
    fullStory: 'የቅዱስ ገብርኤል ወርሃዊ የረዳትነት በዓል።',
  ),
  '9-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
  ),
  '9-21': SynaxariumEntry(
    snippet: 'እመቤታችን በግብፅ ደብረ ምጥማቅ በብርሃን ተገልጣ ለብዙ ቀናት የታየችበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'እመቤታችን በግብፅ ደብረ ምጥማቅ በብርሃን ተገልጣ ለብዙ ቀናት የታየችበት ታላቅ ዓመታዊ በዓል።',
  ),
  '9-22': SynaxariumEntry(
    snippet: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያና ክብር።',
    fullStory: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያና ክብር።',
  ),
  '9-23': SynaxariumEntry(
    snippet: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
    fullStory: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
  ),
  '9-24': SynaxariumEntry(
    snippet: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
    fullStory: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
  ),
  '9-25': SynaxariumEntry(
    snippet: 'የቅዱስ መርቆሬዎስ ወርሃዊ ውዳሴ።',
    fullStory: 'የቅዱስ መርቆሬዎስ ወርሃዊ ውዳሴ።',
  ),
  '9-26': SynaxariumEntry(
    snippet: 'የቅዱስ ቶማስ ወርሃዊ የሐዋርያነት ታሪክ።',
    fullStory: 'የቅዱስ ቶማስ ወርሃዊ የሐዋርያነት ታሪክ።',
  ),
  '9-27': SynaxariumEntry(
    snippet: 'የመድኃኔዓለም ወርሃዊ የስቅለት መታሰቢያ።',
    fullStory: 'የመድኃኔዓለም ወርሃዊ የስቅለት መታሰቢያ።',
  ),
  '9-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ምስጋና።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ምስጋና።',
  ),
  '9-29': SynaxariumEntry(
    snippet: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
    fullStory: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
  ),
  '9-30': SynaxariumEntry(
    snippet: 'የቅዱስ ማርቆስ ወርሃዊ የወንጌል አገልግሎት።',
    fullStory: 'የቅዱስ ማርቆስ ወርሃዊ የወንጌል አገልግሎት።',
  ),
  '10-1': SynaxariumEntry(
    snippet: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
  ),
  '10-2': SynaxariumEntry(
    snippet: 'የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
  ),
  '10-3': SynaxariumEntry(
    snippet: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
  ),
  '10-4': SynaxariumEntry(
    snippet: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
    fullStory: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
  ),
  '10-5': SynaxariumEntry(
    snippet: 'የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ ረድኤት።',
    fullStory: 'የአቡነ ገብረ መንፈስ ቅዱስ ወርሃዊ ረድኤት።',
  ),
  '10-6': SynaxariumEntry(
    snippet: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
  ),
  '10-7': SynaxariumEntry(
    snippet: 'የቅድስት ሥላሴ መለኮታዊ ምስጋና።',
    fullStory: 'የቅድስት ሥላሴ መለኮታዊ ምስጋና።',
  ),
  '10-8': SynaxariumEntry(
    snippet: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
  ),
  '10-9': SynaxariumEntry(
    snippet: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
    fullStory: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
  ),
  '10-10': SynaxariumEntry(
    snippet: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
    fullStory: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
  ),
  '10-11': SynaxariumEntry(
    snippet: 'የእመቤታችን ወላጆች ወርሃዊ መታሰቢያ።',
    fullStory: 'የእመቤታችን ወላጆች ወርሃዊ መታሰቢያ።',
  ),
  '10-12': SynaxariumEntry(
    snippet: 'ሰኔ ሚካኤል የቅዱስ ሚካኤል ዓመታዊ በዓልና አብያተ ክርስቲያናትን ያነጸው የጻድቁ ንጉሥ ላሊበላ ዕረፍት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ሰኔ ሚካኤል የቅዱስ ሚካኤል ዓመታዊ በዓልና አብያተ ክርስቲያናትን ያነጸው የጻድቁ ንጉሥ ላሊበላ ዕረፍት ታላቅ ዓመታዊ በዓል።',
  ),
  '10-13': SynaxariumEntry(
    snippet: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ጸሎት።',
    fullStory: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ጸሎት።',
  ),
  '10-14': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
    fullStory: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
  ),
  '10-15': SynaxariumEntry(
    snippet: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
  ),
  '10-16': SynaxariumEntry(
    snippet: 'የእመቤታችን የቃልኪዳን ወርሃዊ በረከት።',
    fullStory: 'የእመቤታችን የቃልኪዳን ወርሃዊ በረከት።',
  ),
  '10-17': SynaxariumEntry(
    snippet: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
  ),
  '10-18': SynaxariumEntry(
    snippet: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ ገድል።',
    fullStory: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ ገድል።',
  ),
  '10-19': SynaxariumEntry(
    snippet: 'የቅዱስ ገብርኤል ወርሃዊ የረዳትነት በዓል።',
    fullStory: 'የቅዱስ ገብርኤል ወርሃዊ የረዳትነት በዓል።',
  ),
  '10-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
  ),
  '10-21': SynaxariumEntry(
    snippet: 'ጌታችን ለእመቤታችን በጎልጎታ ታላቅና ታሪካዊ የይቅርታ ቃልኪዳን የሰጣት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ጌታችን ለእመቤታችን በጎልጎታ ታላቅና ታሪካዊ የይቅርታ ቃልኪዳን የሰጣት ታላቅ ዓመታዊ በዓል።',
  ),
  '10-22': SynaxariumEntry(
    snippet: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
  ),
  '10-23': SynaxariumEntry(
    snippet: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
    fullStory: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
  ),
  '10-24': SynaxariumEntry(
    snippet: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
    fullStory: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
  ),
  '10-25': SynaxariumEntry(
    snippet: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
    fullStory: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
  ),
  '10-26': SynaxariumEntry(
    snippet: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
  ),
  '10-27': SynaxariumEntry(
    snippet: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
    fullStory: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
  ),
  '10-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
  ),
  '10-29': SynaxariumEntry(
    snippet: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
    fullStory: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
  ),
  '10-30': SynaxariumEntry(
    snippet: 'የመጥምቁ ቅዱስ ዮሐንስ መጥምቅ የተወለደበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'የመጥምቁ ቅዱስ ዮሐንስ መጥምቅ የተወለደበት ታላቅ ዓመታዊ በዓል።',
  ),
  '11-1': SynaxariumEntry(
    snippet: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን የልደት ወርሃዊ በዓል።',
  ),
  '11-2': SynaxariumEntry(
    snippet: 'የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ታዴዎስ ወርሃዊ መታሰቢያ።',
  ),
  '11-3': SynaxariumEntry(
    snippet: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
    fullStory: 'የእመቤታችን ወደ መቅደስ መግባት ወርሃዊ በዓል።',
  ),
  '11-4': SynaxariumEntry(
    snippet: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
    fullStory: 'የቅዱስ ዮሐንስ ወንጌላዊ ወርሃዊ ክብር።',
  ),
  '11-5': SynaxariumEntry(
    snippet: 'የሐዋርያት አለቆች በሮም ምድር በሰማዕትነት ያረፉበት ታላቅ ዕለት።',
    fullStory: 'የሐዋርያት አለቆች በሮም ምድር በሰማዕትነት ያረፉበት ታላቅ ዕለት።',
  ),
  '11-6': SynaxariumEntry(
    snippet: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅድስት ቤተሰብ የስደት ወርሃዊ መታሰቢያ።',
  ),
  '11-7': SynaxariumEntry(
    snippet: 'የቅድስት ሥላሴ መለኮታዊ ምስጋና።',
    fullStory: 'የቅድስት ሥላሴ መለኮታዊ ምስጋና።',
  ),
  '11-8': SynaxariumEntry(
    snippet: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የጻድቁ አባ ኪሮስ ወርሃዊ መታሰቢያ።',
  ),
  '11-9': SynaxariumEntry(
    snippet: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
    fullStory: 'የ318ቱ የኒቅያ አባቶች ወርሃዊ ክብር።',
  ),
  '11-10': SynaxariumEntry(
    snippet: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
    fullStory: 'የክርስቶስ መስቀል ወርሃዊ ምስጋና።',
  ),
  '11-11': SynaxariumEntry(
    snippet: 'የእመቤታችን ወላጆች ወርሃዊ መታሰቢያ።',
    fullStory: 'የእመቤታችን ወላጆች ወርሃዊ መታሰቢያ።',
  ),
  '11-12': SynaxariumEntry(
    snippet: 'የቅዱስ ሚካኤል ወርሃዊ የጥበቃ በዓል።',
    fullStory: 'የቅዱስ ሚካኤል ወርሃዊ የጥበቃ በዓል።',
  ),
  '11-13': SynaxariumEntry(
    snippet: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ጸሎት።',
    fullStory: 'ለእግዚአብሔር አብ የሚቀርብ የቅዳሴ ጸሎት።',
  ),
  '11-14': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
    fullStory: 'የአባታችን የአቡነ አረጋዊ ወርሃዊ በረከት።',
  ),
  '11-15': SynaxariumEntry(
    snippet: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቂርቆስና የኢየሉጣ ወርሃዊ መታሰቢያ።',
  ),
  '11-16': SynaxariumEntry(
    snippet: 'የእመቤታችን የቃልኪዳን ወርሃዊ በረከት።',
    fullStory: 'የእመቤታችን የቃልኪዳን ወርሃዊ በረከት።',
  ),
  '11-17': SynaxariumEntry(
    snippet: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ እስጢፋኖስ ወርሃዊ መታሰቢያ።',
  ),
  '11-18': SynaxariumEntry(
    snippet: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ ገድል።',
    fullStory: 'የአቡነ ኤዎስጣቴዎስ ወርሃዊ ገድል።',
  ),
  '11-19': SynaxariumEntry(
    snippet: 'ቅዱስ ገብርኤል ሠለስቱ ደቂቅን ከሚነድ እሳት ያዳነበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ቅዱስ ገብርኤል ሠለስቱ ደቂቅን ከሚነድ እሳት ያዳነበት ታላቅ ዓመታዊ በዓል።',
  ),
  '11-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
  ),
  '11-21': SynaxariumEntry(
    snippet: 'የእመቤታችን የቅድስት ድንግል ማርያም ወርሃዊ ውዳሴ።',
    fullStory: 'የእመቤታችን የቅድስት ድንግል ማርያም ወርሃዊ ውዳሴ።',
  ),
  '11-22': SynaxariumEntry(
    snippet: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
  ),
  '11-23': SynaxariumEntry(
    snippet: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
    fullStory: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
  ),
  '11-24': SynaxariumEntry(
    snippet: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
    fullStory: 'የጻድቁ የአቡነ ተክለ ሃይማኖት ወርሃዊ ረድኤት።',
  ),
  '11-25': SynaxariumEntry(
    snippet: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
    fullStory: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
  ),
  '11-26': SynaxariumEntry(
    snippet: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
  ),
  '11-27': SynaxariumEntry(
    snippet: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
    fullStory: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
  ),
  '11-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
  ),
  '11-29': SynaxariumEntry(
    snippet: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
    fullStory: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
  ),
  '11-30': SynaxariumEntry(
    snippet: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
  ),
  '12-1': SynaxariumEntry(
    snippet: 'ጾመ ፍልሰታ መግቢያ፤ የእመቤታችንን ትንሣኤና ዕርገት ለማየት ሐዋርያት የጾሙት ጾም መታሰቢያ።',
    fullStory: 'ጾመ ፍልሰታ መግቢያ፤ የእመቤታችንን ትንሣኤና ዕርገት ለማየት ሐዋርያት የጾሙት ጾም መታሰቢያ።',
  ),
  '12-2': SynaxariumEntry(
    snippet: 'በጾመ ፍልሰታ ወቅት የቅዱስ ታዴዎስን ወርሃዊ ሐዋርያዊ አገልግሎት ማሰብ።',
    fullStory: 'በጾመ ፍልሰታ ወቅት የቅዱስ ታዴዎስን ወርሃዊ ሐዋርያዊ አገልግሎት ማሰብ።',
  ),
  '12-3': SynaxariumEntry(
    snippet: 'በጾመ ፍልሰታ ወቅት የእመቤታችንን ቤተ መቅደስ መግባት ማሰብ።',
    fullStory: 'በጾመ ፍልሰታ ወቅት የእመቤታችንን ቤተ መቅደስ መግባት ማሰብ።',
  ),
  '12-4': SynaxariumEntry(
    snippet: 'በጾመ ፍልሰታ ወቅት የቅዱስ ዮሐንስ ወንጌላዊ ረቂቅ ፍቅር ማሰብ።',
    fullStory: 'በጾመ ፍልሰታ ወቅት የቅዱስ ዮሐንስ ወንጌላዊ ረቂቅ ፍቅር ማሰብ።',
  ),
  '12-5': SynaxariumEntry(
    snippet: 'ጻድቁ አባታችን አቡነ ገብረ መንፈስ ቅዱስ በጾም የኖሩት ሕይወት ማሰብ።',
    fullStory: 'ጻድቁ አባታችን አቡነ ገብረ መንፈስ ቅዱስ በጾም የኖሩት ሕይወት ማሰብ።',
  ),
  '12-6': SynaxariumEntry(
    snippet: 'በጾመ ፍልሰታ ወቅት የቅድስት ቤተሰብን ረቂቅ ስደት ማሰብ።',
    fullStory: 'በጾመ ፍልሰታ ወቅት የቅድስት ቤተሰብን ረቂቅ ስደት ማሰብ።',
  ),
  '12-7': SynaxariumEntry(
    snippet: 'በጾም ወቅት ለቅድስት ሥላሴ የሚቀርብ ልዩ የአምልኮ ምስጋና።',
    fullStory: 'በጾም ወቅት ለቅድስት ሥላሴ የሚቀርብ ልዩ የአምልኮ ምስጋና።',
  ),
  '12-8': SynaxariumEntry(
    snippet: 'የጻድቁ የአባ ኪሮስን ታላቅ የገዳም ጾም በትሕትና ማሰብ።',
    fullStory: 'የጻድቁ የአባ ኪሮስን ታላቅ የገዳም ጾም በትሕትና ማሰብ።',
  ),
  '12-9': SynaxariumEntry(
    snippet: 'የ318ቱ ሊቃውንት የሃይማኖት ውሳኔዎችን በጾም ማሰብ።',
    fullStory: 'የ318ቱ ሊቃውንት የሃይማኖት ውሳኔዎችን በጾም ማሰብ።',
  ),
  '12-10': SynaxariumEntry(
    snippet: 'የጌታ መስቀል ለጾማችን ኃይልና መጽናኛ እንዲሆን ማሰብ።',
    fullStory: 'የጌታ መስቀል ለጾማችን ኃይልና መጽናኛ እንዲሆን ማሰብ።',
  ),
  '12-11': SynaxariumEntry(
    snippet: 'የእመቤታችን እናት የቅድስት ሐናን ጽኑ ጸሎት ማሰብ።',
    fullStory: 'የእመቤታችን እናት የቅድስት ሐናን ጽኑ ጸሎት ማሰብ።',
  ),
  '12-12': SynaxariumEntry(
    snippet: 'የሊቀ መላእክት የቅዱስ ሚካኤል ጥበቃ ለጾማችን ስኬት ማሰብ።',
    fullStory: 'የሊቀ መላእክት የቅዱስ ሚካኤል ጥበቃ ለጾማችን ስኬት ማሰብ።',
  ),
  '12-13': SynaxariumEntry(
    snippet: 'ጌታችን በታቦር ተራራ መለኮታዊ ክብሩንና ብርሃኑን የገለጠበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'ጌታችን በታቦር ተራራ መለኮታዊ ክብሩንና ብርሃኑን የገለጠበት ታላቅ ዓመታዊ በዓል።',
  ),
  '12-14': SynaxariumEntry(
    snippet: 'በጾመ ፍልሰታ ወቅት የአቡነ አረጋዊን ረድኤት ማሰብ።',
    fullStory: 'በጾመ ፍልሰታ ወቅት የአቡነ አረጋዊን ረድኤት ማሰብ።',
  ),
  '12-15': SynaxariumEntry(
    snippet: 'በጾም ወቅት የሕፃኑን ቂርቆስን የሰማዕትነት ጽናት ማሰብ።',
    fullStory: 'በጾም ወቅት የሕፃኑን ቂርቆስን የሰማዕትነት ጽናት ማሰብ።',
  ),
  '12-16': SynaxariumEntry(
    snippet: 'የእመቤታችን ቅዱስ ሥጋ ከፈረሰበት ተነሥቶ ወደ ሰማይ ያረገበት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'የእመቤታችን ቅዱስ ሥጋ ከፈረሰበት ተነሥቶ ወደ ሰማይ ያረገበት ታላቅ ዓመታዊ በዓል።',
  ),
  '12-17': SynaxariumEntry(
    snippet: 'የቅዱስ እስጢፋኖስ ወርሃዊ የዲያቆናት በዓል።',
    fullStory: 'የቅዱስ እስጢፋኖስ ወርሃዊ የዲያቆናት በዓል።',
  ),
  '12-18': SynaxariumEntry(
    snippet: 'የአባታችን የአቡነ ኤዎስጣቴዎስ ወርሃዊ በረከት።',
    fullStory: 'የአባታችን የአቡነ ኤዎስጣቴዎስ ወርሃዊ በረከት።',
  ),
  '12-19': SynaxariumEntry(
    snippet: 'የቅዱስ ገብርኤል ወርሃዊ የጥበቃና የብስራት በዓል።',
    fullStory: 'የቅዱስ ገብርኤል ወርሃዊ የጥበቃና የብስራት በዓል።',
  ),
  '12-20': SynaxariumEntry(
    snippet: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱሳን ሁሉ ወርሃዊ መታሰቢያ።',
  ),
  '12-21': SynaxariumEntry(
    snippet: 'የእመቤታችን የቅድስት ድንግል ማርያም ወርሃዊ ውዳሴ።',
    fullStory: 'የእመቤታችን የቅድስት ድንግል ማርያም ወርሃዊ ውዳሴ።',
  ),
  '12-22': SynaxariumEntry(
    snippet: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ደቅስዮስ ወርሃዊ መታሰቢያ።',
  ),
  '12-23': SynaxariumEntry(
    snippet: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
    fullStory: 'የሰማዕቱ የቅዱስ ጊዮርጊስ ወርሃዊ በዓል።',
  ),
  '12-24': SynaxariumEntry(
    snippet: 'የታላቁ አባታችን የኢትዮጵያ ብርሃን አቡነ ተክለሃይማኖት የዕረፍት ታላቅ ዓመታዊ በዓል።',
    fullStory: 'የታላቁ አባታችን የኢትዮጵያ ብርሃን አቡነ ተክለሃይማኖት የዕረፍት ታላቅ ዓመታዊ በዓል።',
  ),
  '12-25': SynaxariumEntry(
    snippet: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
    fullStory: 'የቅዱስ መርቆሬዎስ ወርሃዊ የድል በዓል።',
  ),
  '12-26': SynaxariumEntry(
    snippet: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ቶማስ ወርሃዊ መታሰቢያ።',
  ),
  '12-27': SynaxariumEntry(
    snippet: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
    fullStory: 'የመድኃኔዓለም ወርሃዊ የምሕረት በዓል።',
  ),
  '12-28': SynaxariumEntry(
    snippet: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
    fullStory: 'የጌታችን የአማኑኤል ወርሃዊ ውዳሴ።',
  ),
  '12-29': SynaxariumEntry(
    snippet: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
    fullStory: 'የእግዚአብሔር ወልድ መለኮታዊ ሥራዎች ማሰብ።',
  ),
  '12-30': SynaxariumEntry(
    snippet: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
    fullStory: 'የቅዱስ ማርቆስ ወርሃዊ መታሰቢያ።',
  ),
  '13-1': SynaxariumEntry(
    snippet: 'ቅዱስ ዑራኤል ለቅዱስ ዕዝራ የጥበብን ጽዋ ያጠጣበትና የጌታን ደም በአለም የረጨበት ታላቅ በዓል።',
    fullStory: 'ቅዱስ ዑራኤል ለቅዱስ ዕዝራ የጥበብን ጽዋ ያጠጣበትና የጌታን ደም በአለም የረጨበት ታላቅ በዓል።',
  ),
  '13-2': SynaxariumEntry(
    snippet: 'የቅዱስ አናንያል መላእክት ወርሃዊ መታሰቢያና ጥበቃ።',
    fullStory: 'የቅዱስ አናንያል መላእክት ወርሃዊ መታሰቢያና ጥበቃ።',
  ),
  '13-3': SynaxariumEntry(
    snippet: 'በዓሣ አንበሪ ላይ የተመሠረተችውን ቤተክርስቲያን ያጸናበትና የፈውስ መልአክ ታላቅ በዓል።',
    fullStory: 'በዓሣ አንበሪ ላይ የተመሠረተችውን ቤተክርስቲያን ያጸናበትና የፈውስ መልአክ ታላቅ በዓል።',
  ),
  '13-4': SynaxariumEntry(
    snippet: 'በሰማያት ያሉ መላእክት ሰራዊት ሁሉ በአንድነት ፈጣሪያቸውን የሚያመሰግኑበት ታላቅ ዕለት።',
    fullStory: 'በሰማያት ያሉ መላእክት ሰራዊት ሁሉ በአንድነት ፈጣሪያቸውን የሚያመሰግኑበት ታላቅ ዕለት።',
  ),
  '13-5': SynaxariumEntry(
    snippet: 'የጻድቁ ነቢዩ አሞጽ ዕረፍትና የተለመደው የዓመቱ የመጨረሻ መዝጊያ ቀን።',
    fullStory: 'የጻድቁ ነቢዩ አሞጽ ዕረፍትና የተለመደው የዓመቱ የመጨረሻ መዝጊያ ቀን።',
  ),
  '13-6': SynaxariumEntry(
    snippet: 'ይህች ቀን በየ4 ዓመቱ የምትመጣ ልዩ የ366ኛው ቀን የዘመን መተላለፊያ ናት፤ እግዚአብሔር ለአዲስ ዘመን ስላበቃን ታላቅ ምስጋና ይቀርባል።',
    fullStory: 'ይህች ቀን በየ4 ዓመቱ የምትመጣ ልዩ የ366ኛው ቀን የዘመን መተላለፊያ ናት፤ እግዚአብሔር ለአዲስ ዘመን ስላበቃን ታላቅ ምስጋና ይቀርባል።',
  ),
};


SynaxariumEntry? getSynaxarium(int month, int day) {
  return synaxariumStories['$month-$day'];
}

class EotcDay {
  final int month, day;
  final String name;
  final bool isAnnual;
  const EotcDay({required this.month, required this.day, required this.name, this.isAnnual = false});
}

EotcDay? getEotcDay(int month, int day) {
  try { return eotcCalendar.firstWhere((e) => e.month == month && e.day == day); }
  catch (e) { return null; }
}

List<EotcDay> getAnnualFeasts(int month) =>
    eotcCalendar.where((e) => e.month == month && e.isAnnual).toList();

const List<EotcDay> eotcCalendar = [
  EotcDay(month:1,day:1,name:'እንቁጣጣሽ / ቅዱስ ዮሐንስ',isAnnual:true),
  EotcDay(month:1,day:2,name:'ቅዱስ ዮሐንስ መጥምቅ ሰማዕትነት',isAnnual:true),
  EotcDay(month:1,day:3,name:'በዓታ ማርያም'),
  EotcDay(month:1,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ'),
  EotcDay(month:1,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ'),
  EotcDay(month:1,day:6,name:'ቁስቋም ማርያም'),
  EotcDay(month:1,day:7,name:'ቅድስት ሥላሴ'),
  EotcDay(month:1,day:8,name:'አባ ኪሮስ'),
  EotcDay(month:1,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:1,day:10,name:'ቅዱስ መስቀል'),
  EotcDay(month:1,day:11,name:'ቅድስት ሐና እና ኢያቄም'),
  EotcDay(month:1,day:12,name:'ቅዱስ ሚካኤል'),
  EotcDay(month:1,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:1,day:14,name:'አቡነ አረጋዊ'),
  EotcDay(month:1,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ'),
  EotcDay(month:1,day:16,name:'ኪዳነ ምሕረት'),
  EotcDay(month:1,day:17,name:'ቅዱስ መስቀል - ደመራ',isAnnual:true),
  EotcDay(month:1,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:1,day:19,name:'ቅዱስ ገብርኤል'),
  EotcDay(month:1,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:1,day:21,name:'ግሸን ማርያም',isAnnual:true),
  EotcDay(month:1,day:22,name:'ቅዱስ ደቅስዮስ'),
  EotcDay(month:1,day:23,name:'ቅዱስ ጊዮርጊስ'),
  EotcDay(month:1,day:24,name:'አቡነ ተክለ ሃይማኖት'),
  EotcDay(month:1,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:1,day:26,name:'የጾመ ጽጌ መግቢያ',isAnnual:true),
  EotcDay(month:1,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:1,day:28,name:'አማኑኤል'),
  EotcDay(month:1,day:29,name:'ቅድስት አርሴማ',isAnnual:true),
  EotcDay(month:1,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:2,day:1,name:'ልደታ ማርያም / ቅዱስ ኤልያስ'),
  EotcDay(month:2,day:2,name:'ቅዱስ ታዴዎስ ሐዋርያ'),
  EotcDay(month:2,day:3,name:'በዓታ ማርያም'),
  EotcDay(month:2,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ'),
  EotcDay(month:2,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ'),
  EotcDay(month:2,day:6,name:'ቁስቋም ማርያም'),
  EotcDay(month:2,day:7,name:'ቅድስት ሥላሴ'),
  EotcDay(month:2,day:8,name:'አባ ኪሮስ'),
  EotcDay(month:2,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:2,day:10,name:'ቅዱስ መስቀል'),
  EotcDay(month:2,day:11,name:'ቅድስት ሐና እና ኢያቄም'),
  EotcDay(month:2,day:12,name:'ቅዱስ ሚካኤል'),
  EotcDay(month:2,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:2,day:14,name:'አቡነ አረጋዊ እና ገብረ ክርስቶስ',isAnnual:true),
  EotcDay(month:2,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ'),
  EotcDay(month:2,day:16,name:'ኪዳነ ምሕረት'),
  EotcDay(month:2,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:2,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:2,day:19,name:'ቅዱስ ገብርኤል'),
  EotcDay(month:2,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:2,day:21,name:'ቅድስት ማርያም'),
  EotcDay(month:2,day:22,name:'ቅዱስ ሉቃስ ወንጌላዊ',isAnnual:true),
  EotcDay(month:2,day:23,name:'ቅዱስ ጊዮርጊስ'),
  EotcDay(month:2,day:24,name:'አቡነ ተክለ ሃይማኖት'),
  EotcDay(month:2,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:2,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:2,day:27,name:'ጥቅምት መድኃኔዓለም',isAnnual:true),
  EotcDay(month:2,day:28,name:'አማኑኤል'),
  EotcDay(month:2,day:29,name:'በዓለ ወልድ'),
  EotcDay(month:2,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:3,day:1,name:'ልደታ ማርያም'),
  EotcDay(month:3,day:2,name:'ቅዱስ ታዴዎስ'),
  EotcDay(month:3,day:3,name:'በዓታ ማርያም'),
  EotcDay(month:3,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ'),
  EotcDay(month:3,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ'),
  EotcDay(month:3,day:6,name:'ቁስቋም ማርያም - የጾመ ጽጌ ማብቂያ',isAnnual:true),
  EotcDay(month:3,day:7,name:'ቅድስት ሥላሴ'),
  EotcDay(month:3,day:8,name:'አርባዕቱ እንስሳ',isAnnual:true),
  EotcDay(month:3,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:3,day:10,name:'ቅዱስ መስቀል'),
  EotcDay(month:3,day:11,name:'ቅድስት ሐና',isAnnual:true),
  EotcDay(month:3,day:12,name:'ኅዳር ቅዱስ ሚካኤል',isAnnual:true),
  EotcDay(month:3,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:3,day:14,name:'አቡነ አረጋዊ'),
  EotcDay(month:3,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ'),
  EotcDay(month:3,day:16,name:'ኪዳነ ምሕረት'),
  EotcDay(month:3,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:3,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:3,day:19,name:'ቅዱስ ገብርኤል'),
  EotcDay(month:3,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:3,day:21,name:'ኅዳር ጽዮን ማርያም',isAnnual:true),
  EotcDay(month:3,day:22,name:'ቅዱስ ደቅስዮስ'),
  EotcDay(month:3,day:23,name:'ቅዱስ ጊዮርጊስ'),
  EotcDay(month:3,day:24,name:'አርባዕቱ ካህናተ ሰማይ',isAnnual:true),
  EotcDay(month:3,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:3,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:3,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:3,day:28,name:'አማኑኤል'),
  EotcDay(month:3,day:29,name:'ቅዱስ መርቆሬዎስ ሰማዕት',isAnnual:true),
  EotcDay(month:3,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:4,day:1,name:'ልደታ ማርያም'),
  EotcDay(month:4,day:2,name:'ቅዱስ ታዴዎስ'),
  EotcDay(month:4,day:3,name:'ባዕታ ማርያም ወደ ቤተ መቅደስ',isAnnual:true),
  EotcDay(month:4,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ'),
  EotcDay(month:4,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ'),
  EotcDay(month:4,day:6,name:'ቁስቋም ማርያም'),
  EotcDay(month:4,day:7,name:'ቅድስት ሥላሴ'),
  EotcDay(month:4,day:8,name:'አባ ኪሮስ'),
  EotcDay(month:4,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:4,day:10,name:'ቅዱስ መስቀል'),
  EotcDay(month:4,day:11,name:'ቅድስት ሐና እና ኢያቄም'),
  EotcDay(month:4,day:12,name:'ቅዱስ ሚካኤል'),
  EotcDay(month:4,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:4,day:14,name:'አቡነ አረጋዊ'),
  EotcDay(month:4,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ'),
  EotcDay(month:4,day:16,name:'ኪዳነ ምሕረት'),
  EotcDay(month:4,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:4,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:4,day:19,name:'ቁልቢ ገብርኤል',isAnnual:true),
  EotcDay(month:4,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:4,day:21,name:'ቅድስት ማርያም'),
  EotcDay(month:4,day:22,name:'ብስራተ ገብርኤል',isAnnual:true),
  EotcDay(month:4,day:23,name:'ቅዱስ ጊዮርጊስ'),
  EotcDay(month:4,day:24,name:'አቡነ ተክለ ሃይማኖት'),
  EotcDay(month:4,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:4,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:4,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:4,day:28,name:'አማኑኤል'),
  EotcDay(month:4,day:29,name:'ገና - የጌታ ልደት',isAnnual:true),
  EotcDay(month:4,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:5,day:1,name:'ልደታ ማርያም'),
  EotcDay(month:5,day:2,name:'ቅዱስ ታዴዎስ'),
  EotcDay(month:5,day:3,name:'በዓታ ማርያም'),
  EotcDay(month:5,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ ዕረፍት',isAnnual:true),
  EotcDay(month:5,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ'),
  EotcDay(month:5,day:6,name:'ቁስቋም ማርያም'),
  EotcDay(month:5,day:7,name:'ቅድስት ሥላሴ ለአብርሃም',isAnnual:true),
  EotcDay(month:5,day:8,name:'አባ ኪሮስ'),
  EotcDay(month:5,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:5,day:10,name:'ቅዱስ መስቀል'),
  EotcDay(month:5,day:11,name:'ጥምቀተ ባሕር',isAnnual:true),
  EotcDay(month:5,day:12,name:'ቃና ዘገሊላ እና ቅዱስ ሚካኤል',isAnnual:true),
  EotcDay(month:5,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:5,day:14,name:'አቡነ አረጋዊ'),
  EotcDay(month:5,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ'),
  EotcDay(month:5,day:16,name:'ኪዳነ ምሕረት'),
  EotcDay(month:5,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:5,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:5,day:19,name:'ቅዱስ ገብርኤል'),
  EotcDay(month:5,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:5,day:21,name:'አስተርእዮ ማርያም',isAnnual:true),
  EotcDay(month:5,day:22,name:'ቅዱስ ደቅስዮስ'),
  EotcDay(month:5,day:23,name:'ቅዱስ ጊዮርጊስ ፍልሰተ ዓጽም',isAnnual:true),
  EotcDay(month:5,day:24,name:'አቡነ ተክለ ሃይማኖት'),
  EotcDay(month:5,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:5,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:5,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:5,day:28,name:'አማኑኤል'),
  EotcDay(month:5,day:29,name:'በዓለ ወልድ'),
  EotcDay(month:5,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:6,day:1,name:'ልደታ ማርያም'),
  EotcDay(month:6,day:2,name:'ቅዱስ ታዴዎስ'),
  EotcDay(month:6,day:3,name:'በዓታ ማርያም'),
  EotcDay(month:6,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ'),
  EotcDay(month:6,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ'),
  EotcDay(month:6,day:6,name:'ቁስቋም ማርያም'),
  EotcDay(month:6,day:7,name:'ቅድስት ሥላሴ'),
  EotcDay(month:6,day:8,name:'አባ ኪሮስ'),
  EotcDay(month:6,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:6,day:10,name:'ቅዱስ መስቀል'),
  EotcDay(month:6,day:11,name:'አቡነ ፋሲለደስ'),
  EotcDay(month:6,day:12,name:'ቅዱስ ሚካኤል'),
  EotcDay(month:6,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:6,day:14,name:'አቡነ አረጋዊ'),
  EotcDay(month:6,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ'),
  EotcDay(month:6,day:16,name:'ኪዳነ ምሕረት ቃልኪዳን',isAnnual:true),
  EotcDay(month:6,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:6,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:6,day:19,name:'ቅዱስ ገብርኤል'),
  EotcDay(month:6,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:6,day:21,name:'ቅድስት ማርያም'),
  EotcDay(month:6,day:22,name:'ቅዱስ ደቅስዮስ'),
  EotcDay(month:6,day:23,name:'ቅዱስ ጊዮርጊስ / የዓድዋ ድል',isAnnual:true),
  EotcDay(month:6,day:24,name:'አቡነ ተክለ ሃይማኖት'),
  EotcDay(month:6,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:6,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:6,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:6,day:28,name:'አማኑኤል'),
  EotcDay(month:6,day:29,name:'በዓለ ወልድ'),
  EotcDay(month:6,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:7,day:1,name:'ልደታ ማርያም'),
  EotcDay(month:7,day:2,name:'ቅዱስ ታዴዎስ'),
  EotcDay(month:7,day:3,name:'በዓታ ማርያም'),
  EotcDay(month:7,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ'),
  EotcDay(month:7,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ ዕረፍት',isAnnual:true),
  EotcDay(month:7,day:6,name:'ቁስቋም ማርያም'),
  EotcDay(month:7,day:7,name:'ቅድስት ሥላሴ'),
  EotcDay(month:7,day:8,name:'አባ ኪሮስ'),
  EotcDay(month:7,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:7,day:10,name:'ቅዱስ መስቀል',isAnnual:true),
  EotcDay(month:7,day:11,name:'ቅድስት ሐና እና ኢያቄም'),
  EotcDay(month:7,day:12,name:'ቅዱስ ሚካኤል'),
  EotcDay(month:7,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:7,day:14,name:'አቡነ አረጋዊ'),
  EotcDay(month:7,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ'),
  EotcDay(month:7,day:16,name:'ኪዳነ ምሕረት'),
  EotcDay(month:7,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:7,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:7,day:19,name:'ቅዱስ ገብርኤል'),
  EotcDay(month:7,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:7,day:21,name:'ቅድስት ማርያም'),
  EotcDay(month:7,day:22,name:'ቅዱስ ደቅስዮስ'),
  EotcDay(month:7,day:23,name:'ቅዱስ ጊዮርጊስ'),
  EotcDay(month:7,day:24,name:'አቡነ ተክለ ሃይማኖት'),
  EotcDay(month:7,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:7,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:7,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:7,day:28,name:'አማኑኤል'),
  EotcDay(month:7,day:29,name:'በዓለ ወልድ'),
  EotcDay(month:7,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:8,day:1,name:'ልደታ ማርያም'),
  EotcDay(month:8,day:2,name:'ቅዱስ ታዴዎስ'),
  EotcDay(month:8,day:3,name:'በዓታ ማርያም'),
  EotcDay(month:8,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ'),
  EotcDay(month:8,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ'),
  EotcDay(month:8,day:6,name:'ቁስቋም ማርያም'),
  EotcDay(month:8,day:7,name:'ቅድስት ሥላሴ'),
  EotcDay(month:8,day:8,name:'አባ ኪሮስ'),
  EotcDay(month:8,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:8,day:10,name:'ቅዱስ መስቀል'),
  EotcDay(month:8,day:11,name:'ቅድስት ሐና እና ኢያቄም'),
  EotcDay(month:8,day:12,name:'ቅዱስ ሚካኤል'),
  EotcDay(month:8,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:8,day:14,name:'አቡነ አረጋዊ'),
  EotcDay(month:8,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ'),
  EotcDay(month:8,day:16,name:'ኪዳነ ምሕረት'),
  EotcDay(month:8,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:8,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:8,day:19,name:'ቅዱስ ገብርኤል'),
  EotcDay(month:8,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:8,day:21,name:'ቅድስት ማርያም'),
  EotcDay(month:8,day:22,name:'ቅዱስ ደቅስዮስ'),
  EotcDay(month:8,day:23,name:'ቅዱስ ጊዮርጊስ'),
  EotcDay(month:8,day:24,name:'አቡነ ተክለ ሃይማኖት'),
  EotcDay(month:8,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:8,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:8,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:8,day:28,name:'አማኑኤል'),
  EotcDay(month:8,day:29,name:'በዓለ ወልድ'),
  EotcDay(month:8,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:9,day:1,name:'ልደታ ማርያም',isAnnual:true),
  EotcDay(month:9,day:2,name:'ቅዱስ ታዴዎስ'),
  EotcDay(month:9,day:3,name:'በዓታ ማርያም'),
  EotcDay(month:9,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ'),
  EotcDay(month:9,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ'),
  EotcDay(month:9,day:6,name:'ቁስቋም ማርያም'),
  EotcDay(month:9,day:7,name:'ቅድስት ሥላሴ'),
  EotcDay(month:9,day:8,name:'አባ ኪሮስ'),
  EotcDay(month:9,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:9,day:10,name:'ቅዱስ መስቀል'),
  EotcDay(month:9,day:11,name:'ቅዱስ ያሬድ',isAnnual:true),
  EotcDay(month:9,day:12,name:'ፍልሰተ ዓጽሙ ለአቡነ ተክለ ሃይማኖት',isAnnual:true),
  EotcDay(month:9,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:9,day:14,name:'አቡነ አረጋዊ'),
  EotcDay(month:9,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ'),
  EotcDay(month:9,day:16,name:'ኪዳነ ምሕረት'),
  EotcDay(month:9,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:9,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:9,day:19,name:'ቅዱስ ገብርኤል'),
  EotcDay(month:9,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:9,day:21,name:'ደብረ ምጥማቅ ማርያም',isAnnual:true),
  EotcDay(month:9,day:22,name:'ቅዱስ ደቅስዮስ'),
  EotcDay(month:9,day:23,name:'ቅዱስ ጊዮርጊስ'),
  EotcDay(month:9,day:24,name:'አቡነ ተክለ ሃይማኖት'),
  EotcDay(month:9,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:9,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:9,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:9,day:28,name:'አማኑኤል'),
  EotcDay(month:9,day:29,name:'በዓለ ወልድ'),
  EotcDay(month:9,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:10,day:1,name:'ልደታ ማርያም'),
  EotcDay(month:10,day:2,name:'ቅዱስ ታዴዎስ'),
  EotcDay(month:10,day:3,name:'በዓታ ማርያም'),
  EotcDay(month:10,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ'),
  EotcDay(month:10,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ'),
  EotcDay(month:10,day:6,name:'ቁስቋም ማርያም'),
  EotcDay(month:10,day:7,name:'ቅድስት ሥላሴ'),
  EotcDay(month:10,day:8,name:'አባ ኪሮስ'),
  EotcDay(month:10,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:10,day:10,name:'ቅዱስ መስቀል'),
  EotcDay(month:10,day:11,name:'ቅድስት ሐና እና ኢያቄም'),
  EotcDay(month:10,day:12,name:'ሰኔ ሚካኤል እና ጻድቁ ንጉሥ ላሊበላ',isAnnual:true),
  EotcDay(month:10,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:10,day:14,name:'አቡነ አረጋዊ'),
  EotcDay(month:10,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ'),
  EotcDay(month:10,day:16,name:'ኪዳነ ምሕረት'),
  EotcDay(month:10,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:10,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:10,day:19,name:'ቅዱስ ገብርኤል'),
  EotcDay(month:10,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:10,day:21,name:'ሰኔ ጎልጎታ',isAnnual:true),
  EotcDay(month:10,day:22,name:'ቅዱስ ደቅስዮስ'),
  EotcDay(month:10,day:23,name:'ቅዱስ ጊዮርጊስ'),
  EotcDay(month:10,day:24,name:'አቡነ ተክለ ሃይማኖት'),
  EotcDay(month:10,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:10,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:10,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:10,day:28,name:'አማኑኤል'),
  EotcDay(month:10,day:29,name:'በዓለ ወልድ'),
  EotcDay(month:10,day:30,name:'ልደተ ዮሐንስ መጥምቅ',isAnnual:true),
  EotcDay(month:11,day:1,name:'ልደታ ማርያም'),
  EotcDay(month:11,day:2,name:'ቅዱስ ታዴዎስ'),
  EotcDay(month:11,day:3,name:'በዓታ ማርያም'),
  EotcDay(month:11,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ'),
  EotcDay(month:11,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ'),
  EotcDay(month:11,day:6,name:'ቁስቋም ማርያም'),
  EotcDay(month:11,day:7,name:'ቅድስት ሥላሴ'),
  EotcDay(month:11,day:8,name:'አባ ኪሮስ'),
  EotcDay(month:11,day:9,name:'ሰልስቱ ምዕት'),
  EotcDay(month:11,day:10,name:'ቅዱስ መስቀል'),
  EotcDay(month:11,day:11,name:'ቅድስት ሐና እና ኢያቄም'),
  EotcDay(month:11,day:12,name:'ቅዱስ ሚካኤል'),
  EotcDay(month:11,day:13,name:'እግዚአብሔር አብ'),
  EotcDay(month:11,day:14,name:'አቡነ አረጋዊ'),
  EotcDay(month:11,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ',isAnnual:true),
  EotcDay(month:11,day:16,name:'ኪዳነ ምሕረት'),
  EotcDay(month:11,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:11,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:11,day:19,name:'ሐምሌ ገብርኤል',isAnnual:true),
  EotcDay(month:11,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:11,day:21,name:'ቅድስት ማርያም'),
  EotcDay(month:11,day:22,name:'ቅዱስ ደቅስዮስ'),
  EotcDay(month:11,day:23,name:'ቅዱስ ጊዮርጊስ'),
  EotcDay(month:11,day:24,name:'አቡነ ተክለ ሃይማኖት'),
  EotcDay(month:11,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:11,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:11,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:11,day:28,name:'አማኑኤል'),
  EotcDay(month:11,day:29,name:'በዓለ ወልድ'),
  EotcDay(month:11,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:12,day:1,name:'ልደታ ማርያም (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:2,name:'ቅዱስ ታዴዎስ (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:3,name:'በዓታ ማርያም (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:4,name:'ዮሐንስ ወልደ ነጐድጓድ (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:5,name:'አቡነ ገብረ መንፈስ ቅዱስ (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:6,name:'ቁስቋም ማርያም (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:7,name:'ቅድስት ሥላሴ (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:8,name:'አባ ኪሮስ (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:9,name:'ሰልስቱ ምዕት (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:10,name:'ቅዱስ መስቀል (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:11,name:'ቅድስት ሐና (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:12,name:'ቅዱስ ሚካኤል (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:13,name:'ቡሄ / ደብረ ታቦር',isAnnual:true),
  EotcDay(month:12,day:14,name:'አቡነ አረጋዊ (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:15,name:'ቅዱስ ቂርቆስና ኢየሉጣ (ጾመ ፍልሰታ)'),
  EotcDay(month:12,day:16,name:'ፍልሰታ ማርያም',isAnnual:true),
  EotcDay(month:12,day:17,name:'ቅዱስ እስጢፋኖስ'),
  EotcDay(month:12,day:18,name:'አቡነ ኤዎስጣቴዎስ'),
  EotcDay(month:12,day:19,name:'ቅዱስ ገብርኤል'),
  EotcDay(month:12,day:20,name:'ብዙኃን ቅዱሳን'),
  EotcDay(month:12,day:21,name:'ቅድስት ማርያም'),
  EotcDay(month:12,day:22,name:'ቅዱስ ደቅስዮስ'),
  EotcDay(month:12,day:23,name:'ቅዱስ ጊዮርጊስ'),
  EotcDay(month:12,day:24,name:'አቡነ ተክለ ሃይማኖት ዕረፍት',isAnnual:true),
  EotcDay(month:12,day:25,name:'ቅዱስ መርቆሬዎስ'),
  EotcDay(month:12,day:26,name:'ቅዱስ ቶማስ ሐዋርያ'),
  EotcDay(month:12,day:27,name:'መድኃኔዓለም'),
  EotcDay(month:12,day:28,name:'አማኑኤል'),
  EotcDay(month:12,day:29,name:'በዓለ ወልድ'),
  EotcDay(month:12,day:30,name:'ቅዱስ ማርቆስ'),
  EotcDay(month:13,day:1,name:'ቅዱስ ዑራኤል'),
  EotcDay(month:13,day:2,name:'ቅዱስ አናንያል'),
  EotcDay(month:13,day:3,name:'ቅዱስ ሩፋኤል',isAnnual:true),
  EotcDay(month:13,day:4,name:'የመላእክት ጉባኤ'),
  EotcDay(month:13,day:5,name:'ነቢዩ አሞጽ እና የዓመቱ ማብቂያ'),
  EotcDay(month:13,day:6,name:'የምስጋና ጸሎት ማጠናቀቂያ'),
];

class CalendarScreen extends StatefulWidget {
  final bool isDark;
  const CalendarScreen({super.key, required this.isDark});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late EthiopianDate _today;
  late int _viewMonth, _viewYear;
  int? _selectedDay;

  final _gregDayCtrl = TextEditingController();
  final _gregMonthCtrl = TextEditingController();
  final _gregYearCtrl = TextEditingController();
  final _ethDayCtrl = TextEditingController();
  final _ethMonthCtrl = TextEditingController();
  final _ethYearCtrl = TextEditingController();
  String _convResult = '';
  bool _convToEth = true;

  @override
  void initState() {
    super.initState();
    _today = EthiopianCalendar.today();
    _viewMonth = _today.month;
    _viewYear = _today.year;
    _selectedDay = _today.day;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _gregDayCtrl.dispose(); _gregMonthCtrl.dispose(); _gregYearCtrl.dispose();
    _ethDayCtrl.dispose(); _ethMonthCtrl.dispose(); _ethYearCtrl.dispose();
    super.dispose();
  }

  AppColors get c => AppColors(widget.isDark);

  void _prevMonth() => setState(() {
    if (_viewMonth == 1) { _viewMonth = 13; _viewYear--; } else { _viewMonth--; }
    _selectedDay = null;
  });

  void _nextMonth() => setState(() {
    if (_viewMonth == 13) { _viewMonth = 1; _viewYear++; } else { _viewMonth++; }
    _selectedDay = null;
  });

  String _amharicDow(int weekday) {
    const days = ['ሰኞ','ማክሰኞ','ረቡዕ','ሐሙስ','ዓርብ','ቅዳሜ','እሁድ'];
    return days[weekday - 1];
  }

  String _formatGregorian(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  bool _isToday(int day) => day == _today.day && _viewMonth == _today.month && _viewYear == _today.year;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          Container(
            color: c.hero, padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(children: [
              Row(children: [
                Icon(Icons.calendar_month_outlined, color: c.gold, size: 22),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${_amharicDow(DateTime.now().weekday)} ${EthiopianCalendar.monthsAmharic[_today.month - 1]} ${_today.day}, ${_today.year}',
                    style: TextStyle(fontSize: 16, color: c.text, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(_formatGregorian(DateTime.now()), style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ]),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                labelColor: c.gold, unselectedLabelColor: c.muted,
                indicatorColor: c.gold, indicatorWeight: 2,
                labelStyle: const TextStyle(fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700),
                tabs: const [Tab(text: 'CALENDAR'), Tab(text: 'CONVERTER')],
              ),
            ]),
          ),
          Expanded(child: TabBarView(controller: _tabController, children: [_buildCalendarTab(), _buildConverterTab()])),
        ]),
      ),
    );
  }

  Widget _buildCalendarTab() {
    final daysInMonth = EthiopianCalendar.daysInMonth(_viewMonth, _viewYear);
    final monthAmharic = EthiopianCalendar.monthsAmharic[_viewMonth - 1];
    final firstGreg = EthiopianCalendar.toGregorian(1, _viewMonth, _viewYear);
    final startCol = firstGreg.weekday - 1;
    return SingleChildScrollView(
      child: Column(children: [
        Container(
          color: c.hero, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            _navArrow(Icons.chevron_left, _prevMonth),
            Expanded(child: Center(child: Text('$monthAmharic $_viewYear',
                style: TextStyle(fontSize: 17, color: c.text, fontWeight: FontWeight.w700)))),
            _navArrow(Icons.chevron_right, _nextMonth),
          ]),
        ),
        Container(
          color: c.hero, padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['ሰኞ','ማክ','ረቡ','ሐሙ','ዓር','ቅዳ','እሁ'].map((name) =>
              SizedBox(width: 40, child: Center(child: Text(name, style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w600))))
            ).toList(),
          ),
        ),
        Container(height: 0.5, color: c.border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 0, childAspectRatio: 1.8,
            ),
            itemCount: startCol + daysInMonth,
            itemBuilder: (context, index) {
              if (index < startCol) return const SizedBox();
              final day = index - startCol + 1;
              final today = _isToday(day);
              final selected = _selectedDay == day && !today;
              final eotcDay = getEotcDay(_viewMonth, day);
              final isAnnual = eotcDay?.isAnnual ?? false;
              return GestureDetector(
                onTap: () => setState(() => _selectedDay = day),
                child: Container(
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: isAnnual && !today ? c.goldBg.withAlpha(100) : null,
                    border: today ? Border.all(color: const Color(0xFF4A9EFF), width: 1.5)
                        : selected ? Border.all(color: c.gold, width: 1.5)
                        : isAnnual ? Border.all(color: c.gold.withAlpha(80), width: 0.5) : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    Text('$day', style: TextStyle(
                      fontSize: 14,
                      color: today ? const Color(0xFF4A9EFF) : isAnnual ? c.gold : c.text,
                      fontWeight: today || isAnnual ? FontWeight.w800 : FontWeight.w400,
                    )),
                    if (eotcDay != null) Positioned(bottom: 2, child: Container(
                      width: 4, height: 4,
                      decoration: BoxDecoration(
                        color: isAnnual ? c.gold : c.muted.withAlpha(120),
                        shape: BoxShape.circle,
                      ),
                    )),
                  ]),
                ),
              );
            },
          ),
        ),
        Container(height: 0.5, color: c.border),
        // ── Selected day feast card ──
        if (_selectedDay != null)
          Builder(builder: (ctx) {
            final feast = getEotcDay(_viewMonth, _selectedDay!);
            final isAnnual = feast?.isAnnual ?? false;
            final synaxarium = getSynaxarium(_viewMonth, _selectedDay!);
            return GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SaintStoryScreen(
                    isDark: widget.isDark,
                    feastName: feast?.name ?? 'No feast recorded for this day',
                    dateLabel: '$monthAmharic $_selectedDay',
                    isAnnual: isAnnual,
                    story: synaxarium?.fullStory,
                  ),
                ));
              },
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isAnnual ? c.goldBg : c.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isAnnual ? c.gold : c.border, width: isAnnual ? 1.5 : 0.5),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold, width: 0.5)),
                      child: Center(child: Text(isAnnual ? '⭐' : '☩', style: TextStyle(fontSize: 20, color: c.gold))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$monthAmharic $_selectedDay', style: TextStyle(fontSize: 11, color: c.muted)),
                      const SizedBox(height: 4),
                      Text(feast != null ? feast.name : 'No feast recorded for this day',
                        style: TextStyle(fontSize: 15, color: c.text, fontWeight: FontWeight.w700)),
                      if (isAnnual) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: c.gold.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                          child: Text('ዓመታዊ በዓል', style: TextStyle(fontSize: 10, color: c.gold, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ])),
                    Icon(Icons.chevron_right, color: c.muted, size: 20),
                  ]),
                  if (synaxarium != null) ...[
                    const SizedBox(height: 10),
                    Container(height: 0.5, color: c.border),
                    const SizedBox(height: 10),
                    Text(
                      synaxarium.snippet,
                      style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text('📖 Tap to read the Synaxarium →', style: TextStyle(fontSize: 11, color: c.gold, fontWeight: FontWeight.w600)),
                  ] else if (feast != null) ...[
                    const SizedBox(height: 8),
                    Text('📖 Tap to view details', style: TextStyle(fontSize: 11, color: c.muted, fontStyle: FontStyle.italic)),
                  ],
                ]),
              ),
            );
          }),
        // ── Annual feasts list ──
        Builder(builder: (ctx) {
          final annualFeasts = getAnnualFeasts(_viewMonth);
          if (annualFeasts.isEmpty) return const SizedBox();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(children: [
                Container(width: 3, height: 14, color: c.gold, margin: const EdgeInsets.only(right: 8)),
                Text('ዓመታዊ በዓላት - $monthAmharic', style: TextStyle(fontSize: 10, color: c.label, letterSpacing: 2, fontWeight: FontWeight.w700)),
              ]),
            ),
            ...annualFeasts.map((feast) => GestureDetector(
              onTap: () => setState(() => _selectedDay = feast.day),
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.goldBg, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.gold.withAlpha(80), width: 0.5),
                ),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.gold, width: 0.5)),
                    child: Center(child: Text(feast.day.toString(), style: TextStyle(fontSize: 14, color: c.gold, fontWeight: FontWeight.w800))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(feast.name, style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w600)),
                    Text('$monthAmharic ${feast.day}', style: TextStyle(fontSize: 11, color: c.muted)),
                  ])),
                  const Text('⭐', style: TextStyle(fontSize: 16)),
                ]),
              ),
            )),
          ]);
        }),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _navArrow(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: SizedBox(width: 36, height: 36, child: Icon(icon, color: const Color(0xFF4A9EFF), size: 28)),
  );

  void _convert() {
    setState(() {
      try {
        if (_convToEth) {
          final eth = EthiopianCalendar.fromGregorian(DateTime(
            int.parse(_gregYearCtrl.text), int.parse(_gregMonthCtrl.text), int.parse(_gregDayCtrl.text)));
          _convResult = '✝  ${eth.monthName} ${eth.day}, ${eth.year}\n${eth.monthNameAmharic} ${eth.day}, ${eth.year}\n${eth.zemene}';
        } else {
          final greg = EthiopianCalendar.toGregorian(
            int.parse(_ethDayCtrl.text), int.parse(_ethMonthCtrl.text), int.parse(_ethYearCtrl.text));
          const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
          _convResult = '📅  ${months[greg.month - 1]} ${greg.day}, ${greg.year}';
        }
      } catch (e) { _convResult = '⚠  Please enter valid numbers'; }
    });
  }

  Widget _buildConverterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border, width: 0.5)),
          child: Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _convToEth = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: _convToEth ? c.gold : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text('Gregorian → Ethiopian', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: _convToEth ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.muted,
                ))),
              ),
            )),
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _convToEth = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: !_convToEth ? c.gold : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text('Ethiopian → Gregorian', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: !_convToEth ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.muted,
                ))),
              ),
            )),
          ]),
        ),
        const SizedBox(height: 20),
        if (_convToEth) ...[
          _convLabel('GREGORIAN DATE'), const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field('Day', _gregDayCtrl)),
            const SizedBox(width: 8),
            Expanded(child: _field('Month', _gregMonthCtrl)),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _field('Year', _gregYearCtrl)),
          ]),
        ] else ...[
          _convLabel('ETHIOPIAN DATE'), const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field('Day', _ethDayCtrl)),
            const SizedBox(width: 8),
            Expanded(child: _field('Month (1-13)', _ethMonthCtrl)),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _field('Year', _ethYearCtrl)),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
            child: Wrap(spacing: 8, runSpacing: 6, children: List.generate(13, (i) =>
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.gold.withAlpha(80))),
                child: Text('${i+1}. ${EthiopianCalendar.months[i]}', style: TextStyle(fontSize: 10, color: c.gold)),
              )
            )),
          ),
        ],
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _convert,
          child: Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: c.gold.withAlpha(80), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Center(child: Text('CONVERT ✦', style: TextStyle(fontSize: 13,
                color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, letterSpacing: 3, fontWeight: FontWeight.w800))),
          ),
        ),
        if (_convResult.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.gold, width: 1), boxShadow: [BoxShadow(color: c.gold.withAlpha(40), blurRadius: 16)]),
            child: Column(children: [
              Text('RESULT', style: TextStyle(fontSize: 9, color: c.label, letterSpacing: 3)),
              const SizedBox(height: 10),
              Text(_convResult, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: c.text, fontWeight: FontWeight.w600, height: 1.6)),
            ]),
          ),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _convLabel(String t) => Text(t, style: TextStyle(fontSize: 9, color: c.label, letterSpacing: 3, fontWeight: FontWeight.w700));

  Widget _field(String hint, TextEditingController ctrl) => TextField(
    controller: ctrl, keyboardType: TextInputType.number,
    style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w500),
    decoration: InputDecoration(
      hintText: hint, hintStyle: TextStyle(fontSize: 11, color: c.muted),
      filled: true, fillColor: c.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border, width: 0.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border, width: 0.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.gold, width: 1.5)),
    ),
  );
}

// ═══════════════════════════════════════════════
// CONFESSION HISTORY SCREEN
// ═══════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onFinish;
  const OnboardingScreen({super.key, required this.isDark, required this.onFinish});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController();
  int _page = 0;

  static const List<Map<String, String>> _slides = [
    {
      'emoji': '☩',
      'title': 'Yenefs Abat',
      'titleAm': 'የነፍስ አባት',
      'body': 'Your spiritual companion in the Ethiopian Orthodox Tewahedo faith — always with you, wherever you are.',
      'bodyAm': 'የነፍስ አባትዎ — በኪስዎ ውስጥ ያለ መንፈሳዊ አጋር።',
    },
    {
      'emoji': '✝️',
      'title': 'Stay Faithful to Confession',
      'titleAm': 'ለንስሐ ታማኝ ይሁኑ',
      'body': 'Prepare for confession, examine your conscience, and keep track of your spiritual journey so you never drift away.',
      'bodyAm': 'ለንስሐ ይዘጋጁ፣ ኅሊናዎን ይመርምሩ፣ መንፈሳዊ ጉዞዎን ይከታተሉ።',
    },
    {
      'emoji': '🔔',
      'title': 'Never Miss Prayer Time',
      'titleAm': 'የጸሎት ጊዜ አያምልጥዎ',
      'body': 'Gentle reminders call you to prayer through the day, like the church bell — morning, noon, evening, and night.',
      'bodyAm': 'እንደ ደወል በቀኑ ውስጥ ወደ ጸሎት ይጠሩዎታል።',
    },
    {
      'emoji': '📅',
      'title': 'Follow the Orthodox Calendar',
      'titleAm': 'የኦርቶዶክስ ቀን መቁጠሪያ',
      'body': 'Know the true date, every fast and feast, and the saint (ስንክሳር) remembered on each day of the year.',
      'bodyAm': 'ትክክለኛውን ቀን፣ ጾምና በዓል፣ የዕለቱን ስንክሳር ይወቁ።',
    },
    {
      'emoji': '⛪',
      'title': 'Find the Nearest Church',
      'titleAm': 'ቅርብ ቤተ ክርስቲያን ያግኙ',
      'body': 'Discover Ethiopian Orthodox churches near you, and find a place to worship and a spiritual father wherever you go.',
      'bodyAm': 'በአቅራቢያዎ ያሉ የኦርቶዶክስ አብያተ ክርስቲያናትን ያግኙ።',
    },
  ];

  @override
  void dispose() { _pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    final isLast = _page == _slides.length - 1;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        // Skip
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: widget.onFinish,
              child: Text('Skip', style: TextStyle(color: c.muted, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pc,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final s = _slides[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 130, height: 130,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [c.goldBg, c.card]),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.gold, width: 2),
                      boxShadow: [BoxShadow(color: c.gold.withAlpha(80), blurRadius: 30, spreadRadius: 4)],
                    ),
                    child: Center(child: Text(s['emoji']!, style: const TextStyle(fontSize: 64))),
                  ),
                  const SizedBox(height: 40),
                  Text(s['titleAm']!, style: TextStyle(fontSize: 18, color: c.gold, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text(s['title']!, style: TextStyle(fontSize: 24, color: c.text, fontWeight: FontWeight.w900, height: 1.2), textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  Text(s['body']!, style: TextStyle(fontSize: 14.5, color: c.muted, height: 1.7), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(s['bodyAm']!, style: TextStyle(fontSize: 13, color: c.text, height: 1.8), textAlign: TextAlign.center),
                ]),
              );
            },
          ),
        ),
        // Dots
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_slides.length, (i) =>
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == _page ? 26 : 8, height: 8,
            decoration: BoxDecoration(
              color: i == _page ? c.gold : c.muted.withAlpha(80),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        )),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: GestureDetector(
            onTap: () {
              if (isLast) {
                widget.onFinish();
              } else {
                _pc.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
              }
            },
            child: Container(
              width: double.infinity, height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFE3C878), Color(0xFFC9A84C), Color(0xFFA98937)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: c.gold.withAlpha(110), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Center(child: Text(
                isLast ? 'GET STARTED' : 'NEXT',
                style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1),
              )),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ])),
    );
  }
}


class ConfessionGuideScreen extends StatelessWidget {
  final bool isDark;
  const ConfessionGuideScreen({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final c = AppColors(isDark);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        Container(
          color: c.hero, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(children: [
            GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.arrow_back_ios, color: c.gold, size: 20)),
            const SizedBox(width: 10),
            Container(width: 4, height: 20, color: c.gold, margin: const EdgeInsets.only(right: 10)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('WHY WE CONFESS', style: TextStyle(fontSize: 15, color: c.text, letterSpacing: 2, fontWeight: FontWeight.w800)),
              Text('ስለ ንስሐ — The Sacrament of Repentance', style: TextStyle(fontSize: 11, color: c.muted, fontStyle: FontStyle.italic)),
            ])),
          ]),
        ),
        Divider(color: c.border, height: 0.5),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _hero(c),
            const SizedBox(height: 24),
            _section(c, '☩', 'What is Confession?', 'ኑዛዜ ምንድን ነው?',
              en: 'Confession (ንስሐ) is one of the seven sacraments of the Ethiopian Orthodox Tewahedo Church. It is the sacred act by which a believer, through a spiritual father, confesses their sins to God, receives forgiveness, and is restored to communion with Him. It is not merely listing wrongs — it is a turning of the whole heart back to God.',
              am: 'ንስሐ ከኢትዮጵያ ኦርቶዶክስ ተዋሕዶ ቤተ ክርስቲያን ሰባቱ ምሥጢራት አንዱ ነው። ምእመኑ በንስሐ አባቱ በኩል ኃጢአቱን ለእግዚአብሔር የሚናዘዝበት፣ ይቅርታን የሚያገኝበት እና ከእግዚአብሔር ጋር ኅብረቱን የሚያድስበት ቅዱስ ተግባር ነው። ኃጢአትን መዘርዘር ብቻ ሳይሆን፣ ልብን ሙሉ በሙሉ ወደ እግዚአብሔር መመለስ ነው።'),
            _verse(c, 'If we confess our sins, He is faithful and just to forgive us our sins, and to cleanse us from all unrighteousness.', '1 John 1:9',
              'ኃጢአታችንን ብንናዘዝ ኃጢአታችንን ይቅር ሊለን ከዓመፃም ሁሉ ሊያነጻን የታመነና ጻድቅ ነው። — ፩ ዮሐንስ ፩፥፱'),
            _section(c, '🕊️', 'Why Do We Need to Confess?', 'ለምን መናዘዝ ያስፈልገናል?',
              en: 'Sin separates us from God and wounds the soul. Just as the body needs healing when sick, the soul needs healing when it falls into sin. Confession is the medicine of the soul — it removes the burden of guilt, reconciles us with God and the Church, and gives us strength to resist sin. Christ gave His apostles — and through them, priests — the authority to loose sins.',
              am: 'ኃጢአት ከእግዚአብሔር ይለየናል ነፍስንም ያቆስላል። ሰውነት ሲታመም ፈውስ እንደሚያስፈልገው፣ ነፍስም ወደ ኃጢአት ስትወድቅ ፈውስ ያስፈልጋታል። ንስሐ የነፍስ መድኃኒት ነው — የበደል ሸክምን ያስወግዳል፣ ከእግዚአብሔርና ከቤተ ክርስቲያን ጋር ያስታርቀናል፣ ኃጢአትን ለመቋቋም ኃይል ይሰጠናል። ክርስቶስ ለሐዋርያቱ — በእነርሱም በኩል ለካህናት — ኃጢአትን የማሰር እና የመፍታት ሥልጣን ሰጠ።'),
            _verse(c, 'Whose soever sins ye remit, they are remitted unto them; and whose soever sins ye retain, they are retained.', 'John 20:23',
              'ኃጢአታቸውን ይቅር ያላችኋቸው ሁሉ ይቀርላቸዋል፤ የያዛችሁባቸው ተይዞባቸዋል። — ዮሐንስ ፳፥፳፫'),
            _section(c, '💧', 'The Fruit of Confession', 'የንስሐ ፍሬ',
              en: 'True confession brings peace of heart, a clear conscience, and joy. It breaks the chains of habitual sin and renews our baptismal purity. The one who confesses honestly and regularly grows steadily closer to God, and finds their spiritual struggles becoming lighter over time.',
              am: 'እውነተኛ ንስሐ የልብ ሰላም፣ ንጹህ ኅሊና እና ደስታን ያመጣል። የልማድ ኃጢአት ሰንሰለቶችን ይሰብራል የጥምቀትንም ንጽሕና ያድሳል። በታማኝነትና በተከታታይ የሚናዘዝ ሰው ወደ እግዚአብሔር እየተጠጋ ይሄዳል፣ መንፈሳዊ ትግሉም እየቀለለ ይሄዳል።'),
            _verse(c, 'Confess your faults one to another, and pray one for another, that ye may be healed.', 'James 5:16',
              'እርስ በርሳችሁ በኃጢአታችሁ ተናዘዙ ትፈወሱም ዘንድ እርስ በርሳችሁ ጸልዩ። — ያዕቆብ ፭፥፲፮'),
            const SizedBox(height: 8),
            _stepsCard(c),
            const SizedBox(height: 20),
            _prayerCard(c),
            const SizedBox(height: 24),
          ]),
        )),
      ])),
    );
  }

  Widget _hero(AppColors c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [c.goldBg, c.card]),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.gold, width: 1),
    ),
    child: Column(children: [
      Container(width: 64, height: 64,
        decoration: BoxDecoration(color: c.card, shape: BoxShape.circle, border: Border.all(color: c.gold, width: 2),
          boxShadow: [BoxShadow(color: c.gold.withAlpha(70), blurRadius: 16, spreadRadius: 1)]),
        child: Center(child: Text('☩', style: TextStyle(fontSize: 32, color: c.gold)))),
      const SizedBox(height: 14),
      Text('"Return to Me, and I will return to you."',
        style: TextStyle(fontSize: 15, color: c.text, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, height: 1.5),
        textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text('ተመለሱ ወደ እኔ እኔም እመለሳለሁ ወደ እናንተ',
        style: TextStyle(fontSize: 13, color: c.gold, height: 1.6), textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text('Malachi 3:7 — ሚልክያስ ፫፥፯', style: TextStyle(fontSize: 11, color: c.muted)),
    ]),
  );

  Widget _section(AppColors c, String emoji, String titleEn, String titleAm, {required String en, required String am}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titleEn, style: TextStyle(fontSize: 16, color: c.text, fontWeight: FontWeight.w800)),
            Text(titleAm, style: TextStyle(fontSize: 12, color: c.gold, fontWeight: FontWeight.w600)),
          ])),
        ]),
        const SizedBox(height: 12),
        Text(am, style: TextStyle(fontSize: 14, color: c.text, height: 1.9)),
        const SizedBox(height: 12),
        Text(en, style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.8, fontStyle: FontStyle.italic)),
      ]),
    );

  Widget _verse(AppColors c, String en, String ref, String am) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 22),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: c.goldBg,
      borderRadius: BorderRadius.circular(14),
      border: Border(left: BorderSide(color: c.gold, width: 3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('"$en"', style: TextStyle(fontSize: 13.5, color: c.text, height: 1.7, fontStyle: FontStyle.italic)),
      const SizedBox(height: 8),
      Text(am, style: TextStyle(fontSize: 12.5, color: c.text, height: 1.8)),
      const SizedBox(height: 6),
      Text('— $ref', style: TextStyle(fontSize: 12, color: c.gold, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _stepsCard(AppColors c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('📿', style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text('How to Prepare for Confession', style: TextStyle(fontSize: 15, color: c.text, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 4),
      Text('ለንስሐ እንዴት እንዘጋጃለን', style: TextStyle(fontSize: 12, color: c.gold, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      _step(c, '1', 'Pray for a contrite heart', 'የተሰበረ ልብ ይኖረኝ ዘንድ ጸልይ', 'Ask the Holy Spirit to reveal your sins and grant you true sorrow for them.'),
      _step(c, '2', 'Examine your conscience', 'ኅሊናህን መርምር', 'Use the checklist in this app to reflect honestly on your thoughts, words, and deeds since your last confession.'),
      _step(c, '3', 'Confess honestly & completely', 'በእውነት ተናዘዝ', 'Hide nothing from your spiritual father. He stands in the place of Christ and is bound to secrecy.'),
      _step(c, '4', 'Receive absolution & penance', 'ፍትሐትና ቀኖና ተቀበል', 'Accept the prayer of forgiveness and perform the penance (ቀኖና) given to you with humility.'),
      _step(c, '5', 'Amend your life', 'ሕይወትህን አድስ', 'Resolve, with God\'s help, to turn away from sin and walk in righteousness.', last: true),
    ]),
  );

  Widget _step(AppColors c, String n, String en, String am, String desc, {bool last = false}) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 16),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 26, height: 26, decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFFE3C878), c.gold]), shape: BoxShape.circle),
        child: Center(child: Text(n, style: TextStyle(color: isDark ? const Color(0xFF0F0505) : Colors.white, fontSize: 13, fontWeight: FontWeight.w900)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(en, style: TextStyle(fontSize: 13.5, color: c.text, fontWeight: FontWeight.w700)),
        Text(am, style: TextStyle(fontSize: 12, color: c.gold)),
        const SizedBox(height: 3),
        Text(desc, style: TextStyle(fontSize: 12, color: c.muted, height: 1.6)),
      ])),
    ]),
  );

  Widget _prayerCard(AppColors c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.card, c.goldBg]),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.gold, width: 1),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('🙏', style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text('A Prayer of Repentance', style: TextStyle(fontSize: 15, color: c.text, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 14),
      Text('አቤቱ እግዚአብሔር ሆይ፣ በታላቅ ምሕረትህ ማረኝ፤ እንደ ብዙ ርኅራኄህም መተላለፌን ደምስስ። ከበደሌ ፈጽሞ እጠበኝ ከኃጢአቴም አንጻኝ። አቤቱ ንጹሕ ልብን ፍጠርልኝ የቀናውንም መንፈስ በውስጤ አድስ።',
        style: TextStyle(fontSize: 14, color: c.text, height: 2.0)),
      const SizedBox(height: 12),
      Text('Have mercy upon me, O God, according to Your great mercy; and according to the multitude of Your compassions, blot out my transgression. Wash me thoroughly from my iniquity, and cleanse me from my sin. Create in me a clean heart, O God, and renew a right spirit within me.',
        style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.8, fontStyle: FontStyle.italic)),
      const SizedBox(height: 8),
      Text('— Psalm 51 (መዝሙረ ዳዊት ፶)', style: TextStyle(fontSize: 12, color: c.gold, fontWeight: FontWeight.w700)),
    ]),
  );
}


class ConfessionHistoryScreen extends StatefulWidget {
  final bool isDark;
  const ConfessionHistoryScreen({super.key, required this.isDark});
  @override
  State<ConfessionHistoryScreen> createState() => _ConfessionHistoryScreenState();
}

class _ConfessionHistoryScreenState extends State<ConfessionHistoryScreen> {
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() { super.initState(); _loadHistory(); }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('confession_history') ?? '[]';
    final list = jsonDecode(raw) as List;
    setState(() => _history = list.map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<void> _deleteEntry(int index) async {
    setState(() => _history.removeAt(index));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('confession_history', jsonEncode(_history));
  }

  String _formatDate(String isoStr) {
    final d = DateTime.parse(isoStr);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month-1]} ${d.day}, ${d.year}  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          // Header
          Container(
            color: c.hero,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.arrow_back_ios, color: c.gold, size: 20),
              ),
              const SizedBox(width: 12),
              Container(width: 4, height: 20, color: c.gold, margin: const EdgeInsets.only(right: 10)),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SAVED CONFESSIONS', style: TextStyle(fontSize: 16, color: c.text, letterSpacing: 2, fontWeight: FontWeight.w800)),
                Text('የተቀመጡ ኑዛዜዎች', style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic)),
              ]),
            ]),
          ),
          Divider(color: c.border, height: 0.5),
          // List
          Expanded(
            child: _history.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('📿', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 16),
                    Text('No saved confessions yet', style: TextStyle(fontSize: 15, color: c.muted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('Tap Save on the confession guide to save here', style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic)),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: _history.length,
                    itemBuilder: (context, i) {
                      final entry = _history[i];
                      final date = _formatDate(entry['date'] as String);
                      final sinsList = (entry['sins'] as List).map((s) => Map<String, String>.from(s)).toList();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: c.card, borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: c.border, width: 0.5),
                          boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Date header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                            child: Row(children: [
                              Icon(Icons.calendar_today_outlined, color: c.gold, size: 14),
                              const SizedBox(width: 8),
                              Expanded(child: Text(date, style: TextStyle(fontSize: 13, color: c.gold, fontWeight: FontWeight.w700))),
                              Text('${sinsList.length} sin${sinsList.length == 1 ? '' : 's'}',
                                  style: TextStyle(fontSize: 11, color: c.muted)),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () => showDialog(context: context, builder: (ctx) => AlertDialog(
                                  backgroundColor: c.card,
                                  title: Text('Delete Entry', style: TextStyle(color: c.text)),
                                  content: Text('Delete this saved confession?', style: TextStyle(color: c.muted)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: c.muted))),
                                    TextButton(onPressed: () { Navigator.pop(ctx); _deleteEntry(i); }, child: Text('Delete', style: TextStyle(color: c.red))),
                                  ],
                                )),
                                child: Icon(Icons.delete_outline, color: c.muted, size: 18),
                              ),
                            ]),
                          ),
                          Divider(color: c.border, height: 0.5, indent: 16, endIndent: 16),
                          // Sins list
                          ...sinsList.asMap().entries.map((entry) {
                            final sin = entry.value;
                            final isLast = entry.key == sinsList.length - 1;
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(16, 10, 16, (sin['note'] as String).isNotEmpty ? 4 : 10),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Container(
                                    width: 6, height: 6, margin: const EdgeInsets.only(top: 6, right: 10),
                                    decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle),
                                  ),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(sin['amharic']!, style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w600)),
                                    Text(sin['english']!, style: TextStyle(fontSize: 11, color: c.muted)),
                                  ])),
                                ]),
                              ),
                              if ((sin['note'] as String).isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(32, 0, 16, 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(color: c.strip, borderRadius: BorderRadius.circular(8)),
                                    child: Text(sin['note'] as String, style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic)),
                                  ),
                                ),
                              if (!isLast) Divider(color: c.border, height: 0.5, indent: 16, endIndent: 16),
                            ]);
                          }),
                          const SizedBox(height: 4),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// PRIEST / FIND A CHURCH SCREEN
// ═══════════════════════════════════════════════

// ═══════════════════════════════════════════════
// PREMIUM MAP — Find a Church / Explore
// Immersive full-screen map with glassmorphism UI
// ═══════════════════════════════════════════════

class PriestScreen extends StatefulWidget {
  final bool isDark;
  const PriestScreen({super.key, required this.isDark});
  @override
  State<PriestScreen> createState() => _PriestScreenState();
}

class _PriestScreenState extends State<PriestScreen> with TickerProviderStateMixin {
  static const LatLng _addis = LatLng(9.0227, 38.7468);
  static const Color _gold = Color(0xFFC9A84C);

  final MapController _map = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  double? _lat, _lng;
  bool _locating = true;
  bool _busy = false;
  String _error = '';

  int _style = 0; // 0 standard · 1 satellite · 2 hybrid · 3 terrain
  double _rotation = 0;
  double _zoom = 13.5;
  LatLng _center = _addis;

  List<Map<String, dynamic>> _places = [];
  Map<String, dynamic>? _sel;
  String _activeCategory = 'church_eotc';

  bool _searchOpen = false;
  List<Map<String, dynamic>> _suggestions = [];
  List<String> _recents = [];
  List<Map<String, dynamic>> _favorites = [];
  Timer? _debounce;

  // ── On-map route (free — OSRM, no Google Maps handoff) ──
  List<LatLng> _routePoints = [];
  bool _routing = false;
  double? _routeDistanceKm;
  int? _routeDurationMin;
  String? _routeError;


  late final AnimationController _pulse;

  static const List<Map<String, String>> _categories = [
    {'id': 'church_eotc', 'label': 'Churches', 'emoji': '⛪', 'type': 'church', 'keyword': 'Ethiopian Orthodox'},
  ];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _loadSaved();
    _initLocation();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Persistence ──
  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recents = prefs.getStringList('map_recents') ?? [];
      final favRaw = prefs.getString('map_favorites');
      if (favRaw != null) {
        _favorites = (jsonDecode(favRaw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    });
  }

  Future<void> _saveRecent(String q) async {
    if (q.trim().isEmpty) return;
    _recents.remove(q);
    _recents.insert(0, q);
    if (_recents.length > 8) _recents = _recents.sublist(0, 8);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('map_recents', _recents);
  }

  bool _isFav(Map<String, dynamic> p) =>
      _favorites.any((f) => f['place_id'] == p['place_id']);

  Future<void> _toggleFav(Map<String, dynamic> p) async {
    setState(() {
      if (_isFav(p)) {
        _favorites.removeWhere((f) => f['place_id'] == p['place_id']);
      } else {
        _favorites.insert(0, p);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('map_favorites', jsonEncode(_favorites));
  }

  // ── Location ──
  int _locFix = 0; // 0=retry gps · 1=open location settings · 2=open app settings
  Future<void> _initLocation() async {
    setState(() { _locating = true; _error = ''; _locFix = 0; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() { _locating = false; _error = 'Location is turned off on this phone.'; _locFix = 1; });
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        setState(() { _locating = false; _error = 'Location permission is blocked — allow it in Settings.'; _locFix = 2; });
        return;
      }
      if (perm == LocationPermission.denied) {
        setState(() { _locating = false; _error = 'Location permission denied.'; _locFix = 2; });
        return;
      }
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos != null) {
        setState(() { _lat = pos!.latitude; _lng = pos.longitude; _locating = false; });
        await Future.delayed(const Duration(milliseconds: 250));
        _flyTo(LatLng(pos.latitude, pos.longitude), 14.2);
      } else {
        setState(() { _locating = false; _error = 'Could not get your exact location — showing Addis Ababa.'; });
      }
      _loadCategory(_activeCategory);
    } catch (_) {
      if (mounted) setState(() { _locating = false; _error = 'Could not get your location.'; });
      _loadCategory(_activeCategory);
    }
  }

  // ── Networking (FREE: OpenStreetMap — no key, no billing) ──
  Future<String?> _httpGet(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'YenefsAbat/1.0 (EOTC app; bekielias23@gmail.com)');
      final resp = await req.close();
      final body = await resp.transform(const Utf8Decoder()).join();
      client.close();
      return body;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _httpPost(String url, String data) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 25);
      final req = await client.postUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'YenefsAbat/1.0 (EOTC app; bekielias23@gmail.com)');
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(data);
      final resp = await req.close();
      final body = await resp.transform(const Utf8Decoder()).join();
      client.close();
      return body;
    } catch (_) {
      return null;
    }
  }

  void _apiProblem(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), duration: const Duration(seconds: 4)));
  }

  void _computeDistances(List<Map<String, dynamic>> list) {
    if (_lat == null) return;
    for (final p in list) {
      p['dist'] = Geolocator.distanceBetween(_lat!, _lng!, p['lat'] as double, p['lng'] as double) / 1000;
    }
    list.sort((a, b) => ((a['dist'] as double?) ?? 99).compareTo((b['dist'] as double?) ?? 99));
  }

  // Nearby churches via Overpass (OpenStreetMap) — races two servers for speed
  Future<String?> _overpassFetch(String q) async {
    final data = 'data=${Uri.encodeComponent(q)}';
    final results = await Future.wait([
      _httpPost('https://overpass.kumi.systems/api/interpreter', data),
      _httpPost('https://overpass-api.de/api/interpreter', data),
    ].map((f) => f.timeout(const Duration(seconds: 18), onTimeout: () => null)));
    for (final r in results) {
      if (r != null && r.trimLeft().startsWith('{')) return r;
    }
    return null;
  }

  static const List<String> _eotcInclude = [
    'ኦርቶዶክስ','ተዋሕዶ','ተዋህዶ','ቅዱስ','ቅድስት','ማርያም','መድኃኔ','መድሃኔ','መድኀኔ','ሥላሴ','ስላሴ',
    'ሚካኤል','ገብርኤል','ጊዮርጊስ','ኪዳነ','ተክለ','አማኑኤል','ጽዮን','መስቀል','ላሊበላ','አቡነ','ኡራኤል','ሩፋኤል','አርሴማ','ዮሐንስ',
    'ደብረ','ልደታ','በዓታ','ቁስቋም','መንበረ','ጴጥሮስ','ጳውሎስ','እስጢፋኖስ','መርቆሬዎስ','ቂርቆስ','እየሱስ','ኢየሱስ','እግዚአብሔር','ፈለገ','ምሕረት','ቤተ ክርስቲያን','ቤተክርስቲያን',
    'ethiopian orthodox','tewahedo','tewahdo','medhane','medhani','medhanialem','kidane','selassie','silassie','selasse',
    'st. mary','st mary','mariam','maryam','michael','mikael','gabriel','giorgis','george','trinity','emmanuel','amanuel',
    'tsion','abune','cherkos','kirkos','urael','rufael','debre','lideta','estifanos','petros','paulos','markos','yohannes','eotc','orthodox'
  ];
  static const List<String> _eotcReject = [
    'protestant','pentecost','catholic','baptist','adventist','lutheran','anglican',
    'evangelical','jehovah','mormon','latter','mekane yesus','kale heywet','kale hiwot',
    'mulu wongel','full gospel','መካነ ኢየሱስ','ቃለ ህይወት','ሙሉ ወንጌል','ካቶሊክ','ፕሮቴስታንት','ጴንጤ','መስጊድ','mosque'
  ];

  Future<void> _loadCategory(String id) async {
    final lat = _lat ?? _addis.latitude, lng = _lng ?? _addis.longitude;
    setState(() { _busy = true; _activeCategory = id; _sel = null; });
    // Single fast query — all christian places of worship; EOTC filtering happens locally
    final q = '[out:json][timeout:15];'
        'nwr["amenity"="place_of_worship"](around:11000,$lat,$lng);'
        'out center 200;';
    final body = await _overpassFetch(q);
    if (!mounted) return;
    if (body == null) {
      setState(() => _busy = false);
      _apiProblem('No internet — could not load churches');
      return;
    }
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final elements = data['elements'] as List? ?? [];
      final list = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final el in elements) {
        double? elat, elng;
        if (el['type'] == 'node') {
          elat = (el['lat'] as num?)?.toDouble();
          elng = (el['lon'] as num?)?.toDouble();
        } else if (el['center'] != null) {
          elat = (el['center']['lat'] as num?)?.toDouble();
          elng = (el['center']['lon'] as num?)?.toDouble();
        }
        if (elat == null || elng == null) continue;
        final tags = (el['tags'] as Map?) ?? {};
        final nameAm = (tags['name:am'] ?? '').toString().trim();
        final nameAny = (tags['name'] ?? tags['name:en'] ?? '').toString().trim();
        final name = nameAm.isNotEmpty ? nameAm : nameAny;
        if (name.isEmpty) continue; // exact names only
        final religion = (tags['religion'] ?? '').toString().toLowerCase();
        if (religion.isNotEmpty && religion != 'christian') continue;
        final denom = (tags['denomination'] ?? '').toString().toLowerCase();
        final lowName = ('$nameAny $nameAm').toLowerCase();
        bool rejected = false;
        for (final r in _eotcReject) {
          if (denom.contains(r) || lowName.contains(r)) { rejected = true; break; }
        }
        if (rejected) continue;
        bool included = denom.contains('ethiopian') || denom.contains('tewahedo') || denom.contains('orthodox');
        if (!included) {
          for (final k in _eotcInclude) {
            if (lowName.contains(k) || (nameAm + nameAny).contains(k)) { included = true; break; }
          }
        }
        if (!included) continue;
        final id2 = '${el['type']}${el['id']}';
        if (seen.contains(id2)) continue;
        seen.add(id2);
        list.add({
          'place_id': id2,
          'name': name,
          'sub': nameAm.isNotEmpty && nameAny.isNotEmpty && nameAm != nameAny ? nameAny : 'Ethiopian Orthodox Tewahedo',
          'lat': elat,
          'lng': elng,
          'rating': null, 'ratings': null, 'open': null,
        });
      }
      _computeDistances(list);
      setState(() { _places = list; _busy = false; });
      if (list.isEmpty) _apiProblem('No churches found nearby on the map data');
    } catch (_) {
      setState(() => _busy = false);
      _apiProblem('Could not read church data');
    }
  }

  // Text search via Nominatim (OpenStreetMap)
  Future<List<Map<String, dynamic>>> _nominatim(String q) async {
    final lat = _lat ?? _addis.latitude, lng = _lng ?? _addis.longitude;
    final url = 'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(q)}'
        '&format=json&limit=8&addressdetails=0&accept-language=am,en'
        '&viewbox=${lng - 0.35},${lat + 0.35},${lng + 0.35},${lat - 0.35}';
    final body = await _httpGet(url);
    if (body == null) return [];
    try {
      final data = jsonDecode(body) as List;
      final list = <Map<String, dynamic>>[];
      for (final r in data) {
        final dn = (r['display_name'] as String? ?? '');
        final parts = dn.split(',');
        list.add({
          'place_id': 'nom${r['place_id']}',
          'name': parts.isNotEmpty ? parts.first.trim() : dn,
          'sub': parts.length > 1 ? parts.sublist(1).join(',').trim() : '',
          'lat': double.parse(r['lat'] as String),
          'lng': double.parse(r['lon'] as String),
          'rating': null,
          'ratings': null,
          'open': null,
        });
      }
      _computeDistances(list);
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _busy = true);
    final list = await _nominatim(q);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _suggestions = [];
      _searchOpen = false;
      if (list.isNotEmpty) _places = list;
    });
    _searchFocus.unfocus();
    await _saveRecent(q);
    if (list.isNotEmpty) {
      final first = list.first;
      _flyTo(LatLng(first['lat'] as double, first['lng'] as double), 15.0);
      setState(() => _sel = first);
    } else {
      _apiProblem('Nothing found for "$q" — try a different name');
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) { setState(() => _suggestions = []); return; }
    _debounce = Timer(const Duration(milliseconds: 650), () async {
      final list = await _nominatim(q);
      if (!mounted) return;
      setState(() => _suggestions = list.take(6).toList());
    });
  }

  // ── Camera ──
  void _flyTo(LatLng dest, double destZoom) {
    final cam = _map.camera;
    final latT = Tween<double>(begin: cam.center.latitude, end: dest.latitude);
    final lngT = Tween<double>(begin: cam.center.longitude, end: dest.longitude);
    final zT = Tween<double>(begin: cam.zoom, end: destZoom);
    final ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    final anim = CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic);
    ctrl.addListener(() {
      _map.move(LatLng(latT.evaluate(anim), lngT.evaluate(anim)), zT.evaluate(anim));
    });
    anim.addStatusListener((s) { if (s == AnimationStatus.completed) ctrl.dispose(); });
    ctrl.forward();
  }

  void _resetNorth() {
    final cam = _map.camera;
    final rT = Tween<double>(begin: cam.rotation, end: 0);
    final ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    final anim = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);
    ctrl.addListener(() => _map.rotate(rT.evaluate(anim)));
    anim.addStatusListener((s) { if (s == AnimationStatus.completed) ctrl.dispose(); });
    ctrl.forward();
  }

  void _selectPlace(Map<String, dynamic> p) {
    if (_sel != null && _sel!['place_id'] != p['place_id']) _clearRoute();
    setState(() => _sel = p);
    _flyTo(LatLng(p['lat'] as double, p['lng'] as double), math.max(_zoom, 15.5));
  }

  Future<void> _openDirections(Map<String, dynamic> p) async {
    final lat = p['lat'], lng = p['lng'];
    final app = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final web = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(app)) {
      await launchUrl(app, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  // ── On-map route drawing — free, OSRM public router, stays inside the app ──
  void _clearRoute() {
    setState(() { _routePoints = []; _routeDistanceKm = null; _routeDurationMin = null; _routeError = null; });
  }

  Future<void> _showRoute(Map<String, dynamic> p) async {
    if (_lat == null || _lng == null) {
      setState(() => _routeError = 'Turn on location to draw a route.');
      return;
    }
    final from = LatLng(_lat!, _lng!);
    final to = LatLng(p['lat'] as double, p['lng'] as double);
    setState(() { _routing = true; _routeError = null; });
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final req = await client.getUrl(uri);
      final resp = await req.close();
      final body = await resp.transform(const Utf8Decoder()).join();
      client.close();
      if (resp.statusCode != 200) {
        setState(() { _routing = false; _routeError = 'Could not fetch a route right now.'; });
        return;
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        setState(() { _routing = false; _routeError = 'No route found to this church.'; });
        return;
      }
      final route = routes.first as Map<String, dynamic>;
      final coords = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng((c as List)[1] as double, c[0] as double))
          .toList();
      if (!mounted) return;
      setState(() {
        _routePoints = coords;
        _routeDistanceKm = (route['distance'] as num) / 1000.0;
        _routeDurationMin = ((route['duration'] as num) / 60).round();
        _routing = false;
      });
      _fitRoute(from, to);
    } catch (e) {
      if (!mounted) return;
      setState(() { _routing = false; _routeError = 'Network error — could not draw route.'; });
    }
  }

  void _fitRoute(LatLng from, LatLng to) {
    final bounds = LatLngBounds.fromPoints([from, to]);
    _map.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(60, 220, 60, 260)));
  }

  Future<void> _sharePlace(Map<String, dynamic> p) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${p['lat']},${p['lng']}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInGoogleMaps() async {
    final lat = _lat ?? _addis.latitude, lng = _lng ?? _addis.longitude;
    final url = Uri.parse('https://www.google.com/maps/search/Ethiopian+Orthodox+Church/@$lat,$lng,14z');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _showNearbyList() {
    final dark = widget.isDark;
    final onGlass = dark ? Colors.white : const Color(0xFF15130E);
    final muted = dark ? Colors.white60 : Colors.black54;
    bool kicked = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        if (_places.isEmpty && !_busy && !kicked) {
          kicked = true;
          _loadCategory('church_eotc').then((_) { if (ctx.mounted) setSheet(() {}); });
        }
        return Padding(
          padding: const EdgeInsets.all(12),
          child: _glass(dark,
            radius: BorderRadius.circular(26),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 38, height: 4,
                  decoration: BoxDecoration(color: onGlass.withAlpha(60), borderRadius: BorderRadius.circular(3)))),
                const SizedBox(height: 14),
                Row(children: [
                  const Text('⛪', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Churches near you', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: onGlass))),
                  if (_places.isNotEmpty)
                    Text('${_places.length} found', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _gold)),
                ]),
                const SizedBox(height: 6),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: Column(children: [
                      const CircularProgressIndicator(color: _gold),
                      const SizedBox(height: 12),
                      Text('Searching nearby churches…', style: TextStyle(color: muted, fontSize: 13)),
                    ])),
                  )
                else if (_places.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Column(children: [
                      Text('Could not load churches.', style: TextStyle(color: muted, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('Check your internet connection and retry.', style: TextStyle(color: muted, fontSize: 11.5)),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () {
                          _loadCategory('church_eotc').then((_) { if (ctx.mounted) setSheet(() {}); });
                          setSheet(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFE3C878), _gold]),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        ),
                      ),
                    ])),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.55),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _places.length > 30 ? 30 : _places.length,
                      itemBuilder: (_, i) {
                        final p = _places[i];
                        final d = p['dist'] as double?;
                        return InkWell(
                          onTap: () { Navigator.pop(ctx); _selectPlace(p); },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(children: [
                              Container(
                                width: 42, height: 42,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFFE3C878), _gold]),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Center(child: Text('⛪', style: TextStyle(fontSize: 20))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: onGlass, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Row(children: [
                                  if (d != null) ...[
                                    Icon(Icons.near_me_rounded, size: 11, color: _gold),
                                    const SizedBox(width: 3),
                                    Text('${d.toStringAsFixed(1)} km', style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 8),
                                  ],
                                  if ((p['sub'] as String? ?? '').isNotEmpty)
                                    Expanded(child: Text(p['sub'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: muted, fontSize: 11))),
                                ]),
                              ])),
                              GestureDetector(
                                onTap: () { Navigator.pop(ctx); _openDirections(p); },
                                child: Container(
                                  width: 38, height: 38,
                                  decoration: BoxDecoration(color: _gold.withAlpha(45), borderRadius: BorderRadius.circular(12)),
                                  child: Icon(Icons.directions_rounded, color: _gold, size: 19),
                                ),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  // ── Derived ──
  String _scaleLabel() {
    final mpp = 156543.03392 * math.cos(_center.latitude * math.pi / 180) / math.pow(2, _zoom);
    final target = mpp * 80; // ~80px bar
    const steps = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000];
    num best = steps.first;
    for (final s in steps) { if (s <= target) best = s; }
    return best >= 1000 ? '${(best / 1000).toStringAsFixed(0)} km' : '$best m';
  }

  double _scaleWidth() {
    final mpp = 156543.03392 * math.cos(_center.latitude * math.pi / 180) / math.pow(2, _zoom);
    final target = mpp * 80;
    const steps = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000];
    num best = steps.first;
    for (final s in steps) { if (s <= target) best = s; }
    return (best / mpp).clamp(30, 140).toDouble();
  }

  String _eta(Map<String, dynamic> p) {
    final d = (p['dist'] as double?) ?? 0;
    final walk = (d / 4.5 * 60).round();
    final drive = math.max(1, (d / 28 * 60).round());
    return '🚶 $walk min  ·  🚗 $drive min';
  }

  // ══════════════════ UI ══════════════════
  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;
    final onGlass = dark ? Colors.white : const Color(0xFF15130E);
    final muted = dark ? Colors.white60 : Colors.black54;

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0D0B08) : const Color(0xFFF3EFE7),
      body: Stack(children: [
        // ── MAP ──
        Positioned.fill(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _addis,
              initialZoom: 13.5,
              minZoom: 3,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              onTap: (_, _) { _clearRoute(); setState(() { _sel = null; _searchOpen = false; }); _searchFocus.unfocus(); },
              onMapEvent: (e) {
                final cam = _map.camera;
                final r = cam.rotation, z = cam.zoom;
                if ((r - _rotation).abs() > 1.0 || (z - _zoom).abs() > 0.15 ||
                    (cam.center.latitude - _center.latitude).abs() > 0.004 ||
                    (cam.center.longitude - _center.longitude).abs() > 0.004) {
                  setState(() { _rotation = r; _zoom = z; _center = cam.center; });
                }
              },
            ),
            children: [
              // Base tiles per style (original styling via open tile providers)
              if (_style == 0)
                TileLayer(
                  urlTemplate: dark
                      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                      : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  retinaMode: RetinaMode.isHighDensity(context),
                  keepBuffer: 6,
                  panBuffer: 2,
                  userAgentPackageName: 'com.yenefsabat.yenefs_abat',
                ),
              if (_style == 1 || _style == 2)
                TileLayer(
                  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  keepBuffer: 6,
                  panBuffer: 2,
                  userAgentPackageName: 'com.yenefsabat.yenefs_abat',
                ),
              if (_style == 2)
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_only_labels/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  retinaMode: RetinaMode.isHighDensity(context),
                  keepBuffer: 6,
                  panBuffer: 2,
                  userAgentPackageName: 'com.yenefsabat.yenefs_abat',
                ),
              if (_style == 3)
                TileLayer(
                  urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  keepBuffer: 6,
                  panBuffer: 2,
                  userAgentPackageName: 'com.yenefsabat.yenefs_abat',
                ),

              if (_routePoints.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(points: _routePoints, strokeWidth: 5, color: _gold, borderColor: Colors.white, borderStrokeWidth: 1.5),
                ]),

              MarkerLayer(markers: [
                // Pulsing user dot
                if (_lat != null)
                  Marker(
                    point: LatLng(_lat!, _lng!),
                    width: 70, height: 70,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, _) {
                        final t = _pulse.value;
                        return Stack(alignment: Alignment.center, children: [
                          Container(
                            width: 26 + 40 * t, height: 26 + 40 * t,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2E7CF6).withAlpha(((1 - t) * 70).round()),
                            ),
                          ),
                          Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2E7CF6),
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [BoxShadow(color: Colors.black.withAlpha(90), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                          ),
                        ]);
                      },
                    ),
                  ),
                // Place markers
                ..._places.take(60).map((p) {
                  final sel = identical(_sel, p) || (_sel != null && _sel!['place_id'] == p['place_id']);
                  final emoji = _categories.firstWhere((c) => c['id'] == _activeCategory, orElse: () => _categories.first)['emoji']!;
                  return Marker(
                    point: LatLng(p['lat'] as double, p['lng'] as double),
                    width: sel ? 64 : 46,
                    height: sel ? 80 : 58,
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _selectPlace(p),
                      child: AnimatedScale(
                        scale: sel ? 1.0 : 0.92,
                        duration: const Duration(milliseconds: 180),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: sel ? 54 : 40, height: sel ? 54 : 40,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                                colors: [Color(0xFFE3C878), _gold, Color(0xFF9C7E2E)],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: sel ? 3 : 2.4),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withAlpha(140), blurRadius: 10, offset: const Offset(0, 5)),
                                if (sel) BoxShadow(color: _gold.withAlpha(140), blurRadius: 18, spreadRadius: 2),
                              ],
                            ),
                            child: Center(child: Text(emoji, style: TextStyle(fontSize: sel ? 26 : 19))),
                          ),
                          Container(
                            width: sel ? 6 : 5, height: sel ? 15 : 11,
                            decoration: BoxDecoration(
                              color: const Color(0xFF9C7E2E),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  );
                }),
              ]),
            ],
          ),
        ),

        // ── TOP: search + categories ──
        SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: _glass(dark,
                radius: BorderRadius.circular(26),
                child: Row(children: [
                  const SizedBox(width: 14),
                  Icon(Icons.search_rounded, color: _gold, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      onTap: () => setState(() => _searchOpen = true),
                      onChanged: _onSearchChanged,
                      onSubmitted: _runSearch,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: onGlass, fontSize: 14.5, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Search churches, places…',
                        hintStyle: TextStyle(color: muted, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () { _searchCtrl.clear(); setState(() => _suggestions = []); },
                      child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.close_rounded, color: muted, size: 19)),
                    ),
                  const SizedBox(width: 10),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  ..._categories.map((c) {
                    final active = c['id'] == _activeCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _loadCategory(c['id']!),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: active ? _gold : (dark ? Colors.black : Colors.white).withAlpha(dark ? 150 : 190),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: active ? _gold : (dark ? Colors.white24 : Colors.black12), width: 0.7),
                            boxShadow: [BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 8, offset: const Offset(0, 3))],
                          ),
                          child: Row(children: [
                            Text(c['emoji']!, style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(c['label']!, style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700,
                              color: active ? Colors.white : onGlass,
                            )),
                          ]),
                        ),
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _showNearbyList,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: (dark ? Colors.black : Colors.white).withAlpha(dark ? 150 : 190),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: dark ? Colors.white24 : Colors.black12, width: 0.7),
                        ),
                        child: Row(children: [
                          Icon(Icons.format_list_bulleted_rounded, size: 15, color: _gold),
                          const SizedBox(width: 6),
                          Text('Nearby', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: onGlass)),
                        ]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _showFavorites,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: (dark ? Colors.black : Colors.white).withAlpha(dark ? 150 : 190),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: dark ? Colors.white24 : Colors.black12, width: 0.7),
                        ),
                        child: Row(children: [
                          const Text('⭐', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text('Saved', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: onGlass)),
                        ]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _openInGoogleMaps,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF4285F4), Color(0xFF2E7CF6)]),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: const Color(0xFF2E7CF6).withAlpha(90), blurRadius: 10, offset: const Offset(0, 3))],
                        ),
                        child: const Row(children: [
                          Icon(Icons.map_rounded, size: 15, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Open in Google Maps', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Suggestions / recents panel
            if (_searchOpen && (_suggestions.isNotEmpty || (_recents.isNotEmpty && _searchCtrl.text.isEmpty)))
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: _glass(dark,
                  radius: BorderRadius.circular(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_suggestions.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(children: [
                          Icon(Icons.history_rounded, size: 15, color: muted),
                          const SizedBox(width: 8),
                          Text('RECENT', style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w800, color: muted)),
                        ]),
                      ),
                      ..._recents.take(5).map((r) => InkWell(
                        onTap: () { _searchCtrl.text = r; _runSearch(r); },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                          child: Row(children: [
                            Icon(Icons.north_west_rounded, size: 15, color: muted),
                            const SizedBox(width: 12),
                            Expanded(child: Text(r, style: TextStyle(color: onGlass, fontSize: 13.5))),
                          ]),
                        ),
                      )),
                    ] else
                      ..._suggestions.map((s) => InkWell(
                        onTap: () {
                          _searchCtrl.text = s['name'] as String;
                          setState(() { _places = [s]; _suggestions = []; _searchOpen = false; });
                          _searchFocus.unfocus();
                          _saveRecent(s['name'] as String);
                          _selectPlace(s);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(children: [
                            Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(color: _gold.withAlpha(40), borderRadius: BorderRadius.circular(10)),
                              child: Icon(Icons.place_rounded, color: _gold, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: onGlass, fontSize: 13.5, fontWeight: FontWeight.w600)),
                              if ((s['sub'] as String).isNotEmpty)
                                Text(s['sub'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: muted, fontSize: 11.5)),
                            ])),
                            if (s['dist'] != null)
                              Text('${(s['dist'] as double).toStringAsFixed(1)} km',
                                style: TextStyle(color: _gold, fontSize: 11.5, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      )),
                    const SizedBox(height: 6),
                  ]),
                ),
              ),
          ]),
        ),

        // ── RIGHT controls ──
        Positioned(
          right: 12,
          top: MediaQuery.of(context).padding.top + 116,
          child: Column(children: [
            if (_rotation.abs() > 2) ...[
              _fab(dark, onTap: _resetNorth, child: Transform.rotate(
                angle: -_rotation * math.pi / 180,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('N', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFFD64541))),
                  Icon(Icons.navigation_rounded, size: 14, color: onGlass),
                ]),
              )),
              const SizedBox(height: 10),
            ],
            _fab(dark, onTap: _showLayers, child: Icon(Icons.layers_rounded, color: onGlass, size: 21)),
            const SizedBox(height: 10),
            _fab(dark, onTap: () {
              if (_lat != null) { _flyTo(LatLng(_lat!, _lng!), 15.2); } else { _initLocation(); }
            }, child: Icon(Icons.my_location_rounded, color: _gold, size: 21)),
            const SizedBox(height: 10),
            _fab(dark, onTap: () => _flyTo(_center, math.min(19, _zoom + 1)),
              child: Icon(Icons.add_rounded, color: onGlass, size: 23)),
            const SizedBox(height: 10),
            _fab(dark, onTap: () => _flyTo(_center, math.max(3, _zoom - 1)),
              child: Icon(Icons.remove_rounded, color: onGlass, size: 23)),
          ]),
        ),

        // ── Scale + attribution ──
        Positioned(
          left: 14,
          bottom: (_sel != null ? 196 : 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (dark ? Colors.black : Colors.white).withAlpha(140),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_scaleLabel(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: onGlass)),
                const SizedBox(height: 2),
                Container(width: _scaleWidth(), height: 2.5,
                  decoration: BoxDecoration(color: onGlass, borderRadius: BorderRadius.circular(2))),
              ]),
            ),
            const SizedBox(height: 4),
            Text('© OpenStreetMap · CARTO · Esri',
              style: TextStyle(fontSize: 8.5, color: (dark ? Colors.white : Colors.black).withAlpha(110))),
          ]),
        ),

        // ── Busy indicator ──
        if (_busy)
          Positioned(
            top: MediaQuery.of(context).padding.top + 118,
            left: 0, right: 0,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: (dark ? Colors.black : Colors.white).withAlpha(200),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(40), blurRadius: 10)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _gold)),
                const SizedBox(width: 10),
                Text('Finding places…', style: TextStyle(fontSize: 12, color: onGlass, fontWeight: FontWeight.w600)),
              ]),
            )),
          ),

        // ── Locating pill (non-blocking) ──
        if (_locating)
          Positioned(
            top: MediaQuery.of(context).padding.top + 160,
            left: 0, right: 0,
            child: IgnorePointer(child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: (dark ? Colors.black : Colors.white).withAlpha(210),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 12)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: _gold)),
                const SizedBox(width: 10),
                Text('Finding you…', style: TextStyle(color: onGlass, fontWeight: FontWeight.w600, fontSize: 12.5)),
              ]),
            ))),
          ),

        // ── Error toast ──
        if (_error.isNotEmpty && !_locating)
          Positioned(
            left: 14, right: 14, bottom: 30,
            child: _glass(dark,
              radius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.location_off_rounded, color: const Color(0xFFD64541), size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_error, style: TextStyle(color: onGlass, fontSize: 13))),
                  GestureDetector(
                    onTap: () async {
                      if (_locFix == 1) {
                        await Geolocator.openLocationSettings();
                      } else if (_locFix == 2) {
                        await Geolocator.openAppSettings();
                      }
                      _initLocation();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(12)),
                      child: Text(_locFix == 0 ? 'Retry' : 'Open Settings',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                ]),
              ),
            ),
          ),

        // ── Place detail sheet ──
        AnimatedPositioned(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          left: 12, right: 12,
          bottom: _sel != null ? 14 : -260,
          child: _sel == null ? const SizedBox() : _glass(dark,
            radius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 38, height: 4,
                  decoration: BoxDecoration(color: muted.withAlpha(90), borderRadius: BorderRadius.circular(3)))),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFE3C878), _gold]),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [BoxShadow(color: _gold.withAlpha(90), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Center(child: Text(
                      _categories.firstWhere((c) => c['id'] == _activeCategory, orElse: () => _categories.first)['emoji']!,
                      style: const TextStyle(fontSize: 25))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_sel!['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: onGlass, height: 1.2)),
                    const SizedBox(height: 3),
                    if ((_sel!['sub'] as String? ?? '').isNotEmpty)
                      Text(_sel!['sub'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: muted)),
                    const SizedBox(height: 5),
                    Row(children: [
                      if (_sel!['rating'] != null) ...[
                        Icon(Icons.star_rounded, size: 15, color: const Color(0xFFF2B01E)),
                        const SizedBox(width: 3),
                        Text((_sel!['rating'] as double).toStringAsFixed(1),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: onGlass)),
                        if (_sel!['ratings'] != null)
                          Text(' (${_sel!['ratings']})', style: TextStyle(fontSize: 11, color: muted)),
                        const SizedBox(width: 10),
                      ],
                      if (_sel!['dist'] != null)
                        Text('${(_sel!['dist'] as double).toStringAsFixed(1)} km',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _gold)),
                      if (_sel!['open'] == true) ...[
                        const SizedBox(width: 10),
                        Text('Open', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF3CA55C))),
                      ] else if (_sel!['open'] == false) ...[
                        const SizedBox(width: 10),
                        Text('Closed', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFFD64541))),
                      ],
                    ]),
                  ])),
                  GestureDetector(
                    onTap: () => _toggleFav(_sel!),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _isFav(_sel!) ? _gold.withAlpha(50) : muted.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isFav(_sel!) ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: _isFav(_sel!) ? _gold : muted, size: 22),
                    ),
                  ),
                ]),
                if (_sel!['dist'] != null) ...[
                  const SizedBox(height: 8),
                  Text(_eta(_sel!), style: TextStyle(fontSize: 11.5, color: muted, fontWeight: FontWeight.w600)),
                ],
                if (_routePoints.isNotEmpty && _routeDistanceKm != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.route_rounded, size: 14, color: _gold),
                    const SizedBox(width: 5),
                    Text('${_routeDistanceKm!.toStringAsFixed(1)} km on the map · ~$_routeDurationMin min',
                      style: TextStyle(fontSize: 11.5, color: _gold, fontWeight: FontWeight.w700)),
                  ]),
                ],
                if (_routeError != null) ...[
                  const SizedBox(height: 8),
                  Text(_routeError!, style: const TextStyle(fontSize: 11.5, color: Color(0xFFD64541), fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(flex: 3, child: GestureDetector(
                    onTap: _routing ? null : () => _routePoints.isNotEmpty ? _clearRoute() : _showRoute(_sel!),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFE3C878), _gold, Color(0xFFA98937)]),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [BoxShadow(color: _gold.withAlpha(110), blurRadius: 14, offset: const Offset(0, 5))],
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        if (_routing) ...[
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)),
                          const SizedBox(width: 8),
                          const Text('Finding route…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        ] else if (_routePoints.isNotEmpty) ...[
                          const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          const Text('Clear Route', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        ] else ...[
                          const Icon(Icons.route_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          const Text('Route', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        ],
                      ]),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: GestureDetector(
                    onTap: () => _sharePlace(_sel!),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: muted.withAlpha(28),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: muted.withAlpha(60), width: 0.8),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.ios_share_rounded, color: onGlass, size: 17),
                        const SizedBox(width: 7),
                        Text('Share', style: TextStyle(color: onGlass, fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ]),
                    ),
                  )),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Glass helpers ──
  Widget _glass(bool dark, {required Widget child, BorderRadius? radius}) {
    return ClipRRect(
      borderRadius: radius ?? BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: (dark ? const Color(0xFF17130C) : Colors.white).withAlpha(dark ? 165 : 185),
            borderRadius: radius ?? BorderRadius.circular(22),
            border: Border.all(color: (dark ? Colors.white : Colors.black).withAlpha(dark ? 30 : 18), width: 0.8),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(dark ? 90 : 35), blurRadius: 22, offset: const Offset(0, 8))],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _fab(bool dark, {required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: (dark ? const Color(0xFF17130C) : Colors.white).withAlpha(dark ? 170 : 195),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: (dark ? Colors.white : Colors.black).withAlpha(dark ? 30 : 16), width: 0.8),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(dark ? 100 : 40), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  // ── Sheets ──
  void _showLayers() {
    final dark = widget.isDark;
    final onGlass = dark ? Colors.white : const Color(0xFF15130E);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: _glass(dark,
          radius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 38, height: 4,
                decoration: BoxDecoration(color: onGlass.withAlpha(60), borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 14),
              Text('Map style', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: onGlass)),
              const SizedBox(height: 14),
              Row(children: List.generate(4, (i) {
                const names = ['Standard', 'Satellite', 'Hybrid', 'Terrain'];
                const icons = [Icons.map_rounded, Icons.satellite_alt_rounded, Icons.layers_rounded, Icons.terrain_rounded];
                final active = _style == i;
                return Expanded(child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 10 : 0),
                  child: GestureDetector(
                    onTap: () { setState(() => _style = i); Navigator.pop(ctx); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 76,
                      decoration: BoxDecoration(
                        color: active ? _gold : onGlass.withAlpha(14),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: active ? _gold : onGlass.withAlpha(35), width: active ? 1.6 : 0.7),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(icons[i], size: 24, color: active ? Colors.white : onGlass),
                        const SizedBox(height: 6),
                        Text(names[i], style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700,
                          color: active ? Colors.white : onGlass)),
                      ]),
                    ),
                  ),
                ));
              })),
            ]),
          ),
        ),
      ),
    );
  }


  void _showFavorites() {
    final dark = widget.isDark;
    final onGlass = dark ? Colors.white : const Color(0xFF15130E);
    final muted = dark ? Colors.white60 : Colors.black54;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: _glass(dark,
          radius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 38, height: 4,
                decoration: BoxDecoration(color: onGlass.withAlpha(60), borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 14),
              Row(children: [
                const Text('⭐', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text('Saved places', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: onGlass)),
              ]),
              const SizedBox(height: 10),
              if (_favorites.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('Tap ⭐ on any place to save it here.',
                    style: TextStyle(color: muted, fontSize: 13))),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView(shrinkWrap: true, children: _favorites.map((f) => InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      if (!_places.any((p) => p['place_id'] == f['place_id'])) {
                        setState(() => _places = [f, ..._places]);
                      }
                      _selectPlace(f);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(color: _gold.withAlpha(45), borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.place_rounded, color: _gold, size: 19),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(f['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: onGlass, fontSize: 13.5, fontWeight: FontWeight.w600))),
                        GestureDetector(
                          onTap: () { _toggleFav(f); Navigator.pop(ctx); _showFavorites(); },
                          child: Icon(Icons.close_rounded, size: 17, color: muted),
                        ),
                      ]),
                    ),
                  )).toList()),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class SaintStoryScreen extends StatelessWidget {
  final bool isDark;
  final String feastName;
  final String dateLabel;
  final bool isAnnual;
  final String? story;
  const SaintStoryScreen({
    super.key, required this.isDark, required this.feastName,
    required this.dateLabel, required this.isAnnual, this.story,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors(isDark);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        Container(
          color: c.hero, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(children: [
            GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.arrow_back_ios, color: c.gold, size: 20)),
            const SizedBox(width: 12),
            Container(width: 4, height: 20, color: c.gold, margin: const EdgeInsets.only(right: 10)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SYNAXARIUM', style: TextStyle(fontSize: 13, color: c.text, letterSpacing: 2, fontWeight: FontWeight.w800)),
              Text('ስንክሳር', style: TextStyle(fontSize: 11, color: c.muted, fontStyle: FontStyle.italic)),
            ])),
          ]),
        ),
        Divider(color: c.border, height: 0.5),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Column(children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: c.goldBg, shape: BoxShape.circle,
                    border: Border.all(color: c.gold, width: 2),
                    boxShadow: [BoxShadow(color: c.gold.withAlpha(60), blurRadius: 16, spreadRadius: 2)],
                  ),
                  child: Center(child: Text(isAnnual ? '⭐' : '☩', style: TextStyle(fontSize: 36, color: c.gold))),
                ),
                const SizedBox(height: 16),
                Text(feastName, style: TextStyle(fontSize: 20, color: c.text, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(dateLabel, style: TextStyle(fontSize: 13, color: c.muted, fontStyle: FontStyle.italic)),
                if (isAnnual) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: c.gold.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                    child: Text('ዓመታዊ በዓል — Annual Feast', style: TextStyle(fontSize: 11, color: c.gold, fontWeight: FontWeight.w700)),
                  ),
                ],
              ])),
              const SizedBox(height: 28),
              Container(height: 0.5, color: c.border),
              const SizedBox(height: 24),
              if (story != null) ...[
                Row(children: [
                  Container(width: 3, height: 14, color: c.gold, margin: const EdgeInsets.only(right: 8)),
                  Text('THE STORY', style: TextStyle(fontSize: 10, color: c.label, letterSpacing: 2, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 12),
                Text(story!, style: TextStyle(fontSize: 15, color: c.text, height: 1.9)),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border, width: 0.5)),
                  child: Column(children: [
                    Text('📖', style: const TextStyle(fontSize: 32)),
                    const SizedBox(height: 12),
                    Text(
                      'The full story for this day is still being added to the Synaxarium.',
                      style: TextStyle(fontSize: 13, color: c.muted, height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'የዚህ ቀን ሙሉ ታሪክ ወደ ስንክሳር በመጨመር ላይ ነው።',
                      style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic, height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ])),
    );
  }
}

class MoreScreen extends StatefulWidget {
  final bool isDark;
  const MoreScreen({super.key, required this.isDark});
  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _notificationsEnabled = true;
  double _fontSize = 1.0;
  UserProfile? _profile;

  @override
  void initState() { super.initState(); _loadPrefs(); }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_profile');
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _fontSize = prefs.getDouble('font_size') ?? 1.0;
      if (raw != null) _profile = UserProfile.fromJson(jsonDecode(raw));
    });
  }

  Future<void> _saveNotif(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', val);
    setState(() => _notificationsEnabled = val);
    if (!val) await notificationsPlugin.cancelAll();
  }

  Future<void> _saveFontSize(double val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_size', val);
    setState(() => _fontSize = val);
    fontSizeNotifier.value = val;
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const YenefsAbatApp()),
      (route) => false,
    );
  }

  void _shareApp() {
    final c = AppColors(widget.isDark);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Share Yenefs_Abat', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Share this app with your friends and family:', style: TextStyle(color: c.muted, fontSize: 13)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
          child: SelectableText('https://play.google.com/store/apps/details?id=com.yenefsabat.yenefs_abat', style: TextStyle(fontSize: 12, color: c.gold)),
        ),
        const SizedBox(height: 10),
        Text('You can also share via Xender, Bluetooth, WhatsApp, Telegram and other apps.', style: TextStyle(color: c.muted, fontSize: 12)),
      ]),
      actions: [GestureDetector(onTap: () => Navigator.pop(ctx), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(8)), child: Text('OK', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700))))],
    ));
  }

  void _showAbout() {
    final c = AppColors(widget.isDark);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('About Yenefs_Abat', style: TextStyle(color: c.gold, fontWeight: FontWeight.w800, fontSize: 18)),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 80, height: 80, decoration: const BoxDecoration(shape: BoxShape.circle), child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.cover)))),
        const SizedBox(height: 12),
        Text('English', style: TextStyle(color: c.gold, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        Text('This app was created by students of Finote Yared Abenet School of Jemo Medhanialem, dedicated to Yeneta Yohannes — Teacher of the Abenet School and Scholar of Degua.', style: TextStyle(color: c.text, fontSize: 13, height: 1.6)),
        const SizedBox(height: 14),
        Text('አማርኛ', style: TextStyle(color: c.gold, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        Text('ይህ መተግበሪያ በጀሞ መድኃኔዓለም የፍኖተ ያሬድ አቤኔት ትምህርት ቤት ተማሪዎች የተሠራ ሲሆን፣ ለ"የኔታ ዮሐንስ" — የአቤኔት ትምህርት ቤቱ መምህርና የድጓ ምሁር — የተሰጠ ትሩፋት ነው።', style: TextStyle(color: c.text, fontSize: 13, height: 1.6)),
        const SizedBox(height: 14),
        Container(height: 0.5, color: c.border),
        const SizedBox(height: 10),
        Text('Version 1.0.0', style: TextStyle(color: c.muted, fontSize: 12)),
      ])),
      actions: [GestureDetector(onTap: () => Navigator.pop(ctx), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(8)), child: Text('Close', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700))))],
    ));
  }

  void _showLicense() {
    final c = AppColors(widget.isDark);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('MIT License', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(child: Text(
        'Copyright (c) 2026 Finote Yared Abenet School\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files, to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software.\n\nTHE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.',
        style: TextStyle(fontSize: 12, color: c.muted, height: 1.6),
      )),
      actions: [GestureDetector(onTap: () => Navigator.pop(ctx), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(8)), child: Text('Close', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700))))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        Container(color: c.hero, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), child: Row(children: [
          Container(width: 4, height: 20, color: c.gold, margin: const EdgeInsets.only(right: 10)),
          Text('MORE', style: TextStyle(fontSize: 16, color: c.text, letterSpacing: 3, fontWeight: FontWeight.w800)),
        ])),
        Divider(color: c.border, height: 0.5),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(children: [
          _sectionLabel('ACCOUNT', c),
          _settingsCard(c, children: [
            if (_profile != null) ...[
              _infoRow(_profile!.name, _profile!.role, Icons.person_outline, c),
              Divider(color: c.border, height: 0.5),
            ],
            _actionRow('Log Out', Icons.logout, c, c.red, _logout),
          ]),
          _sectionLabel('SPIRITUAL LIFE', c),
          _settingsCard(c, children: [
            _actionRow('Prayer Library', Icons.menu_book_outlined, c, c.gold, () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => PrayerLibraryScreen(isDark: widget.isDark)))),
          ]),
          _sectionLabel('NOTIFICATIONS', c),
          _settingsCard(c, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Icon(Icons.notifications_outlined, color: c.gold, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Prayer Notifications', style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w600)),
                  Text('Church bell at prayer times', style: TextStyle(fontSize: 12, color: c.muted)),
                ])),
                Switch(value: _notificationsEnabled, onChanged: _saveNotif, activeThumbColor: c.gold),
              ]),
            ),
          ]),
          _sectionLabel('DISPLAY', c),
          _settingsCard(c, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.format_size, color: c.gold, size: 20),
                  const SizedBox(width: 12),
                  Text('Font Size', style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(_fontSize < 0.9 ? 'Small' : _fontSize > 1.1 ? 'Large' : 'Medium', style: TextStyle(fontSize: 12, color: c.gold, fontWeight: FontWeight.w600)),
                ]),
                Slider(value: _fontSize, min: 0.8, max: 1.4, divisions: 6, activeColor: c.gold, inactiveColor: c.border, onChanged: _saveFontSize),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('A', style: TextStyle(fontSize: 10, color: c.muted)),
                  Text('A', style: TextStyle(fontSize: 18, color: c.muted, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
          ]),
          _sectionLabel('APP', c),
          _settingsCard(c, children: [
            _actionRow('Rate Us', Icons.star_outline, c, c.gold, () {
              showDialog(context: context, builder: (ctx) => AlertDialog(
                backgroundColor: c.card,
                title: Text('Rate Yenefs_Abat', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
                content: Text('Thank you! Please rate us on the Play Store.', style: TextStyle(color: c.muted, fontSize: 13)),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK', style: TextStyle(color: c.gold)))],
              ));
            }),
            Divider(color: c.border, height: 0.5),
            _actionRow('Share App', Icons.share_outlined, c, c.gold, _shareApp),
            Divider(color: c.border, height: 0.5),
            _actionRow('Contact Us', Icons.email_outlined, c, c.gold, () {
              showDialog(context: context, builder: (ctx) => AlertDialog(
                backgroundColor: c.card,
                title: Text('Contact Us', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
                content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Send us an email:', style: TextStyle(color: c.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
                    child: SelectableText('yenefsabat@gmail.com', style: TextStyle(color: c.gold, fontSize: 14, fontWeight: FontWeight.w600))),
                  const SizedBox(height: 8),
                  Text('Tap and hold the email to copy it.', style: TextStyle(color: c.muted, fontSize: 12)),
                ]),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK', style: TextStyle(color: c.gold)))],
              ));
            }),
          ]),
          _sectionLabel('INFORMATION', c),
          _settingsCard(c, children: [
            _actionRow('About Us', Icons.info_outline, c, c.gold, _showAbout),
            Divider(color: c.border, height: 0.5),
            _actionRow('License (MIT)', Icons.description_outlined, c, c.gold, _showLicense),
          ]),
          const SizedBox(height: 24),
          Text('Yenefs_Abat v1.0.0', style: TextStyle(fontSize: 11, color: c.muted, fontStyle: FontStyle.italic)),
          Text('Made with love for EOTC faithful', style: TextStyle(fontSize: 11, color: c.muted, fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
        ]))),
      ])),
    );
  }

  Widget _sectionLabel(String t, AppColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Row(children: [
      Container(width: 3, height: 12, color: c.gold, margin: const EdgeInsets.only(right: 8)),
      Text(t, style: TextStyle(fontSize: 10, color: c.label, letterSpacing: 3, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _settingsCard(AppColors c, {required List<Widget> children}) => Container(
    decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border, width: 0.5), boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))]),
    child: Column(children: children),
  );

  Widget _actionRow(String label, IconData icon, AppColors c, Color iconColor, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w600))),
        Icon(Icons.chevron_right, color: c.muted, size: 18),
      ]),
    ),
  );

  Widget _infoRow(String name, String role, IconData icon, AppColors c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Container(width: 40, height: 40, decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold, width: 0.5)), child: Center(child: Icon(icon, color: c.gold, size: 20))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w700)),
        Text(role, style: TextStyle(fontSize: 12, color: c.muted)),
      ])),
    ]),
  );
}

// ═══════════════════════════════════════════════
// PRAYER LIBRARY — የጸሎት መጽሐፍ
// ═══════════════════════════════════════════════

// A named part within a multi-part prayer (e.g. a booklet like Zewter
// Tselot bundles several distinct prayers together, each with its own
// title). Leave a PrayerItem's `sections` empty for a single-block prayer.
class PrayerSection {
  final String titleAmharic;
  final String titleGeez;
  final String geezText;
  final String amharicText;
  const PrayerSection({
    required this.titleAmharic,
    required this.titleGeez,
    required this.geezText,
    required this.amharicText,
  });
}

class PrayerItem {
  final String id;
  final String titleGeez;
  final String titleAmharic;
  final String category; // Daily, Praise, Repentance, Liturgy
  final String timeOfDay;
  final String geezText;
  final String amharicTranslation;
  final List<PrayerSection> sections;
  const PrayerItem({
    required this.id,
    required this.titleGeez,
    required this.titleAmharic,
    required this.category,
    required this.timeOfDay,
    required this.geezText,
    required this.amharicTranslation,
    this.sections = const [],
  });
}

const List<PrayerItem> orthodoxPrayerSource = [
  PrayerItem(
    id: 'pr-1',
    titleGeez: 'በስመ አብ ወወልድ ወመንፈስ ቅዱስ',
    titleAmharic: 'አባታችን ሆይ (የዘወትር ጸሎት)',
    category: 'Daily',
    timeOfDay: 'Morning / Evening',
    geezText: 'አቡነ ዘበሰማያት ይትቀደስ ስምከ፤ ትምጻእ መንግሥትከ፤ ወይኩን ፈቃድከ በከመ በሰማይ ከማሁ በምድር፤ ሲሳየነ ዘለለ ዕለትነ ሀበነ ዮም፤ ኅድግ ለነ አበሳነ ወጌጋየነ ከመ ንሕነኒ ንኅድግ ለዘአበሰ ለነ፤ ኢታብኦነ እግዚኦ ውስተ መንሱት፤ አላ አድኅነነ ወባልሐነ እምኩሉ እኩይ፤ እስመ ዚአከ ይእቲ መንግሥት ኃይል ወስብሐት ለዓለመ ዓለም አሜን።',
    amharicTranslation: 'በሰማያት የምትኖር አባታችን ሆይ፤ ስምህ ይቀደስ፤ መንግሥትህ ትምጣ፤ ፈቃድህ በሰማይ እንደ ሆነች እንዲሁ በምድር ትሁን፤ የዕለት እንጀራችንን ስጠን ዛሬ፤ በደላችንንም ይቅር በለን፤ እኛም የበደሉንን ይቅር እንደምንል፤ አቤቱ ወደ ፈተና አታግባን፤ ከክፉ ሁሉ አድነን እንጂ፤ መንግሥት ያንተ ናትና ኃይልም ስብሐትም ለዘለዓለሙ አሜን።',
    // NOTE: the Creed (የሃይማኖት ጸሎት) section is intentionally left out of
    // this list — the text supplied for it had corrupted fragments
    // ("በብHierarchy", "በ his ዮ P ጲላጦስ") that read like a generation
    // glitch, not real Ge'ez. Add it back once the correct wording is
    // confirmed.
    sections: [
      PrayerSection(
        titleAmharic: 'የመክፈቻ ጸሎት',
        titleGeez: 'በስመ አብ ወወልድ ወመንፈስ ቅዱስ',
        geezText: 'በስመ አብ ወወልድ ወመንፈስ ቅዱስ አሐዱ አምላክ አሜን።\nስብሐት ለአብ፤ ስብሐት ለወልድ፤ ስብሐት ለመንፈስ ቅዱስ። (፫ ጊዜ)\nአአምን በአሐዱ አምላክ አምላከ ጽድቅ።\nአአምን በክርስቶስ አምላኪየ ዘአንሥአኒ እምነ ሞት።\nአአምን በመንፈስ ቅዱስ ዘያሐይወነ።',
        amharicText: 'አንድ አምላክ በሚሆን በአብ በወልድ በመንፈስ ቅዱስ ስም አሜን።\nለአብ ምስጋና ይሁን፤ ለወልድ ምስጋና ይሁን፤ ለመንፈስ ቅዱስም ምስጋና ይሁን። (3 ጊዜ)\nእውነተኛ አምላክ በሚሆን በአንድ አምላክ እምናለሁ።\nከሞት ባነሣኝ በአምላኬ በክርስቶስ እምናለሁ።\nሕይወትን በሚሰጠን በመንፈስ ቅዱስ እምናለሁ።',
      ),
      PrayerSection(
        titleAmharic: 'የጌታችን ጸሎት (አባታችን ሆይ)',
        titleGeez: 'አቡነ ዘበሰማያት',
        geezText: 'አቡነ ዘበሰማያት፤ ይትቀደስ ስምከ፤ ትምጻእ መንግሥትከ፤ ወይኩን ፈቃድከ በከመ በሰማይ፤ ከማሁ በምድር፤ ሲሳየነ ዘለለ ዕለትነ ሀበነ ዮም፤ ኅድግ ለነ አበሳነ ወጌጋየነ፤ ከመ ንሕነኒ ንኅድግ ለዘአበሰ ለነ፤ ኢታብኦነ እግዚኦ ውስተ መንሱት፤ አላ አድኅነነ ወባልሐነ እምኩሉ እኩይ፤ እስመ ዚአከ ይእቲ መንግሥት፤ ኃይል ወስብሐት፤ ለዓለመ ዓለም አሜን።',
        amharicText: 'በሰማያት የምትኖር አባታችን ሆይ፤ ስምህ ይቀደስ፤ መንግሥትህ ትምጣ፤ ፈቃድህ በሰማይ እንደ ሆነች እንዲሁ በምድር ትሁን፤ የዕለት እንጀራችንን ስጠን ዛሬ፤ በደላችንንም ይቅር በለን፤ እኛም የበደሉንን ይቅር እንደምንል፤ አቤቱ ወደ ፈተና አታግባን፤ ከክፉ ሁሉ አድነን እንጂ፤ መንግሥት ያንተ ናትና ኃይልም ስብሐትም ለዘለዓለሙ አሜን።',
      ),
      PrayerSection(
        titleAmharic: 'የእመቤታችን ጸሎት (ሰላምታ)',
        titleGeez: 'ሰላም ለኪ',
        geezText: 'በሰላመ ቅዱስ ገብርኤል መልአክ፤ እግዝእትየ ማርያም ሰላም ለኪ፤ ድንግል ብኅሊናኪ ወድንግል በሥጋኪ፤ እመ እግዚአብሔር ጸባኦት ሰላም ለኪ፤ ቡሩክት አንቲ እምአንስት ወቡሩክ ፍሬ ከርሥኪ፤ ተፈሥሒ ፍሥሕት ኦ ምልእተ ጸጋ፤ እግዚአብሔር ምስሌኪ፤ ሰአሊ ወጸልዪ ምሕረተ በኀበ ፍቁር ወልድኪ፤ ኢየሱስ ክርስቶስ፤ ከመ ይሥረይ ለነ ኃጣውኢነ አሜን።',
        amharicText: 'በቅዱስ ገብርኤል መልአክ ሰላምታ እመቤታችን ቅድስት ድንግል ማርያም ሆይ ሰላም እንልሻለን፤ በሐሳብሽ ድንግል ነሽ፤ በሥጋሽም ድንግል ነሽ፤ የሠራዊት ጌታ የእግዚአብሔር እናት ሆይ ሰላምታ ይገባሻል፤ ከሴቶች ሁሉ ተለይተሽ የተባረክሽ ነሽ፤ የሆድሽም ፍሬ የተባረከ ነው፤ ጸጋን የተሞላሽ ሆይ ደስ ይበልሽ እግዚአብሔር ከአንቺ ጋር ነውና፤ ከፍቅር ልጅሽ ከጌታችን ከኢየሱስ ክርስቶስ ዘንድ ይቅርታንና ምሕረትን ለምኚልን ኃጢአታችንንም ይሠረይልን ዘንድ ለዘለዓለሙ አሜን።',
      ),
      PrayerSection(
        titleAmharic: 'ቅዱስ ቅዱስ ቅዱስ (የመላእክት ምስጋና)',
        titleGeez: 'ቅዱስ ቅዱስ ቅዱስ',
        geezText: 'ቅዱስ ቅዱስ ቅዱስ እግዚአብሔር ጸባኦት ፍጹም ምሉዕ ሰማያተ ወምድረ ቅድሳተ ስብሐቲከ።\nንሰግድ ለከ ክርስቶስ ምስለ አቡከ ኄር ሰማያዊ ወመንፈስከ ቅዱስ ማሕየዊ እስመ መጻእከ ወአድኃንከነ።',
        amharicText: 'የሠራዊት ጌታ እግዚአብሔር ቅዱስ ቅዱስ ቅዱስ ተብሎ ይመሰገናል። የምስጋናህ ቅድስና በሰማይና በምድር የመላ ነው።\nክርስቶስ ሆይ ከቸር ከሰማያዊ አባትህ ጋር ሕይወትን ከሚሰጥ ከቅዱስ መንፈስህ ጋር እንሰግድልሃለን፤ መጥተህ አድነኸናልና።',
      ),
      PrayerSection(
        titleAmharic: 'የእመቤታችን ምስጋና (ሰላም ለኪ)',
        titleGeez: 'ስብሐት ለኪ ኦ እግዝእትነ',
        geezText: 'ለአብ ወወልድ ወመንፈስ ቅዱስ ስብሐት ወዕዝዝ ይእዜኒ ወዘልፈኒ ወለዓለመ ዓለም አሜን።\nተፈሥሒ ኦ ምልእተ ጸጋ፤ ተፈሥሒ እስመ ረከብኪ ጸጋ፤ ተፈሥሒ እግዚአብሔር ምስሌኪ።\nቡሩክት አንቲ እምአንስት፤ ወቡሩክ ፍሬ ከርሥኪ፤ ሰአሊ ወጸልዪ በኀበ ፍቁር ወልድኪ ከመ ይሥረይ ለነ ኃጣውኢነ።',
        amharicText: 'ለአብ ለወልድ ለመንፈስ ቅዱስ ምስጋናና ጌትነት ይገባል፤ ዛሬም ዘወትርም ለዘለዓለሙ አሜን።\nጸጋን የተሞላሽ ሆይ ደስ ይበልሽ፤ ጸጋን አግኝተሻልና ደስ ይበልሽ፤ እግዚአብሔር ከአንቺ ጋር ነውና ደስ ይበልሽ።\nከሴቶች ሁሉ ተለይተሽ የተባረክሽ ነሽ፤ የሆድሽም ፍሬ የተባረከ ነው፤ ኃጢአታችንን ይሠረይልን ዘንድ ከፍቅር ልጅሽ ዘንድ ለምኚልን።',
      ),
    ],
  ),
  PrayerItem(
    id: 'pr-2',
    titleGeez: 'ሰላም ለኪ ማርያም',
    titleAmharic: 'እመቤታችን ማርያም ሆይ ሰላምታ ይገባሻል',
    category: 'Praise',
    timeOfDay: 'Daily',
    geezText: 'በሰላመ ቅዱስ ገብርኤል መልአክ፡ እግዝእትየ ማርያም ሰላም ለኪ፤ ድንግል ብኅሊናኪ ወድንግል በሥጋኪ፤ እመ እግዚአብሔር ጸባኦት ሰላም ለኪ፤ ቡሩክት አንቲ እምአንስት ወቡሩክ ፍሬ ከርሥኪ፤ ተፈሥሒ ፍሥሕት ኦ ምልእተ ጸጋ እግዚአብሔር ምስሌኪ፤ ሰአሊ ወጸልዪ ምሕረተ በኀበ ፍቁር ወልድኪ ኢየሱስ ክርስቶስ ከመ ይሥረይ ለነ ኃጣውኢነ አሜን።',
    amharicTranslation: 'እመቤታችን ቅድስት ድንግል ማርያም ሆይ፤ በቅዱስ ገብርኤል መልአክ ሰላምታ ሰላም እንልሻለን፤ በሐሳብሽ ድንግል ነሽ፤ በሥጋሽም ድንግል ነሽ፤ የሠራዊት ጌታ የእግዚአብሔር እናት ሆይ ሰላምታ ይገባሻል፤ ከሴቶች ሁሉ ተለይተሽ የተባረክሽ ነሽ፤ የሆድሽም ፍሬ የተባረከ ነው፤ ጸጋን የተሞላሽ ሆይ ደስ ይበልሽ እግዚአብሔር ከአንቺ ጋር ነውና፤ ከፍቅር ልጅሽ ከጌታችን ከኢየሱስ ክርስቶስ ዘንድ ይቅርታንና ምሕረትን ለምኚልን ኃጢአታችንንም ይሠረይልን ዘንድ ለዘለዓለሙ አሜን።',
  ),
  PrayerItem(
    id: 'pr-3',
    titleGeez: 'ውዳሴ ማርያም (ዘሰኞ)',
    titleAmharic: 'የሰኞ ውዳሴ ማርያም',
    category: 'Daily',
    timeOfDay: 'Monday',
    geezText: 'ፈቀደ እግዚእ ያግዕዞ ለአዳም ኅዙነ ወትኩዘ ልብ፤ ወያግብኦ ውስተ ቀዲሙ ብሔር፤ ሰአሊ ለነ ቅድስት...',
    amharicTranslation: 'ያዘነና የተቀዘነ አዳምን ነጻ ያወጣው ዘንድ፥ ወደ ቀደመ ቦታውም ይመልሰው ዘንድ ጌታ ፈቀደ። ቅድስት ሆይ ለምኚልን...',
  ),
];

class PrayerLibraryScreen extends StatefulWidget {
  final bool isDark;
  const PrayerLibraryScreen({super.key, required this.isDark});
  @override
  State<PrayerLibraryScreen> createState() => _PrayerLibraryScreenState();
}

class _PrayerLibraryScreenState extends State<PrayerLibraryScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  bool _bookmarksOnly = false;
  Set<String> _bookmarks = {};
  bool _loaded = false;

  static const _categories = ['All', 'Daily', 'Praise', 'Repentance', 'Liturgy'];

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('prayer_bookmarks');
    setState(() {
      _bookmarks = saved != null ? saved.toSet() : {'pr-1', 'pr-3'};
      _loaded = true;
    });
  }

  Future<void> _toggleBookmark(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_bookmarks.contains(id)) {
        _bookmarks.remove(id);
      } else {
        _bookmarks.add(id);
      }
    });
    await prefs.setStringList('prayer_bookmarks', _bookmarks.toList());
  }

  List<PrayerItem> get _filtered => orthodoxPrayerSource.where((p) {
    final q = _searchQuery.trim();
    final matchesSearch = q.isEmpty ||
        p.titleGeez.contains(q) || p.titleAmharic.contains(q) || p.amharicTranslation.contains(q);
    final matchesCategory = _selectedCategory == 'All' || p.category == _selectedCategory;
    final matchesTab = !_bookmarksOnly || _bookmarks.contains(p.id);
    return matchesSearch && matchesCategory && matchesTab;
  }).toList();

  void _resetFilters() => setState(() {
    _searchCtrl.clear();
    _searchQuery = '';
    _selectedCategory = 'All';
    _bookmarksOnly = false;
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    final results = _filtered;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        Container(
          color: c.hero, padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.arrow_back_ios, color: c.gold, size: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('የጸሎት መጽሐፍ', style: TextStyle(fontSize: 18, color: c.text, fontWeight: FontWeight.w800)),
                Text('Orthodox Tewahedo Prayer Library', style: TextStyle(fontSize: 11, color: c.muted, fontStyle: FontStyle.italic)),
              ])),
              Icon(Icons.auto_awesome, color: c.gold, size: 20),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(color: c.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'ጸሎት ይፈልጉ... (Search prayers)',
                hintStyle: TextStyle(color: c.muted, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: c.muted, size: 20),
                filled: true, fillColor: c.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border, width: 0.5)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border, width: 0.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.gold, width: 1.5)),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _tabBtn('ሁሉንም (All)', !_bookmarksOnly, c, () => setState(() => _bookmarksOnly = false))),
              const SizedBox(width: 8),
              Expanded(child: _tabBtn('የተመረጡ (Saved)', _bookmarksOnly, c, () => setState(() => _bookmarksOnly = true), icon: Icons.bookmark)),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final cat = _categories[i];
                  final active = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? c.gold : c.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: active ? c.gold : c.border, width: 0.5),
                      ),
                      child: Text(cat, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: active ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.muted)),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
        Divider(color: c.border, height: 0.5),
        Expanded(
          child: !_loaded ? Center(child: CircularProgressIndicator(color: c.gold))
            : results.isEmpty ? _emptyState(c) : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: results.length,
              itemBuilder: (_, i) => _prayerCard(results[i], c),
            ),
        ),
      ])),
    );
  }

  Widget _tabBtn(String label, bool active, AppColors c, VoidCallback onTap, {IconData? icon}) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: active ? c.gold : c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? c.gold : c.border, width: 0.5),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: active ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.muted), const SizedBox(width: 5)],
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: active ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.muted)),
      ]),
    ),
  );

  Widget _prayerCard(PrayerItem p, AppColors c) {
    final bookmarked = _bookmarks.contains(p.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => PrayerDetailScreen(isDark: widget.isDark, initialId: p.id),
            ));
            _loadBookmarks(); // pick up any bookmark change made from the reader
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border, width: 0.5),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(6)),
                    child: Text(p.category, style: TextStyle(fontSize: 10, color: c.gold, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 6),
                  Text(p.titleAmharic, style: TextStyle(fontSize: 15, color: c.text, fontWeight: FontWeight.w800)),
                  Text(p.titleGeez, style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic)),
                ])),
                GestureDetector(
                  onTap: () => _toggleBookmark(p.id),
                  child: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border, color: bookmarked ? c.gold : c.muted, size: 20),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.goldBg.withAlpha(120), borderRadius: BorderRadius.circular(10)),
                child: Text(p.amharicTranslation, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.text, height: 1.6)),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  Icon(Icons.access_time, size: 13, color: c.gold.withAlpha(160)),
                  const SizedBox(width: 4),
                  Text(p.timeOfDay, style: TextStyle(fontSize: 11, color: c.muted)),
                ]),
                Row(children: [
                  Text('ንበብ (Read)', style: TextStyle(fontSize: 11, color: c.gold, fontWeight: FontWeight.w700)),
                  Icon(Icons.chevron_right, size: 16, color: c.gold),
                ]),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(AppColors c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: c.goldBg, shape: BoxShape.circle, border: Border.all(color: c.gold, width: 0.5)),
          child: Center(child: Icon(Icons.menu_book_outlined, color: c.gold, size: 32)),
        ),
        const SizedBox(height: 16),
        Text('ምንም ጸሎት አልተገኘም', style: TextStyle(fontSize: 16, color: c.text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('No prayers match your selected filters or search terms at this time.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.muted, height: 1.5)),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _resetFilters,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.refresh, size: 15, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white),
              const SizedBox(width: 6),
              Text('ሁሉንም አሳይ (Reset View)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white)),
            ]),
          ),
        ),
      ]),
    ),
  );
}

class PrayerDetailScreen extends StatefulWidget {
  final bool isDark;
  final String initialId;
  const PrayerDetailScreen({super.key, required this.isDark, required this.initialId});
  @override
  State<PrayerDetailScreen> createState() => _PrayerDetailScreenState();
}

class _PrayerDetailScreenState extends State<PrayerDetailScreen> {
  late PrayerItem _current = orthodoxPrayerSource.firstWhere(
    (p) => p.id == widget.initialId,
    orElse: () => orthodoxPrayerSource.first,
  );
  Set<String> _bookmarks = {};

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('prayer_bookmarks');
    setState(() => _bookmarks = saved != null ? saved.toSet() : {'pr-1', 'pr-3'});
  }

  Future<void> _toggleBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_bookmarks.contains(_current.id)) {
        _bookmarks.remove(_current.id);
      } else {
        _bookmarks.add(_current.id);
      }
    });
    await prefs.setStringList('prayer_bookmarks', _bookmarks.toList());
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    final p = _current;
    final bookmarked = _bookmarks.contains(p.id);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        Container(
          color: c.hero, padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.arrow_back_ios, color: c.gold, size: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.titleAmharic, style: TextStyle(fontSize: 15, color: c.text, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(p.category, style: TextStyle(fontSize: 11, color: c.muted)),
              ])),
              GestureDetector(
                onTap: _toggleBookmark,
                child: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border, color: c.gold, size: 22),
              ),
            ]),
            const SizedBox(height: 12),
            // Quick-switch to another prayer without leaving the reader
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: orthodoxPrayerSource.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final other = orthodoxPrayerSource[i];
                  final active = other.id == p.id;
                  return GestureDetector(
                    onTap: () => setState(() => _current = other),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? c.gold : c.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: active ? c.gold : c.border, width: 0.5),
                      ),
                      child: Text(other.titleAmharic, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: active ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.muted)),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
        Divider(color: c.border, height: 0.5),
        Expanded(child: SingleChildScrollView(
          key: ValueKey(p.id),
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.titleGeez, style: TextStyle(fontSize: 18, color: c.gold, fontWeight: FontWeight.w800, height: 1.5)),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.access_time, size: 13, color: c.muted),
              const SizedBox(width: 4),
              Text(p.timeOfDay, style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
            const SizedBox(height: 20),
            if (p.sections.isNotEmpty)
              ...p.sections.map((s) => _sectionBlock(s, c))
            else ...[
              Text('ግዕዝ (Ge\'ez)', style: TextStyle(fontSize: 11, color: c.gold, letterSpacing: 1, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border, width: 0.5)),
                child: Text(p.geezText, style: TextStyle(fontSize: 15, color: c.text, height: 1.9)),
              ),
              const SizedBox(height: 20),
              Text('አማርኛ (Amharic)', style: TextStyle(fontSize: 11, color: c.gold, letterSpacing: 1, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.gold.withAlpha(70), width: 0.5)),
                child: Text(p.amharicTranslation, style: TextStyle(fontSize: 14, color: c.text, height: 1.9)),
              ),
            ],
            const SizedBox(height: 30),
          ]),
        )),
      ])),
    );
  }

  Widget _sectionBlock(PrayerSection s, AppColors c) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 3, height: 14, color: c.gold, margin: const EdgeInsets.only(right: 8)),
        Expanded(child: Text('${s.titleAmharic} (${s.titleGeez})',
          style: TextStyle(fontSize: 12, color: c.gold, fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 10),
      Container(
        width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.goldBg.withAlpha(120), borderRadius: BorderRadius.circular(12)),
        child: Text(s.geezText, style: TextStyle(fontSize: 14.5, color: c.text, height: 1.85)),
      ),
      const SizedBox(height: 10),
      Text(s.amharicText, style: TextStyle(fontSize: 13.5, color: c.text, height: 1.8)),
    ]),
  );
}
