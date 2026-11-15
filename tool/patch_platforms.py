#!/usr/bin/env python3
"""Poprawki nakładane na katalogi wygenerowane przez `flutter create` (idempotentne)."""
import json
import os
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "Forma"
PACKAGE = "pl.rafal.forma"


def log(msg):
    print(f"[patch] {msg}")


def icon_source():
    try:
        from PIL import Image  # noqa
    except ImportError:
        log("brak Pillow — pomijam ikony")
        return None
    p = ROOT / "assets" / "icon.png"
    return p if p.exists() else None


def resize(src, dst, px):
    from PIL import Image

    im = Image.open(src).convert("RGB").resize((px, px), Image.LANCZOS)
    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst)


ANDROID_PERMS = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
    '<uses-permission android:name="android.permission.CAMERA"/>',
    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
    '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>',
    '<uses-feature android:name="android.hardware.bluetooth_le" android:required="false"/>',
] + [
    f'<uses-permission android:name="android.permission.health.{p}"/>'
    for p in [
        "READ_SLEEP", "READ_HEART_RATE", "WRITE_HEART_RATE", "READ_RESTING_HEART_RATE",
        "READ_HEART_RATE_VARIABILITY", "READ_WEIGHT", "READ_EXERCISE", "WRITE_EXERCISE",
        "READ_ACTIVE_CALORIES_BURNED", "WRITE_ACTIVE_CALORIES_BURNED",
        "READ_TOTAL_CALORIES_BURNED", "WRITE_TOTAL_CALORIES_BURNED",
        "READ_DISTANCE", "WRITE_DISTANCE",
    ]
]

RATIONALE_FILTER = '''            <intent-filter>
                <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>
            </intent-filter>
            <intent-filter>
                <action android:name="es.antonborri.home_widget.action.LAUNCH"/>
            </intent-filter>
'''

# widżet na ekranie telefonu (home_widget)
WIDGET_RECEIVER = '''        <receiver android:name=".FormaWidget" android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/forma_widget_info"/>
        </receiver>
'''

WIDGET_KT = '''package pl.rafal.forma

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class FormaWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.forma_widget).apply {
                setTextViewText(R.id.w_title, widgetData.getString("title", "Forma"))
                setTextViewText(R.id.w_sub, widgetData.getString("sub", "Stuknij, aby otworzyć"))
                setTextViewText(R.id.w_streak, widgetData.getString("streak", "🔥 0"))
                setTextViewText(R.id.w_level, widgetData.getString("level", ""))
                setOnClickPendingIntent(R.id.w_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("forma://today")))
                setOnClickPendingIntent(R.id.w_quick, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("forma://quick7")))
                setOnClickPendingIntent(R.id.w_break, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("forma://break")))
            }
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
'''

WIDGET_LAYOUT = '''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/w_root" android:layout_width="match_parent" android:layout_height="match_parent"
    android:orientation="vertical" android:padding="14dp" android:background="@drawable/forma_widget_bg">
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal">
        <TextView android:id="@+id/w_title" android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
            android:textColor="#FFFFFFFF" android:textSize="16sp" android:textStyle="bold" android:maxLines="1" android:ellipsize="end"/>
        <TextView android:id="@+id/w_streak" android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:textColor="#FFFFB347" android:textSize="15sp" android:textStyle="bold"/>
    </LinearLayout>
    <TextView android:id="@+id/w_sub" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:layout_marginTop="2dp" android:textColor="#B3FFFFFF" android:textSize="12sp" android:maxLines="2"/>
    <TextView android:id="@+id/w_level" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:textColor="#80FFFFFF" android:textSize="11sp"/>
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:layout_marginTop="8dp" android:orientation="horizontal">
        <TextView android:id="@+id/w_quick" android:layout_width="0dp" android:layout_weight="1" android:layout_height="36dp"
            android:gravity="center" android:text="⚡ 7 minut" android:textColor="#FFFFFFFF" android:textStyle="bold"
            android:background="@drawable/forma_widget_btn"/>
        <TextView android:id="@+id/w_break" android:layout_width="0dp" android:layout_weight="1" android:layout_height="36dp"
            android:layout_marginStart="8dp" android:gravity="center" android:text="🧘 Przerwa" android:textColor="#FFFFFFFF"
            android:textStyle="bold" android:background="@drawable/forma_widget_btn2"/>
    </LinearLayout>
</LinearLayout>
'''

WIDGET_INFO = '''<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp" android:minHeight="110dp" android:targetCellWidth="4" android:targetCellHeight="2"
    android:updatePeriodMillis="3600000" android:initialLayout="@layout/forma_widget"
    android:resizeMode="horizontal|vertical" android:widgetCategory="home_screen"
    android:description="@string/forma_widget_desc"/>
'''

def _shape(color):
    return f'''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="{color}"/>
    <corners android:radius="18dp"/>
</shape>
'''


def write_widget(app):
    res = app / "src" / "main" / "res"
    for sub, name, text in (("layout", "forma_widget.xml", WIDGET_LAYOUT), ("xml", "forma_widget_info.xml", WIDGET_INFO),
                            ("drawable", "forma_widget_bg.xml", _shape("#F21A1D24")),
                            ("drawable", "forma_widget_btn.xml", _shape("#FFFF6A3D")),
                            ("drawable", "forma_widget_btn2.xml", _shape("#FF3A4150"))):
        (res / sub).mkdir(parents=True, exist_ok=True)
        (res / sub / name).write_text(text)
    vals = res / "values" / "forma_widget_strings.xml"
    vals.parent.mkdir(parents=True, exist_ok=True)
    vals.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="forma_widget_desc">Dzisiejszy trening, seria i szybki start</string>\n</resources>\n')
    kts = list((app / "src" / "main" / "kotlin").rglob("MainActivity.kt"))
    if not kts:
        sys.exit("[patch] BŁĄD: brak MainActivity.kt")
    (kts[0].parent / "FormaWidget.kt").write_text(WIDGET_KT)
    log("widżet: układ, opis, FormaWidget.kt")

STRAVA_CALLBACK = '''        <activity
            android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
            android:exported="true"
            android:taskAffinity="">
            <intent-filter android:label="flutter_web_auth_2">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="forma"/>
            </intent-filter>
        </activity>
'''

NOTIFY_RECEIVERS = '''        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'''

PERMISSION_ALIAS = '''        <activity-alias
            android:name="ViewPermissionUsageActivity"
            android:exported="true"
            android:targetActivity=".MainActivity"
            android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
            <intent-filter>
                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE"/>
                <category android:name="android.intent.category.HEALTH_PERMISSIONS"/>
            </intent-filter>
        </activity-alias>
'''

QUERIES = '''    <queries>
        <package android:name="com.google.android.apps.healthdata"/>
        <intent>
            <action android:name="android.support.customtabs.action.CustomTabsService"/>
        </intent>
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
        <intent>
            <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE"/>
        </intent>
    </queries>
'''


# ----------------------------------------------------------------- Android
def patch_android():
    app = ROOT / "android" / "app"
    if not app.exists():
        return
    gradle = app / "build.gradle.kts"
    kts = gradle.exists()
    if not kts:
        gradle = app / "build.gradle"
    g = gradle.read_text()
    g = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 26", g)
    g = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 26", g)

    if os.environ.get("FORMA_KEYSTORE") and "FORMA_KEYSTORE" not in g:
        if kts:
            block = '''    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("FORMA_KEYSTORE"))
            storePassword = System.getenv("FORMA_STORE_PASS")
            keyAlias = System.getenv("FORMA_KEY_ALIAS")
            keyPassword = System.getenv("FORMA_KEY_PASS")
        }
    }

    buildTypes {'''
            g = g.replace("    buildTypes {", block, 1)
            g = g.replace('signingConfig = signingConfigs.getByName("debug")',
                          'signingConfig = signingConfigs.getByName("release")')
        else:
            block = '''    signingConfigs {
        release {
            storeFile file(System.getenv("FORMA_KEYSTORE"))
            storePassword System.getenv("FORMA_STORE_PASS")
            keyAlias System.getenv("FORMA_KEY_ALIAS")
            keyPassword System.getenv("FORMA_KEY_PASS")
        }
    }

    buildTypes {'''
            g = g.replace("    buildTypes {", block, 1)
            g = g.replace("signingConfig = signingConfigs.debug", "signingConfig = signingConfigs.release")
            g = g.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
        log("podpis wydania: własny klucz")
    # R8 potrafi wyciąć metody pluginów wołane przez kanały Fluttera — wyłączamy zmniejszanie kodu.
    if "isMinifyEnabled = false" not in g and "minifyEnabled false" not in g:
        if kts:
            g = re.sub(r'(getByName\("release"\)\s*\{|release\s*\{)(?![^}]*storeFile)',
                       lambda m: m.group(0) + "\n            isMinifyEnabled = false\n            isShrinkResources = false",
                       g, count=1)
        else:
            g = re.sub(r'(buildTypes\s*\{\s*release\s*\{)',
                       lambda m: m.group(0) + "\n            minifyEnabled false\n            shrinkResources false",
                       g, count=1)
    if "isMinifyEnabled = false" not in g and "minifyEnabled false" not in g:
        sys.exit("[patch] BŁĄD: nie udało się wyłączyć R8 w " + gradle.name)
    # powiadomienia (flutter_local_notifications) wymagają desugaringu bibliotek Javy
    if "CoreLibraryDesugaring" not in g and "coreLibraryDesugaring" not in g:
        if kts:
            g = re.sub(r"(compileOptions\s*\{)", r"\1\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
            g = g.rstrip("\n") + '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        else:
            g = re.sub(r"(compileOptions\s*\{)", r"\1\n        coreLibraryDesugaringEnabled true", g, count=1)
            g = g.rstrip("\n") + "\n\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
        if "esugaringEnabled" not in g:
            sys.exit("[patch] BŁĄD: nie udało się włączyć desugaringu w " + gradle.name)
    gradle.write_text(g)
    log(f"{gradle.name}: minSdk 26, bez R8, desugaring")

    props = ROOT / "android" / "gradle.properties"
    pt = props.read_text() if props.exists() else ""
    if "kotlin.jvm.target.validation.mode" not in pt:
        props.write_text(pt.rstrip("\n") + "\nkotlin.jvm.target.validation.mode=warning\n")

    manifest = app / "src" / "main" / "AndroidManifest.xml"
    m = manifest.read_text()
    m = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', m, count=1)
    if "BLUETOOTH_SCAN" not in m:
        perms = "\n".join("    " + p for p in ANDROID_PERMS) + "\n"
        m = re.sub(r"(<manifest[^>]*>\n)", lambda mm: mm.group(1) + perms, m, count=1)
    if "ACTION_SHOW_PERMISSIONS_RATIONALE" not in m.split("<queries>")[0]:
        # filtr na MainActivity: Health Connect pokazuje stąd uzasadnienie uprawnień
        m = re.sub(r'(<activity\s+android:name="\.MainActivity"[^>]*>\n)', lambda mm: mm.group(1) + RATIONALE_FILTER, m, count=1)
    if "flutter_web_auth_2.CallbackActivity" not in m:
        m = m.replace("    </application>", STRAVA_CALLBACK + "    </application>", 1)
    if ".FormaWidget" not in m:
        m = m.replace("    </application>", WIDGET_RECEIVER + "    </application>", 1)
    if "ScheduledNotificationReceiver" not in m:
        m = m.replace("    </application>", NOTIFY_RECEIVERS + "    </application>", 1)
    if "ViewPermissionUsageActivity" not in m:
        m = m.replace("    </application>", PERMISSION_ALIAS + "    </application>", 1)
    if "com.google.android.apps.healthdata" not in m:
        if "<queries>" in m:
            inner = "\n".join(QUERIES.rstrip("\n").split("\n")[1:-1])
            m = m.replace("<queries>", "<queries>\n" + inner, 1)
        else:
            m = m.replace("</manifest>", QUERIES + "</manifest>", 1)
    manifest.write_text(m)
    log("AndroidManifest: nazwa, Bluetooth, Health Connect")

    # Health Connect wymaga FlutterFragmentActivity
    for kt in (app / "src" / "main" / "kotlin").rglob("MainActivity.kt"):
        t = kt.read_text()
        t = t.replace("import io.flutter.embedding.android.FlutterActivity",
                      "import io.flutter.embedding.android.FlutterFragmentActivity")
        t = re.sub(r":\s*FlutterActivity\(\)", ": FlutterFragmentActivity()", t)
        kt.write_text(t)
        log(f"{kt.name}: FlutterFragmentActivity")
    write_widget(app)

    src = icon_source()
    if src:
        sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
        for d, px in sizes.items():
            resize(src, app / "src" / "main" / "res" / f"mipmap-{d}" / "ic_launcher.png", px)
        log("ikony Androida")


# --------------------------------------------------------------------- iOS
ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.developer.healthkit</key>
\t<true/>
\t<key>com.apple.developer.healthkit.access</key>
\t<array/>
</dict>
</plist>
"""


def patch_ios():
    runner = ROOT / "ios" / "Runner"
    if not runner.exists():
        return
    plist_path = runner / "Info.plist"
    with open(plist_path, "rb") as f:
        pl = plistlib.load(f)
    pl["CFBundleDisplayName"] = APP_NAME
    pl["NSBluetoothAlwaysUsageDescription"] = (
        "Forma łączy się z opaską lub zegarkiem, żeby pokazywać tętno podczas treningu.")
    pl["NSHealthShareUsageDescription"] = (
        "Forma odczytuje sen, tętno spoczynkowe, HRV i wagę, żeby dopasować trening do Twojej formy.")
    pl["NSHealthUpdateUsageDescription"] = "Forma zapisuje treningi, tętno i spalone kalorie w aplikacji Zdrowie."
    pl["NSMicrophoneUsageDescription"] = "Forma słucha komend głosowych podczas treningu („dalej”, „pauza”, „za trudne”)."
    pl["NSCameraUsageDescription"] = (
        "Forma używa aparatu do liczenia powtórzeń i oceny ruchu oraz do pomiaru HRV palcem na obiektywie. "
        "Obraz jest analizowany tylko na telefonie."
    )
    pl["NSSpeechRecognitionUsageDescription"] = "Rozpoznawanie mowy zamienia Twoje komendy w sterowanie treningiem."
    with open(plist_path, "wb") as f:
        plistlib.dump(pl, f)
    log("Info.plist: Bluetooth i Zdrowie")

    (runner / "Runner.entitlements").write_text(ENTITLEMENTS)
    pbx = ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj"
    if pbx.exists():
        t = pbx.read_text()
        t = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.5;", t)
        if "CODE_SIGN_ENTITLEMENTS" not in t:
            t = re.sub(r"(\n(\s*)PRODUCT_BUNDLE_IDENTIFIER = " + re.escape(PACKAGE) + r";)",
                       lambda m: f"\n{m.group(2)}CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;" + m.group(1), t)
        pbx.write_text(t)
        log("Xcode: iOS 15.5, uprawnienia HealthKit")

    podfile = ROOT / "ios" / "Podfile"
    if podfile.exists():
        p = podfile.read_text()
        p = re.sub(r"^#?\s*platform :ios, '[0-9.]+'", "platform :ios, '15.5'", p, flags=re.M)
        podfile.write_text(p)
        log("Podfile: iOS 15.5")

    src = icon_source()
    iconset = runner / "Assets.xcassets" / "AppIcon.appiconset"
    contents = iconset / "Contents.json"
    if src and contents.exists():
        data = json.loads(contents.read_text())
        for img in data.get("images", []):
            fn = img.get("filename")
            if not fn:
                continue
            base = float(img["size"].split("x")[0])
            scale = int(img.get("scale", "1x").rstrip("x"))
            resize(src, iconset / fn, int(round(base * scale)))
        log("ikony iOS")


if __name__ == "__main__":
    only = sys.argv[1:] or ["android", "ios"]
    if "android" in only:
        patch_android()
    if "ios" in only:
        patch_ios()
