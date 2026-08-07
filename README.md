# کاوشگر تلگرام (Telegram Explorer)

اکسپلورر فایل روی Saved Messages تلگرام — پرشان.

## ساختار پروژه

فقط `lib/` و `pubspec.yaml` در ریپازیتوری نگه‌داری می‌شن. پوشهٔ `android/`
عمداً commit نمی‌شه (در `.gitignore`) و هر بار در GitHub Actions با دستور
`flutter create --platforms=android .` از نو ساخته می‌شه — این یعنی فایل‌های
Gradle همیشه توسط خودِ ابزار فلاتر تولید می‌شن، نه دستی، و کمتر خراب می‌شن.

```
lib/
  main.dart                 نقطهٔ ورود
  app.dart                  روتینگ بین Settings / Login / Explorer بر اساس وضعیت اتصال
  theme/app_theme.dart      تم Fluent با accent طلایی/برنجی
  models/manifest.dart      مدل‌های فولدر / تگ / آیتم (همون schema که طراحی کردیم)
  services/
    settings_service.dart   ذخیرهٔ امن api_id / api_hash (از داخل خود برنامه)
    td_service.dart         لایهٔ پایه‌ای FFI روی TDLib (send/receive/@extra)
    auth_service.dart       مدیریت مراحل ورود (شماره → کد → رمز دومرحله‌ای)
    manifest_service.dart   کش محلی SQLite + همگام‌سازی با پیام سنجاق‌شدهٔ منیفست
  screens/
    settings_screen.dart    فرم ورود api_id/api_hash
    login_screen.dart       فرم شماره/کد/رمز
    explorer_screen.dart    صفحهٔ اصلی (nav pane + آیکونی/لیستی + جزئیات)
    widgets/file_icons.dart آیکون فولدر و آیکون‌های رنگی نوع فایل
```

## قبل از اولین اجرا

۱. یک `api_id` و `api_hash` رایگان و مخصوص حساب خودت از
   <https://my.telegram.org> بگیر.
۲. برنامه رو نصب کن (از artifact خروجی GitHub Actions)، وارد تنظیمات شو،
   این دو مقدار رو وارد کن. این‌ها فقط روی خود دستگاه و به‌صورت رمزنگاری‌شده
   (`flutter_secure_storage`) ذخیره می‌شن — جایی در کد هارد‌کد نشدن.
۳. بعد وارد شمارهٔ تلفن، کد پیامکی، و در صورت فعال بودن، رمز دومرحله‌ای می‌شی.

## ساخت APK با GitHub Actions

هر push به شاخهٔ `main` به‌صورت خودکار در `.github/workflows/build-apk.yml`
اجرا می‌شه:
فلاتر نصب → `flutter create --platforms=android .` → `flutter pub get` →
`flutter build apk --release` → آپلود APK به‌عنوان artifact اجرا.

برای دانلود: به تب **Actions** ریپازیتوری برو → آخرین اجرای موفق → پایین
صفحه، بخش **Artifacts** → `telegram-explorer-apk`.

### اگر مرحلهٔ Build APK با خطای ۴۰۱/۴۰۳ شکست خورد

پکیج `libtdjson` باینری از پیش کامپایل‌شدهٔ Android رو از GitHub Packages
ریپازیتوری دیگه‌ای (`up9cloud/android-libtdjson`) می‌گیره. این باید با
`GITHUB_TOKEN` پیش‌فرض اکشن‌ها کار کنه چون پکیج عمومیه، اما اگه نکرد:
یک Personal Access Token (classic) با scope فقط `read:packages` بساز،
به‌عنوان یک repository secret (مثلاً `TD_READ_TOKEN`) اضافه کن، و در
ورک‌فلو `secrets.GITHUB_TOKEN` رو با `secrets.TD_READ_TOKEN` جایگزین کن.

## نکات صادقانه دربارهٔ وضعیت فعلی کد

این پروژه در محیطی بدون Flutter SDK و بدون دسترسی شبکه نوشته شده، پس تا
الان با `flutter analyze`/`flutter build` تست نشده — اولین کامپایل واقعی
همون اجرای اول GitHub Actions شماست. جاهایی که بیشتر از همه احتمال داره
نیاز به اصلاح جزئی داشته باشن:

- **`manifest_service.dart` → `_extractMediaInfo`**: مسیر دقیق فیلدهای
  JSON برای هر نوع پیام (`messagePhoto`, `messageVideo`, ...) بین نسخه‌های
  TDLib کمی فرق می‌کنه؛ اگه نام/حجم فایل درست استخراج نشد، این تابع اولین
  جای بررسیه.
- **`td_service.dart` → `_receiveLoop`**: فعلاً حلقهٔ `receive()` روی
  ایزولت اصلی اجرا می‌شه (برای سادگی). برای روانی کامل UI در آینده بهتره
  به یک Isolate جدا منتقل بشه.
- **فونت Vazirmatn** bundle نشده (چون دانلود فایل فونت در این محیط ممکن
  نبود) — فعلاً از فونت پیش‌فرض پلتفرم برای فارسی استفاده می‌شه. برای
  اضافه‌کردنش: فایل‌های فونت رو به `assets/fonts/` اضافه کن، در
  `pubspec.yaml` بخش `fonts:` رو تعریف کن، و در `app_theme.dart`
  `fontFamily: 'Vazirmatn'` رو برگردون.
- نسخهٔ ویندوز هنوز اضافه نشده — همون معماری (Dart + fluent_ui) روی ویندوز
  هم جواب می‌ده، فقط باید در ورک‌فلوی جدا `flutter create --platforms=windows .`
  و `flutter build windows` اضافه بشه؛ چون این تسک روی APK تمرکز داشت این
  بخش رو نگه داشتم برای قدم بعدی.
- چند تا از نام‌های `FluentIcons.*` استفاده‌شده (مثل `grid_view_medium`)
  بدون دسترسی به پکیج واقعی نوشته شدن؛ اگه کامپایلر گفت پیدا نشد، کافیه در
  ویرایشگر روی `FluentIcons.` تایپ کنی و از autocomplete نزدیک‌ترین اسم رو
  انتخاب کنی — تغییر جزئیه و منطق برنامه رو تحت تأثیر قرار نمی‌ده.
