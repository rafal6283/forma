# Forma

Trening w domu z lokalnym trenerem — Android i iOS (Flutter).

- **Trener na telefonie**: ocena gotowości (sen, tętno spoczynkowe, HRV, samopoczucie, obciążenie tygodnia), dobór rodzaju treningu, ćwiczeń, czasu pracy i przerw; uczy się z ocen RPE po treningu.
- **64 ćwiczenia z animacjami** — głównie bez sprzętu, opcjonalnie krzesło, hantle, kettlebell, guma, drążek.
- **Tętno z opasek i zegarków BLE** (standardowa usługa Heart Rate 0x180D), strefy, pomiar HRV z odstępów RR.
- **Health Connect / Zdrowie**: zapis treningów z tętnem i kaloriami; odczyt snu (np. z Rytmu Snu), tętna, HRV i wagi.
- **Kopia na Koofr** — wspólny moduł `koofr_backup_ui` z Rytmu Snu (appId `forma`).

## Ćwiczenia i animacje

Źródłem bazy jest `tool/build_exercises.py` (pozy szkieletu + metadane) → `assets/exercises.json`.
Podgląd wszystkich póz bez telefonu:

```
python3 tool/build_exercises.py && python3 tool/render_preview.py build/poses.png
```

Kinematyka w `tool/figure.py` i `lib/core/figure.dart` musi być identyczna.

## Build

GitHub Actions (`.github/workflows/build.yml`) generuje katalogi platform (`tool/prepare_platforms.sh`),
buduje APK (podpisany kluczem z `signing/`) i niepodpisaną IPA, i publikuje je jako wydanie `build-N`.
