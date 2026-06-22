import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

const String GOOGLE_API_KEY = 'AIzaSyA-X9y5ouviMuzRZ0xGIrKpst5m0XpF2F8';


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

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_profile');
    final loggedIn = prefs.getBool('logged_in') ?? false;
    fontSizeNotifier.value = prefs.getDouble('font_size') ?? 1.0;
    setState(() {
      _profileLoaded = true;
      if (raw != null) {
        _profile = UserProfile.fromJson(jsonDecode(raw));
        _needsLogin = !loggedIn;
      }
    });
  }

  void _onProfileSaved(UserProfile p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', jsonEncode(p.toJson()));
    await prefs.setBool('logged_in', true);
    setState(() { _profile = p; _needsLogin = false; });
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

  // Verification
  final _verifyCtrl = TextEditingController();
  String _verifyCode = '';
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

  String _generateCode() {
    final code = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
    return code.substring(0, 6);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.red.shade800,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _tryLogin() async {
    print('TRYLOGIN CALLED');
    final contact = _loginContactCtrl.text.trim();
    final pass = _loginPassCtrl.text.trim();
    print('contact=$contact pass=$pass');

    if (contact.isEmpty) { _showError('Please enter your phone number or email'); return; }
    if (pass.isEmpty) { _showError('Please enter your password'); return; }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_profile');
    if (raw == null) { _showError('No account found. Please register first.'); return; }

    final profile = UserProfile.fromJson(jsonDecode(raw));

    // Check contact match (case insensitive)
    final contactMatch = profile.contact.trim().toLowerCase() == contact.toLowerCase();

    if (!contactMatch) {
      _showError('No account found with that phone/email. You registered with: ${profile.contact}');
      return;
    }

    // If old account with no password, let them in
    if (profile.password.isEmpty) {
      await prefs.setBool('logged_in', true);
      widget.onSaved(profile);
      return;
    }

    if (profile.password != pass) {
      _showError('Incorrect password. Please try again.'); return;
    }

    await prefs.setBool('logged_in', true);
    widget.onSaved(profile);
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

  void _submitRegister() {
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

    final code = _generateCode();
    _verifyCode = code;
    _pendingProfile = UserProfile(
      name: _nameCtrl.text.trim(),
      contact: _contactCtrl.text.trim(),
      age: int.tryParse(_ageCtrl.text.trim()) ?? 0,
      gender: _gender,
      role: _role,
      password: _passCtrl.text.trim(),
      verified: false,
    );

    // Show verification code dialog (simulating SMS/email)
    final c = AppColors(widget.isDark);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Verification Code Sent', style: TextStyle(color: c.gold, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Your verification code has been sent to:', style: TextStyle(color: c.muted, fontSize: 13)),
        const SizedBox(height: 8),
        Text(_contactCtrl.text.trim(), style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold)),
          child: Column(children: [
            Text('Your code is:', style: TextStyle(color: c.muted, fontSize: 12)),
            const SizedBox(height: 6),
            Text(code, style: TextStyle(color: c.gold, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 8)),
          ]),
        ),
        const SizedBox(height: 10),
        Text('(In a real app this would be sent via SMS or Email)', style: TextStyle(color: c.muted, fontSize: 11, fontStyle: FontStyle.italic)),
      ]),
      actions: [
        GestureDetector(
          onTap: () { Navigator.pop(ctx); setState(() => _step = 2); },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(8)),
            child: Text('Continue', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700))),
        ),
      ],
    ));
  }

  void _submitVerify() {
    if (_pendingProfile == null) {
      _showError('Something went wrong. Please go back and register again.');
      return;
    }
    final entered = _verifyCtrl.text.trim();
    if (entered.isEmpty) { _showError('Please enter the verification code'); return; }
    if (entered.length != 6) { _showError('Verification code must be 6 digits'); return; }
    if (!RegExp(r'^[0-9]{6}$').hasMatch(entered)) { _showError('Verification code must contain numbers only'); return; }
    if (entered != _verifyCode) {
      _showError('Incorrect verification code. Please try again.'); return;
    }
    final verified = UserProfile(
      name: _pendingProfile!.name, contact: _pendingProfile!.contact,
      age: _pendingProfile!.age, gender: _pendingProfile!.gender,
      role: _pendingProfile!.role, password: _pendingProfile!.password,
      verified: true,
    );
    widget.onSaved(verified);
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
          ]),
        ),
      ),
    );
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
    _goldBtn('SIGN IN', () => _tryLogin(), c),
    const SizedBox(height: 16),
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
    _goldBtn('REGISTER & VERIFY', _submitRegister, c),
    const SizedBox(height: 16),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('Already have an account? ', style: TextStyle(color: c.muted, fontSize: 13)),
      GestureDetector(onTap: () => setState(() => _step = 0), child: Text('Sign In', style: TextStyle(color: c.gold, fontSize: 13, fontWeight: FontWeight.w700))),
    ]),
    const SizedBox(height: 24),
  ]);

  Widget _buildVerify(AppColors c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Center(child: Column(children: [
      Container(width: 70, height: 70, decoration: BoxDecoration(color: c.goldBg, shape: BoxShape.circle, border: Border.all(color: c.gold, width: 2)),
        child: Center(child: Icon(Icons.verified_user_outlined, color: c.gold, size: 36))),
      const SizedBox(height: 16),
      Text('Verify Your Account', style: TextStyle(fontSize: 20, color: c.text, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text('Enter the 6-digit code sent to', style: TextStyle(fontSize: 13, color: c.muted)),
      const SizedBox(height: 4),
      Text(_contactCtrl.text.trim(), style: TextStyle(fontSize: 13, color: c.gold, fontWeight: FontWeight.w700)),
    ])),
    const SizedBox(height: 28),
    Center(child: Text('VERIFICATION CODE', style: TextStyle(fontSize: 10, color: c.label, letterSpacing: 3, fontWeight: FontWeight.w700))),
    const SizedBox(height: 12),
    TextField(
      controller: _verifyCtrl,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      style: TextStyle(fontSize: 32, color: c.gold, fontWeight: FontWeight.w900, letterSpacing: 12),
      decoration: InputDecoration(
        counterText: '',
        hintText: '000000', hintStyle: TextStyle(color: c.muted, fontSize: 28, letterSpacing: 8),
        filled: true, fillColor: c.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.gold, width: 2)),
      ),
    ),
    const SizedBox(height: 28),
    _goldBtn('VERIFY & CONTINUE', _submitVerify, c),
    const SizedBox(height: 16),
    Center(child: GestureDetector(
      onTap: () => setState(() => _step = 1),
      child: Text('Go back and edit', style: TextStyle(color: c.muted, fontSize: 13)),
    )),
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

  Widget _goldBtn(String label, VoidCallback onTap, AppColors c) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: c.gold.withAlpha(80), blurRadius: 16, offset: const Offset(0, 4))]),
      child: Center(child: Text(label, style: TextStyle(fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w800, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white))),
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
                    } else if (key == 'prayer_noon') _noonTime = newTime;
                    else if (key == 'prayer_evening') _eveningTime = newTime;
                    else _nightTime = newTime;
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

  Widget _grid(AppColors c) {
    final items = [
      {'icon': '📅', 'title': 'FASTING', 'sub': 'Calendar'},
      {'icon': '⛪', 'title': 'FIND PRIEST', 'sub': 'Near you'},
      {'icon': '📜', 'title': 'PENANCE', 'sub': 'Your log'},
      {'icon': '🙏', 'title': 'SAINTS', 'sub': 'All feasts'},
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.5,
        children: items.map((item) => Container(
          decoration: BoxDecoration(
            color: c.card, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border, width: 0.5),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(item['icon']!, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 6),
            Text(item['title']!, style: TextStyle(fontSize: 10, color: c.text, letterSpacing: 1, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(item['sub']!, style: TextStyle(fontSize: 11, color: c.muted, fontStyle: FontStyle.italic)),
          ]),
        )).toList(),
      ),
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
                Text('CONFESSION GUIDE', style: TextStyle(fontSize: 16, color: c.text, letterSpacing: 2, fontWeight: FontWeight.w800)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ConfessionHistoryScreen(isDark: widget.isDark))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.gold, width: 0.5)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.history, color: c.gold, size: 14),
                      const SizedBox(width: 4),
                      Text('History', style: TextStyle(fontSize: 11, color: c.gold, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: c.strip, borderRadius: BorderRadius.circular(20)),
                    child: Text('Clear All', style: TextStyle(fontSize: 11, color: c.muted)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
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
    snippet: 'እንቁጣጣሽ የኢትዮጵያ አዲስ ዓመት መታሰቢያ ነው፣ እንዲሁም የቅዱስ ዮሐንስ መጥምቅ ልደት ይከበራል።',
    fullStory: 'መስከረም 1 የኢትዮጵያ ዘመን አቆጣጠር አዲስ ዓመት መጀመሪያ ነው። በዚህ ቀን ቅዱስ ዮሐንስ መጥምቅ የተወለደበት ቀንም ይታሰባል። ቅዱስ ዮሐንስ የጌታችን ኢየሱስ ክርስቶስ መንገድ ጠራጊ ሆኖ፣ ንስሐን እና የልብ ለውጥን ሲሰብክ ኖረ። እንቁጣጣሽ የምትለው ቃል ራሷ ንግሥት ሳባ ከጉብኝቷ ስትመለስ የተሰጣት ስጦታ ታሪክ ጋር ይያያዛል ይባላል። ይህ ቀን አበቦች የሚታደሱበት፣ ቤተሰብ የሚሰበሰብበት እና አዲስ ተስፋ የሚታቀድበት ነው።',
  ),
  '1-17': SynaxariumEntry(
    snippet: 'መስቀል የጌታችን መስቀል በቅድስት ዕሌኒ ንግሥት የተገኘበት ቀን ሆኖ በደመራ በዓል ይከበራል።',
    fullStory: 'ይህ በዓል የጌታችን የኢየሱስ ክርስቶስ መስቀል በ4ኛው መቶ ክፍለ ዘመን በቅድስት ዕሌኒ ንግሥት እንደ ተገኘ የሚያስታውስ ነው። ንግሥት ዕሌኒ ቅዱሱን መስቀል ለማግኘት ብዙ ጥረት ካደረገች በኋላ፣ የተቃጠለ ዕጣን ጢስ ወደ ላይ ወጥቶ የመስቀሉን ቦታ አሳያት። ይህንን መታሰቢያ በማድረግ ኢትዮጵያውያን ምዕመናን ደመራ በማቃጠል፣ እሳቱ ወደ ምን አቅጣጫ እንደሚዘንብል በመመልክት የመጭውን ዓመት ምልክት እንደ ያደርጉታል። ይህ ከእምነት ጋር የተያያዘ ጥንታዊ ትውፊት ነው።',
  ),
  '1-23': SynaxariumEntry(
    snippet: 'ቅዱስ ጊዮርጊስ ለክርስቶስ እምነት ብዙ መከራ ቢደርስበትም ጸንቶ የቆመ ታላቅ ሰማዕት ነው።',
    fullStory: 'ቅዱስ ጊዮርጊስ በሮም ግዛት ዘመነ ድዮቅልጥያኖስ ንግሥት የነበረ ወታደር ነበር። ክርስቲያን በመሆኑ ምክንያት እምነቱን ለመካድ ብዙ ግፍና መከራ ቢደርስበትም፣ በጽናት ጸንቶ ቆመ። ለክርስቶስ ያለውን ፍቅር ላለመተው ብዙ ስቃይን ታገሰ፣ በመጨረሻም በሰማዕትነት አለፈ። ቅዱስ ጊዮርጊስ የጽናት፣ የእምነት እና የጀግንነት ምሳሌ ተደርጎ ይታያል፤ ስለዚህም በኢትዮጵያ ኦርቶዶክስ ተዋሕዶ ቤተ ክርስቲያን እጅግ የተወደደ ቅዱስ ነው።',
  ),
  '1-24': SynaxariumEntry(
    snippet: 'አቡነ ተክለ ሃይማኖት የኢትዮጵያ ታላቅ መነኩሴና የደብረ ሊባኖስ ገዳም መሥራች ናቸው።',
    fullStory: 'አቡነ ተክለ ሃይማኖት በ13ኛው መቶ ክፍለ ዘመን ተወልደው፣ ሕይወታቸውን ሙሉ ለጸሎት እና ለትምህርት ሰጥተዋል። ስድስት ክንፍ እንደ መልአክ እንዲኖራቸው እስኪደረግ ድረስ በብዙ ጾምና ጸሎት እግዚአብሔርን አገለገሉ። ደብረ ሊባኖስን መሥርተው ብዙ ደቀ መዛሙርትን አስተምረዋል። ህይወታቸው የጽናት፣ የትህትና እና ላልተወሰነ ፍቅር ለእግዚአብሔር ምሳሌ ነው።',
  ),
  '2-22': SynaxariumEntry(
    snippet: 'ቅዱስ ሉቃስ ወንጌላዊ ከአራቱ ወንጌላውያን አንዱ ሲሆን፣ ሐኪምና ሰዓሊ ጭምር ነበር።',
    fullStory: 'ቅዱስ ሉቃስ ከጥንት ግሪክ ምሁራን አንዱ ሆኖ፣ ቅዱስ ወንጌልን እና የሐዋርያት ሥራን የጻፈ ነው። እርሱ ራሱ ከአህዛብ የተወለደ ሲሆን፣ በሙያው ሐኪም ነበር። ከቅዱስ ጳውሎስ ሐዋርያ ጋር ብዙ ቦታዎችን ተጓዘ፣ የጌታችንን ወንጌል ለማስፋት ትልቅ አስተዋጽኦ አበረከተ። እንደ ትውፊት የእመቤታችን ቅድስት ድንግል ማርያምን ምስል ለመጀመሪያ ጊዜ የሳለ ሰዓሊ ተብሎ ይታመናል።',
  ),
  '4-29': SynaxariumEntry(
    snippet: 'ገና የጌታችን ኢየሱስ ክርስቶስ የልደት በዓል ሲሆን፣ ለሰው ልጅ ድነት የመጣው ቀን ነው።',
    fullStory: 'ይህ ታላቅ በዓል የአምላካችን ኢየሱስ ክርስቶስ በቤተልሔም ከቅድስት ድንግል ማርያም እንደተወለደ የሚያስታውስ ነው። መላእክት ለእረኞች የምስራች ብስራት አወጁ፣ ሰብአ ሰገልም ከምስራቅ መጥተው ሰገዱለት። ይህ የእግዚአብሔር ሰው የመሆን ምስጢር በዓል ለክርስቲያኖች ሁሉ የተስፋና የደስታ ምልክት ነው። በኢትዮጵያ ኦርቶዶክስ ቤተ ክርስቲያን ይህ በዓል በታላቅ ድምቀት ይከበራል።',
  ),
  '5-11': SynaxariumEntry(
    snippet: 'ጥምቀተ ባሕር የጌታችን ኢየሱስ ክርስቶስ በዮርዳኖስ ወንዝ የተጠመቀበት ታላቅ በዓል ነው።',
    fullStory: 'በዚህ ቀን ጌታችን ኢየሱስ ክርስቶስ በቅዱስ ዮሐንስ መጥምቅ እጅ በዮርዳኖስ ወንዝ ተጠመቀ። በዚያ ቅጽበት መንፈስ ቅዱስ በርግብ አምሳል ወረደ፣ የአባት ድምጽም ከሰማይ ተሰማ፣ "የምወድደው ልጄ ይህ ነው" ሲል። ይህ የስላሴ መገለጥ (ኤፒፋንያ) በዓል ተብሎ ይታወቅ ሲሆን፣ በኢትዮጵያ በታላቅ ድምቀት፣ በውሃ መርጨትና በዝማሬ ይከበራል። የጥምቀት ምስጢር ለሰው ልጅ የነጻነትና የአዲስ ሕይወት ምልክት ነው።',
  ),
  '9-1': SynaxariumEntry(
    snippet: 'ልደታ ማርያም የእመቤታችን ቅድስት ድንግል ማርያም ልደት መታሰቢያ ነው።',
    fullStory: 'ይህ ቀን ቅድስት ድንግል ማርያም ከእናቷ ቅድስት ሐና እና ከአባቷ ኢያቄም እንደተወለደች የሚያስታውስ ነው። ቅድስት ሐናና ኢያቄም ለዓመታት ልጅ ስላልነበራቸው፣ ለእግዚአብሔር ጸልየው ቅድስት ድንግል ማርያምን ተሰጣቸው። ይህ ልደት ለሰው ልጅ ድነት መንገድ የከፈተ ታላቅ ምስጢር ነው፤ ቅድስት ድንግል ማርያም የጌታችን እናት ሆና ስለተመረጠች ይህ ቀን በታላቅ ክብር ይታሰባል።',
  ),
  '12-13': SynaxariumEntry(
    snippet: 'ቡሄ ጌታችን ኢየሱስ ክርስቶስ በደብረ ታቦር ብርሃኑን ለሐዋርያት ያሳየበት ቀን ነው።',
    fullStory: 'ይህ በዓል ጌታችን ኢየሱስ ክርስቶስ ከጴጥሮስ፣ ከያዕቆብና ከዮሐንስ ጋር ወደ ደብረ ታቦር ተራራ ወጥቶ፣ ክብሩን ያሳያቸው ቀን ነው። ፊቱ እንደ ፀሐይ በራ፣ ልብሱም እንደ በረዶ ነጭ ሆነ። ሙሴና ኤልያስም ከእርሱ ጋር ተገለጡ። ይህ የጌታችን አምላክነት መገለጥ ለሐዋርያት ትልቅ እምነት ሰጣቸው። በኢትዮጵያ ይህ በዓል ቡሄ ተብሎ ይከበራል፤ ልጆችም ችቦ በማብራት ይዘፍናሉ።',
  ),
  '12-16': SynaxariumEntry(
    snippet: 'ፍልሰታ ማርያም የእመቤታችን ቅድስት ድንግል ማርያም ዕርገት ወደ ሰማይ መታሰቢያ ነው።',
    fullStory: 'ከ16 ቀን ጾም በኋላ የሚከበረው ይህ በዓል፣ የቅድስት ድንግል ማርያም ሥጋ ከሞት በኋላ ወደ ሰማይ ማረጉን ያስታውሳል። ሐዋርያት ለቅድስት ድንግል ማርያም የቀብር ሥርዓት ሲፈጽሙ፣ ከ3 ቀን በኋላ መቃብሯ ባዶ ሆኖ ተገኘ፤ ይህም እመቤታችን በሥጋዋ ወደ ሰማይ ማረገች ብለው አምነዋል። ይህ በዓል ለቅድስት ድንግል ማርያም ካላት ልዩ ክብር የተነሳ በታላቅ ጾምና ጸሎት ይከበራል።',
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

class _CalEvent {
  final int ethDay;
  final String title;
  const _CalEvent({required this.ethDay, required this.title});
}

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

  final List<_CalEvent> _events = const [
    _CalEvent(ethDay: 9, title: 'የእስላም አዲስ ዓመት'),
    _CalEvent(ethDay: 18, title: 'አሹራ'),
  ];

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
  bool _hasEvent(int day) => _events.any((e) => e.ethDay == day);

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
            return Container(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isAnnual ? c.goldBg : c.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isAnnual ? c.gold : c.border, width: isAnnual ? 1.5 : 0.5),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              ]),
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

class PriestScreen extends StatefulWidget {
  final bool isDark;
  const PriestScreen({super.key, required this.isDark});
  @override
  State<PriestScreen> createState() => _PriestScreenState();
}

class _PriestScreenState extends State<PriestScreen> {
  double? _userLat, _userLng;
  bool _loading = true;
  String _error = '';
  Map<String, dynamic>? _selected;
  bool _satellite = false;
  final MapController _mapController = MapController();

  // Verified EOTC churches in Addis Ababa
  List<Map<String, dynamic>> _churches = [];
  bool _loadingChurches = false;

  @override
  void initState() { super.initState(); _getLocation(); }

  Future<void> _getLocation() async {
    setState(() { _loading = true; _error = ''; });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) { setState(() { _loading = false; _error = 'Please enable location services'; }); return; }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() { _loading = false; _error = 'Location permission denied'; }); return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() { _userLat = pos.latitude; _userLng = pos.longitude; _loading = false; });
      await Future.delayed(const Duration(milliseconds: 500));
      _mapController.move(LatLng(pos.latitude, pos.longitude), 14.0);
      _fetchNearbyChurches(pos.latitude, pos.longitude);
    } catch (e) {
      setState(() { _loading = false; _error = 'Could not get location'; });
    }
  }

  Future<void> _fetchNearbyChurches(double lat, double lng) async {
    setState(() { _loadingChurches = true; });
    try {
      final allChurches = <Map<String, dynamic>>{};
      // Search 1: EOTC specific
      for (final keyword in ['Ethiopian Orthodox', 'Ethiopian Orthodox Tewahedo', 'EOTC']) {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=$lat,$lng&radius=10000&type=church'
          '&keyword=${Uri.encodeComponent(keyword)}&key=$GOOGLE_API_KEY'
        );
        final client = HttpClient();
        final req = await client.getUrl(url);
        final resp = await req.close();
        final body = await resp.transform(const Utf8Decoder()).join();
        client.close();
        final data = jsonDecode(body);
        final results = data['results'] as List? ?? [];
        for (final r in results) {
          final loc = r['geometry']['location'];
          final elat = (loc['lat'] as num).toDouble();
          final elng = (loc['lng'] as num).toDouble();
          final name = r['name'] as String? ?? 'Church';
          final vicinity = r['vicinity'] as String? ?? '';
          final dist = Geolocator.distanceBetween(lat, lng, elat, elng) / 1000;
          allChurches.add({'name': name, 'sub': vicinity, 'lat': elat, 'lng': elng, 'dist': dist});
        }
      }
      // Search 2: All nearby churches
      final url2 = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=$lat,$lng&radius=5000&type=church&key=$GOOGLE_API_KEY'
      );
      final client2 = HttpClient();
      final req2 = await client2.getUrl(url2);
      final resp2 = await req2.close();
      final body2 = await resp2.transform(const Utf8Decoder()).join();
      client2.close();
      final data2 = jsonDecode(body2);
      final results2 = data2['results'] as List? ?? [];
      for (final r in results2) {
        final loc = r['geometry']['location'];
        final elat = (loc['lat'] as num).toDouble();
        final elng = (loc['lng'] as num).toDouble();
        final name = r['name'] as String? ?? 'Church';
        final vicinity = r['vicinity'] as String? ?? '';
        final dist = Geolocator.distanceBetween(lat, lng, elat, elng) / 1000;
        allChurches.add({'name': name, 'sub': vicinity, 'lat': elat, 'lng': elng, 'dist': dist});
      }
      final list = allChurches.toList();
      list.sort((a, b) => (a['dist'] as double).compareTo(b['dist'] as double));
      if (list.isNotEmpty) {
        setState(() { _churches = list; _loadingChurches = false; });
      } else {
        setState(() { _loadingChurches = false; });
      }
    } catch (e) {
      // Keep existing churches if API fails
    }
  }

  List<Map<String, dynamic>> get _sortedChurches {
    if (_userLat == null) return _churches;
    final list = List<Map<String, dynamic>>.from(_churches);
    list.sort((a, b) {
      final da = Geolocator.distanceBetween(_userLat!, _userLng!, a['lat'] as double, a['lng'] as double);
      final db = Geolocator.distanceBetween(_userLat!, _userLng!, b['lat'] as double, b['lng'] as double);
      return da.compareTo(db);
    });
    return list;
  }

  double _dist(Map<String, dynamic> ch) {
    if (_userLat == null) return 0;
    return Geolocator.distanceBetween(_userLat!, _userLng!, ch['lat'] as double, ch['lng'] as double) / 1000;
  }

  void _openDirections(Map<String, dynamic> ch) async {
    final lat = ch['lat'] as double;
    final lng = ch['lng'] as double;
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _openGoogleMapsSearch() async {
    if (_userLat == null) return;
    final url = Uri.parse('https://www.google.com/maps/search/Ethiopian+Orthodox+Church/@$_userLat,$_userLng,14z');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    final sorted = _sortedChurches;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        // Header
        Container(
          color: c.hero, padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            Container(width: 4, height: 20, color: c.gold, margin: const EdgeInsets.only(right: 10)),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('FIND A CHURCH', style: TextStyle(fontSize: 15, color: c.text, letterSpacing: 2, fontWeight: FontWeight.w800)),
              Text('ቅርብ ቤተ ክርስቲያን ፈልግ', style: TextStyle(fontSize: 11, color: c.muted, fontStyle: FontStyle.italic)),
            ]),
            const Spacer(),
            GestureDetector(
              onTap: _openGoogleMapsSearch,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.gold, width: 0.5)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.search, color: c.gold, size: 14),
                  const SizedBox(width: 4),
                  Text('Search All', style: TextStyle(fontSize: 10, color: c.gold, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _satellite = !_satellite),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: _satellite ? c.gold : c.goldBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.gold, width: 0.5)),
                child: Text('Satellite', style: TextStyle(fontSize: 10, color: _satellite ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.gold, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _getLocation,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.gold, width: 0.5)),
                child: Icon(Icons.my_location, color: c.gold, size: 16),
              ),
            ),
          ]),
        ),
        Divider(color: c.border, height: 0.5),

        // Map
        SizedBox(
          height: 280,
          child: _loading
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CircularProgressIndicator(color: c.gold),
                  const SizedBox(height: 12),
                  Text('Getting your location...', style: TextStyle(color: c.muted, fontSize: 12)),
                ]))
              : _error.isNotEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.location_off, color: c.muted, size: 36),
                      const SizedBox(height: 8),
                      Text(_error, style: TextStyle(color: c.muted, fontSize: 12), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      GestureDetector(onTap: _getLocation, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(10)), child: Text('Try Again', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700)))),
                    ]))
                  : Stack(children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: LatLng(_userLat ?? 9.0227, _userLng ?? 38.7468),
                          initialZoom: 13.5,
                          minZoom: 3, maxZoom: 19,
                          onTap: (_, _) => setState(() => _selected = null),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: _satellite
                                ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.yenefsabat.yenefs_abat',
                          ),
                          MarkerLayer(markers: [
                            if (_userLat != null)
                              Marker(
                                point: LatLng(_userLat!, _userLng!),
                                width: 44, height: 44,
                                child: Container(
                                  decoration: BoxDecoration(color: const Color(0xFF2196F3), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: Colors.blue.withAlpha(100), blurRadius: 10)]),
                                  child: const Icon(Icons.person_pin, color: Colors.white, size: 22),
                                ),
                              ),
                            ...sorted.map((ch) {
                              final isSel = _selected == ch;
                              return Marker(
                                point: LatLng(ch['lat'] as double, ch['lng'] as double),
                                width: isSel ? 64 : 50,
                                height: isSel ? 78 : 62,
                                alignment: Alignment.bottomCenter,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    setState(() => _selected = ch);
                                    _mapController.move(LatLng(ch['lat'] as double, ch['lng'] as double), 15.0);
                                  },
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    Container(
                                      width: isSel ? 54 : 42,
                                      height: isSel ? 54 : 42,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFC9A84C),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: isSel ? 3 : 2.5),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withAlpha(180), blurRadius: 6, offset: const Offset(0, 3)),
                                          BoxShadow(color: const Color(0xFFC9A84C).withAlpha(80), blurRadius: 10, spreadRadius: 1),
                                        ],
                                      ),
                                      child: Center(child: Text('⛪', style: TextStyle(fontSize: isSel ? 26 : 20))),
                                    ),
                                    Container(
                                      width: isSel ? 6 : 5,
                                      height: isSel ? 16 : 12,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFC9A84C),
                                        borderRadius: BorderRadius.circular(3),
                                        boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 3)],
                                      ),
                                    ),
                                  ]),
                                ),
                              );
                            }),
                          ]),
                        ],
                      ),
                      // Zoom controls
                      Positioned(right: 10, top: 10, child: Column(children: [
                        Container(width: 36, height: 36, margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(color: c.card, shape: BoxShape.circle, border: Border.all(color: c.border), boxShadow: [BoxShadow(color: Colors.black.withAlpha(40), blurRadius: 4)]),
                          child: Center(child: Text('N', style: TextStyle(fontSize: 12, color: c.gold, fontWeight: FontWeight.w900)))),
                        GestureDetector(onTap: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
                          child: Container(width: 36, height: 36, decoration: BoxDecoration(color: c.card, borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), border: Border.all(color: c.border)), child: Center(child: Icon(Icons.add, color: c.text, size: 20)))),
                        Container(height: 0.5, width: 36, color: c.border),
                        GestureDetector(onTap: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
                          child: Container(width: 36, height: 36, decoration: BoxDecoration(color: c.card, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)), border: Border.all(color: c.border)), child: Center(child: Icon(Icons.remove, color: c.text, size: 20)))),
                      ])),
                      // Selected popup
                      if (_selected != null)
                        Positioned(bottom: 10, left: 10, right: 10, child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.gold, width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 12)]),
                          child: Row(children: [
                            Container(width: 44, height: 44, decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold)), child: const Center(child: Text('⛪', style: TextStyle(fontSize: 24)))),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_selected!['name'] as String, style: TextStyle(fontSize: 13, color: c.text, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text('${_dist(_selected!).toStringAsFixed(1)} km away', style: TextStyle(fontSize: 11, color: c.gold, fontWeight: FontWeight.w600)),
                            ])),
                            GestureDetector(onTap: () => _openDirections(_selected!), child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(10)),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.directions, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, size: 18),
                                Text('Go', style: TextStyle(fontSize: 10, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w800)),
                              ]),
                            )),
                          ]),
                        )),
                    ]),
        ),
        Divider(color: c.border, height: 0.5),

        // Church list below map
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final ch = sorted[i];
              final dist = _dist(ch);
              final isSel = _selected == ch;
              return GestureDetector(
                onTap: () {
                  setState(() => _selected = ch);
                  _mapController.move(LatLng(ch['lat'] as double, ch['lng'] as double), 15.0);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSel ? c.goldBg : c.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isSel ? c.gold : c.border, width: isSel ? 1.5 : 0.5),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold, width: 0.5)), child: const Center(child: Text('⛪', style: TextStyle(fontSize: 22)))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ch['name'] as String, style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w700)),
                      Text(ch['sub'] as String, style: TextStyle(fontSize: 11, color: c.muted)),
                      if (_userLat != null) Row(children: [
                        Icon(Icons.location_on, color: c.gold, size: 11),
                        const SizedBox(width: 2),
                        Text('${dist.toStringAsFixed(1)} km away', style: TextStyle(fontSize: 11, color: c.gold, fontWeight: FontWeight.w600)),
                      ]),
                    ])),
                    GestureDetector(
                      onTap: () => _openDirections(ch),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(10)),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.directions, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, size: 18),
                          Text('Go', style: TextStyle(fontSize: 10, color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ])),
    );
  }
}


class _ChurchPinPainter extends CustomPainter {
  final bool selected;
  final Color gold;
  const _ChurchPinPainter({required this.selected, required this.gold});

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final double cy = r; // circle center y
    final Paint fillPaint = Paint()..color = gold..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3;
    final Paint shadowPaint = Paint()..color = Colors.black.withAlpha(80)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // Shadow
    canvas.drawCircle(Offset(r, cy + 3), r - 2, shadowPaint);
    // Gold circle
    canvas.drawCircle(Offset(r, cy), r - 2, fillPaint);
    // White border
    canvas.drawCircle(Offset(r, cy), r - 2, borderPaint);

    // Pin tail
    final tailPaint = Paint()..color = gold..style = PaintingStyle.fill;
    final tailPath = ui.Path();
    final double tailX = r;
    final double tailTop = cy + r - 4;
    final double tailBot = size.height - 2;
    tailPath.moveTo(tailX - 5, tailTop);
    tailPath.lineTo(tailX + 5, tailTop);
    tailPath.lineTo(tailX, tailBot);
    tailPath.close();
    canvas.drawPath(tailPath, tailPaint);

    // Cross icon drawn manually
    final crossPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = selected ? 4 : 3..strokeCap = StrokeCap.round;
    final double cs = r * 0.55;
    // Vertical bar
    canvas.drawLine(Offset(r, cy - cs), Offset(r, cy + cs * 0.6), crossPaint);
    // Horizontal bar (upper third)
    canvas.drawLine(Offset(r - cs * 0.7, cy - cs * 0.2), Offset(r + cs * 0.7, cy - cs * 0.2), crossPaint);
    // Church roof
    final roofPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = selected ? 3 : 2..strokeCap = StrokeCap.round;
    final roofPath = ui.Path();
    roofPath.moveTo(r - cs * 0.7, cy + cs * 0.6);
    roofPath.lineTo(r, cy - cs * 0.6);
    roofPath.lineTo(r + cs * 0.7, cy + cs * 0.6);
    canvas.drawPath(roofPath, roofPaint);
  }

  @override
  bool shouldRepaint(_ChurchPinPainter old) => old.selected != selected;
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged_in', false);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SignInScreen(
        onSaved: (p) async {
          final prefs2 = await SharedPreferences.getInstance();
          await prefs2.setString('user_profile', jsonEncode(p.toJson()));
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const YenefsAbatApp()),
            (route) => false,
          );
        },
        isDark: widget.isDark,
      )),
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
