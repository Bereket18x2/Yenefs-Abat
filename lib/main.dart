import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ═══════════════════════════════════════════════
// NOTIFICATIONS
// ═══════════════════════════════════════════════

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings settings =
      InitializationSettings(android: androidSettings);
  await notificationsPlugin.initialize(settings);
}

Future<void> schedulePrayerNotification(int id, int hour, int minute, String label) async {
  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'prayer_channel', 'Prayer Reminders',
    channelDescription: 'Daily prayer time reminders',
    importance: Importance.max, priority: Priority.high,
    sound: const RawResourceAndroidNotificationSound('church_bell'),
    playSound: true,
  );
  await notificationsPlugin.periodicallyShow(
    id, '🕯 $label', 'It is time for your prayer — ጸሎት ጊዜ ነው',
    RepeatInterval.daily, NotificationDetails(android: androidDetails),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
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
    for (int i = 1; i < m; i++) t += daysInMonth(i, y);
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
  UserProfile({
    required this.name, required this.contact,
    required this.age, required this.gender, required this.role,
  });
  Map<String, dynamic> toJson() => {
    'name': name, 'contact': contact, 'age': age, 'gender': gender, 'role': role,
  };
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    name: j['name'], contact: j['contact'],
    age: j['age'], gender: j['gender'], role: j['role'],
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

final ValueNotifier<double> fontSizeNotifier = ValueNotifier<double>(1.0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  // Load saved font size
  final prefs = await SharedPreferences.getInstance();
  fontSizeNotifier.value = prefs.getDouble('font_size') ?? 1.0;
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

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_profile');
    setState(() {
      _profileLoaded = true;
      if (raw != null) _profile = UserProfile.fromJson(jsonDecode(raw));
    });
  }

  void _onProfileSaved(UserProfile p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', jsonEncode(p.toJson()));
    setState(() => _profile = p);
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
          : _profile == null
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

class SignInScreen extends StatefulWidget {
  final Function(UserProfile) onSaved;
  final bool isDark;
  const SignInScreen({super.key, required this.onSaved, required this.isDark});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String _gender = '';
  String _role = '';
  final _formKey = GlobalKey<FormState>();

  final List<String> _genders = ['Male', 'Female'];
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
    _nameCtrl.dispose(); _contactCtrl.dispose(); _ageCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) { _showError('Please enter your name'); return; }
    if (_gender.isEmpty) { _showError('Please select your gender'); return; }
    if (_role.isEmpty) { _showError('Please select your role in church'); return; }
    final age = int.tryParse(_ageCtrl.text.trim()) ?? 0;
    widget.onSaved(UserProfile(
      name: _nameCtrl.text.trim(),
      contact: _contactCtrl.text.trim(),
      age: age, gender: _gender, role: _role,
    ));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 20),
              // Logo
              Center(child: Column(children: [
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
                const SizedBox(height: 16),
                Text('YENEFS_ABAT', style: TextStyle(fontSize: 24, color: c.text, letterSpacing: 0, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('የነፍስ አባት', style: TextStyle(fontSize: 16, color: c.muted, fontStyle: FontStyle.italic)),
                const SizedBox(height: 8),
                Container(width: 60, height: 2, color: c.gold),
                const SizedBox(height: 8),
                Text('Create your profile to get started', style: TextStyle(fontSize: 13, color: c.muted)),
              ])),
              const SizedBox(height: 32),
              // Name
              _fieldLabel('Full Name *', 'ሙሉ ስም', c),
              const SizedBox(height: 8),
              _inputField('Enter your full name', _nameCtrl, c),
              const SizedBox(height: 18),
              // Contact
              _fieldLabel('Phone or Email', 'ስልክ ወይም ኢሜል', c),
              const SizedBox(height: 8),
              _inputField('Phone number or email address', _contactCtrl, c),
              const SizedBox(height: 18),
              // Age
              _fieldLabel('Age', 'እድሜ', c),
              const SizedBox(height: 8),
              _inputField('Your age', _ageCtrl, c, isNumber: true),
              const SizedBox(height: 18),
              // Gender
              _fieldLabel('Gender *', 'ጾታ', c),
              const SizedBox(height: 8),
              Row(children: _genders.map((g) => Expanded(child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _gender = g),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _gender == g ? c.gold : c.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _gender == g ? c.gold : c.border, width: _gender == g ? 0 : 0.5),
                    ),
                    child: Center(child: Text(g, style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: _gender == g ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.text,
                    ))),
                  ),
                ),
              ))).toList()),
              const SizedBox(height: 18),
              // Role
              _fieldLabel('Your Role in Church *', 'በቤተክርስቲያን ውስጥ ያለዎት ሚና', c),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _roles.map((r) => GestureDetector(
                  onTap: () => setState(() => _role = r['en']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _role == r['en'] ? c.gold : c.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _role == r['en'] ? c.gold : c.border, width: 0.5),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(r['am']!, style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: _role == r['en'] ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white) : c.text,
                      )),
                      Text(r['en']!, style: TextStyle(
                        fontSize: 10,
                        color: _role == r['en'] ? (widget.isDark ? const Color(0xFF0F0505) : Colors.white).withAlpha(180) : c.muted,
                      )),
                    ]),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 32),
              // Submit
              GestureDetector(
                onTap: _submit,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: c.gold, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: c.gold.withAlpha(80), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  child: Center(child: Text('GET STARTED ✝', style: TextStyle(
                    fontSize: 15, letterSpacing: 2, fontWeight: FontWeight.w800,
                    color: widget.isDark ? const Color(0xFF0F0505) : Colors.white,
                  ))),
                ),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String en, String am, AppColors c) => Row(children: [
    Text(en, style: TextStyle(fontSize: 12, color: c.text, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    const SizedBox(width: 8),
    Text(am, style: TextStyle(fontSize: 12, color: c.muted, fontStyle: FontStyle.italic)),
  ]);

  Widget _inputField(String hint, TextEditingController ctrl, AppColors c, {bool isNumber = false}) =>
    TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
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
}

// ═══════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════

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
      MoreScreen(isDark: widget.isDark),
    ];
    final items = [
      {'icon': Icons.home_outlined, 'label': 'HOME'},
      {'icon': Icons.church_outlined, 'label': 'CONFESS'},
      {'icon': Icons.calendar_month_outlined, 'label': 'CALENDAR'},
      {'icon': Icons.auto_stories_outlined, 'label': 'PENANCE'},
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
    setState(() {
      _morningTime = prefs.getString('prayer_morning') ?? '';
      _noonTime = prefs.getString('prayer_noon') ?? '';
      _eveningTime = prefs.getString('prayer_evening') ?? '';
      _nightTime = prefs.getString('prayer_night') ?? '';
      if (lastConfStr != null) {
        _lastConfessionDate = DateTime.parse(lastConfStr);
        _daysSinceConfession = DateTime.now().difference(_lastConfessionDate!).inDays;
      }
    });
    if (_daysSinceConfession >= 30) await showConfessionNotification();
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
          content: Text('Current: ' + current + '. What would you like to do?', style: TextStyle(color: c.muted, fontSize: 13)),
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
              _label('TODAY\'S SAINT', c), _saintCard(c),
              _label('PRAYER REMINDERS', c), _prayerSection(c),
              _label('CONFESSION', c), _confCard(c),
              _label('SPIRITUAL TOOLS', c), _grid(c),
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

  Widget _saintCard(AppColors c) {
    final todayFeast = getEotcDay(_today.month, _today.day);
    final isAnnual = todayFeast?.isAnnual ?? false;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAnnual ? c.goldBg : c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isAnnual ? c.gold : c.border, width: isAnnual ? 1.5 : 0.5),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
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
            _today.monthNameAmharic + ' ' + _today.day.toString() + ', ' + _today.year.toString(),
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
                    if (key == 'prayer_morning') _morningTime = newTime;
                    else if (key == 'prayer_noon') _noonTime = newTime;
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
      for (int i = 0; i < sins.length; i++) _checked[i] = false;
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
      for (int i = 0; i < sins.length; i++) _checked[i] = false;
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
// EOTC CALENDAR DATA
// ═══════════════════════════════════════════════

class EotcDay {
  final int month;
  final int day;
  final String name;
  final bool isAnnual;
  const EotcDay({required this.month, required this.day, required this.name, this.isAnnual = false});
}

EotcDay? getEotcDay(int month, int day) {
  try {
    return eotcCalendar.firstWhere((e) => e.month == month && e.day == day);
  } catch (e) { return null; }
}

List<EotcDay> getAnnualFeasts(int month) {
  return eotcCalendar.where((e) => e.month == month && e.isAnnual).toList();
}

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
              final hasEvent = _hasEvent(day);
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
                      fontSize: 15,
                      color: today ? const Color(0xFF4A9EFF) : isAnnual ? c.gold : c.text,
                      fontWeight: today || isAnnual ? FontWeight.w800 : FontWeight.w400,
                    )),
                    if (eotcDay != null) Positioned(bottom: 2, child: Container(
                      width: 5, height: 5,
                      decoration: BoxDecoration(color: isAnnual ? c.gold : c.muted.withAlpha(100), shape: BoxShape.circle),
                    )),
                    if (hasEvent) Positioned(bottom: 2, child: Container(
                      width: 5, height: 5,
                      decoration: BoxDecoration(color: c.green, shape: BoxShape.circle),
                    )),
                  ]),
                ),
              );
            },
          ),
        ),
        Container(height: 0.5, color: c.border),

        // Selected day feast
        if (_selectedDay != null)
          Builder(builder: (context) {
            final selectedFeast = getEotcDay(_viewMonth, _selectedDay!);
            final isAnnual = selectedFeast?.isAnnual ?? false;
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
                  Text(EthiopianCalendar.monthsAmharic[_viewMonth-1] + ' ' + _selectedDay.toString(), style: TextStyle(fontSize: 11, color: c.muted)),
                  const SizedBox(height: 4),
                  Text(selectedFeast != null ? selectedFeast.name : 'No feast recorded', style: TextStyle(fontSize: 15, color: c.text, fontWeight: FontWeight.w700)),
                  if (isAnnual) ...[
                    const SizedBox(height: 4),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: c.gold.withAlpha(30), borderRadius: BorderRadius.circular(8)), child: Text('ዓመታዊ በዓል', style: TextStyle(fontSize: 10, color: c.gold, fontWeight: FontWeight.w700))),
                  ],
                ])),
              ]),
            );
          }),

        // Annual feasts
        Builder(builder: (context) {
          final annualFeasts = getAnnualFeasts(_viewMonth);
          final monthAmharic = EthiopianCalendar.monthsAmharic[_viewMonth-1];
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
                decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold.withAlpha(80), width: 0.5)),
                child: Row(children: [
                  Container(width: 36, height: 36, decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.gold, width: 0.5)), child: Center(child: Text(feast.day.toString(), style: TextStyle(fontSize: 14, color: c.gold, fontWeight: FontWeight.w800)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(feast.name, style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w600)),
                    Text(monthAmharic + ' ' + feast.day.toString(), style: TextStyle(fontSize: 11, color: c.muted)),
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
// MORE SCREEN
// ═══════════════════════════════════════════════

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
    await prefs.remove('user_profile');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SignInScreen(onSaved: (p) async {
        final prefs2 = await SharedPreferences.getInstance();
        await prefs2.setString('user_profile', jsonEncode(p.toJson()));
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => YenefsAbatApp()),
          (route) => false,
        );
      }, isDark: widget.isDark)),
      (route) => false,
    );
  }

  void _shareApp() {
    showDialog(
      context: context,
      builder: (ctx) {
        final c = AppColors(widget.isDark);
        return AlertDialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Share Yenefs_Abat', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Share this app with your friends and family:', style: TextStyle(color: c.muted, fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
              child: SelectableText(
                'https://play.google.com/store/apps/details?id=com.yenefsabat.yenefs_abat',
                style: TextStyle(fontSize: 12, color: c.gold),
              ),
            ),
            const SizedBox(height: 12),
            Text('You can also share via Xender, Bluetooth, WhatsApp, Telegram and other apps installed on your phone.', style: TextStyle(color: c.muted, fontSize: 12)),
          ]),
          actions: [
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(8)),
                child: Text('OK', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAbout() {
    final c = AppColors(widget.isDark);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('About Yenefs_Abat', style: TextStyle(color: c.gold, fontWeight: FontWeight.w800, fontSize: 18)),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 80, height: 80,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(shape: BoxShape.circle),
            child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.cover)),
          ),
          Text('English', style: TextStyle(color: c.gold, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            'This app was created by students of Finote Yared Abenet School of Jemo Medhanialem, dedicated to Yeneta Yohannes — Teacher of the Abenet School and Scholar of Degua.',
            style: TextStyle(color: c.text, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 14),
          Text('አማርኛ', style: TextStyle(color: c.gold, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            'ይህ መተግበሪያ በጀሞ መድኃኔዓለም የፍኖተ ያሬድ አቤኔት ትምህርት ቤት ተማሪዎች የተሠራ ሲሆን፣ ለአቤኔት ትምህርት ቤቱ መምህርና የድጓ ምሁር ለሆኑት ለ"የኔታ ዮሐንስ" የተሰጠ ትሩፋት ነው።',
            style: TextStyle(color: c.text, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 14),
          Container(height: 0.5, color: c.border),
          const SizedBox(height: 14),
          Text('Version 1.0.0', style: TextStyle(color: c.muted, fontSize: 12)),
        ])),
        actions: [
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(8)),
              child: Text('Close', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  void _showLicense() {
    final c = AppColors(widget.isDark);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('MIT License', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Text(
          'Copyright (c) 2026 Finote Yared Abenet School\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the Software), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.',
          style: TextStyle(fontSize: 12, color: c.muted, height: 1.6),
        )),
        actions: [
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(8)),
              child: Text('Close', style: TextStyle(color: widget.isDark ? const Color(0xFF0F0505) : Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(widget.isDark);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        Container(
          color: c.hero, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(children: [
            Container(width: 4, height: 20, color: c.gold, margin: const EdgeInsets.only(right: 10)),
            Text('MORE', style: TextStyle(fontSize: 16, color: c.text, letterSpacing: 3, fontWeight: FontWeight.w800)),
          ]),
        ),
        Divider(color: c.border, height: 0.5),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(children: [

          // ── Account ──
          _sectionLabel('ACCOUNT', c),
          _settingsCard(c, children: [
            if (_profile != null) ...[
              _infoRow(_profile!.name, _profile!.role, Icons.person_outline, c),
              Divider(color: c.border, height: 0.5),
            ],
            _actionRow('Log Out', Icons.logout, c, c.red, _logout),
          ]),

          // ── Notifications ──
          _sectionLabel('NOTIFICATIONS', c),
          _settingsCard(c, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Icon(Icons.notifications_outlined, color: c.gold, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Prayer Notifications', style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w600)),
                  Text('Church bell sound at prayer times', style: TextStyle(fontSize: 12, color: c.muted)),
                ])),
                Switch(
                  value: _notificationsEnabled,
                  onChanged: _saveNotif,
                  activeColor: c.gold,
                ),
              ]),
            ),
          ]),

          // ── Display ──
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
                Slider(
                  value: _fontSize,
                  min: 0.8, max: 1.4, divisions: 6,
                  activeColor: c.gold,
                  inactiveColor: c.border,
                  onChanged: _saveFontSize,
                ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('A', style: TextStyle(fontSize: 10, color: c.muted)),
                  Text('A', style: TextStyle(fontSize: 18, color: c.muted, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
          ]),

          // ── App ──
          _sectionLabel('APP', c),
          _settingsCard(c, children: [
            _actionRow('Rate Us', Icons.star_outline, c, c.gold, () {
              showDialog(context: context, builder: (ctx) => AlertDialog(
                backgroundColor: c.card,
                title: Text('Rate Yenefs_Abat', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
                content: Text('Thank you for using Yenefs_Abat! Please rate us on the Play Store.', style: TextStyle(color: c.muted, fontSize: 13)),
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
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
                    child: SelectableText('yenefsabat@gmail.com', style: TextStyle(color: c.gold, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  Text('Tap and hold the email to copy it, then open Gmail to send us a message.', style: TextStyle(color: c.muted, fontSize: 12)),
                ]),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK', style: TextStyle(color: c.gold)))],
              ));
            }),
          ]),

          // ── About ──
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
    decoration: BoxDecoration(
      color: c.card, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.border, width: 0.5),
      boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
    ),
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
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: c.goldBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.gold, width: 0.5)),
        child: Center(child: Icon(icon, color: c.gold, size: 20)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w700)),
        Text(role, style: TextStyle(fontSize: 12, color: c.muted)),
      ])),
    ]),
  );
}
