<div align="center">

<img src="assets/images/logo.png" width="150" height="150" style="border-radius: 50%;" alt="Yenefs Abat Logo"/>

# YENEFS_ABAT — የነፍስ አባት

### A Spiritual Companion App for Ethiopian Orthodox Tewahedo Faithful

[![Flutter](https://img.shields.io/badge/Flutter-3.12+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-C9A84C?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://play.google.com/store)

---

*"ምንድን ነው ለሰው ነፍሱን ቢያተርፍ ዓለሙን ሁሉ ቢያተርፍ?"*
**— ማቴዎስ 16:26**

</div>

---

## 📖 About

**Yenefs Abat (የነፍስ አባት)** is a spiritual companion mobile app built for members of the **Ethiopian Orthodox Tewahedo Church (EOTC)**. It helps believers track their confession, penance, daily prayers, and follow the rich EOTC liturgical calendar — all in one beautifully designed app.

This app was created by students of **Finote Yared Abenet School of Jemo Medhanialem**, and is dedicated to **"የኔታ ዮሐንስ"** — Teacher of the Abenet School and Scholar of Degua.

> ይህ መተግበሪያ በጀሞ መድኃኔዓለም የፍኖተ ያሬድ አቤኔት ትምህርት ቤት ተማሪዎች የተሠራ ሲሆን፣ ለአቤኔት ትምህርት ቤቱ መምህርና የድጓ ምሁር ለሆኑት ለ**"የኔታ ዮሐንስ"** የተሰጠ ትሩፋት ነው።

---

## ✨ Features

### 🕯️ Prayer Reminders
- Set daily prayer times for **Morning, Noon, Evening and Night**
- Beautiful alarm-style time picker
- Church bell notification sound at each prayer time

### 📿 Confession Guide (ኑዛዜ ዝርዝር)
- Complete list of **28 sins** according to EOTC teaching
- Both **Amharic and English** side by side
- Tick each sin you have committed
- Add personal notes to each sin
- **Save** your confession list and return to it anytime
- **Confession History** — view all your past saved confessions
- One-tap **"I Confessed"** button that clears your list and records the date

### 📜 Penance Tracker (የተሠጦት ቅኖና)
- Add penance assigned by your priest
- Types include: **ስግደት, ጾም, መዝሙረ ዳዊት, ቅዳሴ, ምጽዋት, ውዳሴ ማርያም** and more
- Track progress with a visual progress bar
- **+ Mark One Done** button for each session
- When complete — notifies you to return to your priest

### 📅 Ethiopian Orthodox Calendar
- Full **Ethiopian Calendar** with all 13 months
- Shows **saint and feast for every single day** when tapped
- **Annual feasts highlighted in gold** (⭐) on the calendar grid
- Scrollable list of all annual feasts for the current month
- **Gregorian ↔ Ethiopian date converter**

### 👤 Profile & Sign In
- Personal profile with name, age, gender and church role
- Roles: **ምዕመን, ዲያቆን, ካህን, የሰንበት ትምህርት ቤት ተማሪ, ዘማሪ, መርጌታ, አስተማሪ**

### ⚙️ More / Settings
- 🔔 Notifications on/off toggle
- 🔤 Font size adjustment
- 👤 Account details
- 🚪 Log out
- ⭐ Rate the app
- 📤 Share the app
- ✉️ Contact us
- ℹ️ About us
- 📄 MIT License

---

## 📱 Screenshots

> *Coming soon*

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) `^3.12.1`
- [Android Studio](https://developer.android.com/studio) or [VS Code](https://code.visualstudio.com/)
- Android device or emulator (API 21+)

### Installation

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/yenefs_abat.git

# Navigate to project directory
cd yenefs_abat

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Build APK

```bash
flutter build apk --release
```

The APK will be at:
```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 🛠️ Built With

| Technology | Purpose |
|---|---|
| [Flutter](https://flutter.dev) | Cross-platform UI framework |
| [Dart](https://dart.dev) | Programming language |
| [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) | Prayer time notifications with church bell sound |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Local data persistence |

---

## 📁 Project Structure

```
yenefs_abat/
├── lib/
│   └── main.dart          # Complete app source code
├── assets/
│   ├── images/
│   │   └── logo.png       # App logo
│   └── sounds/
│       └── church_bell.mp3 # Notification sound
├── fonts/
│   └── NotoSansEthiopic-VariableFont_wdth,wght.ttf
├── android/               # Android-specific files
└── pubspec.yaml           # Dependencies and assets
```

---

## 👥 Contributors

<table>
  <tr>
    <td align="center">
      <b>Abenezer Mandefro</b><br/>
      <sub>Developer & Designer</sub><br/>
      <a href="https://github.com/AbenezerMandefro">@AbenezerMandefro</a>
    </td>
    <td align="center">
      <b>Bereket Elias</b><br/>
      <sub>Developer & Designer</sub><br/>
      <a href="https://github.com/BelaElias">@BelaElias</a>
    </td>
  </tr>
</table>

---

## 🏫 About the School

This project was built at **Finote Yared Abenet School**, located at **Jemo Medhanialem, Addis Ababa, Ethiopia** — a school dedicated to preserving and teaching Ethiopian Orthodox Tewahedo traditions, liturgical music (Degua), and spiritual education.

---

## 📄 License

```
MIT License

Copyright (c) 2026 Finote Yared Abenet School

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
```

---

<div align="center">

Made with ❤️ and ✝️ for the EOTC faithful

**Yenefs Abat — የነፍስ አባት**

</div>
