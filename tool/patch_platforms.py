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
    gradle.write_text(g)
    log(f"{gradle.name}: minSdk 26, bez R8")

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
    with open(plist_path, "wb") as f:
        plistlib.dump(pl, f)
    log("Info.plist: Bluetooth i Zdrowie")

    (runner / "Runner.entitlements").write_text(ENTITLEMENTS)
    pbx = ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj"
    if pbx.exists():
        t = pbx.read_text()
        t = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 14.0;", t)
        if "CODE_SIGN_ENTITLEMENTS" not in t:
            t = re.sub(r"(\n(\s*)PRODUCT_BUNDLE_IDENTIFIER = " + re.escape(PACKAGE) + r";)",
                       lambda m: f"\n{m.group(2)}CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;" + m.group(1), t)
        pbx.write_text(t)
        log("Xcode: iOS 14, uprawnienia HealthKit")

    podfile = ROOT / "ios" / "Podfile"
    if podfile.exists():
        p = podfile.read_text()
        p = re.sub(r"^#?\s*platform :ios, '[0-9.]+'", "platform :ios, '14.0'", p, flags=re.M)
        podfile.write_text(p)
        log("Podfile: iOS 14")

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
