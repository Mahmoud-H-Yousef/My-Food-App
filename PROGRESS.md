# My Food: build progress

Flutter Android app. Source here, builds go to `C:\dev\builds\myfood` (junctions; OneDrive locks build files).
Build from the junction: `cd C:\dev\myfood-src && flutter build apk --release --no-tree-shake-icons`
(kill `java.exe` first if Gradle says "Unable to delete directory").

Each stage gets an APK in `APKs/` and a git tag:

| Stage | APK | Git tag | Contents |
|---|---|---|---|
| v1 | My Food v1.apk | v1 | Food DB (USDA + world dishes, EN/AR), onboarding + goals, daily log, quick add, copy day, water, weight + charts, My Pot recipes, custom foods |
| v2 | My Food v2.apk | v2 | Barcode (Open Food Facts), meal planner, shopping list, what-can-I-cook, Health Connect, Google Drive backup, export/import file |
| v3 | My Food v3.apk | v3 | Gemma on-device AI (text + photo), optional Gemini key, Ramadan mode |
| final | My Food.apk | final | Polish |

## Data
- `tools/build_usda.dart` turns the USDA SR Legacy CSV into `assets/data/usda.tsv`.
- `assets/data/world.txt` is the hand-made list of world dishes + common ingredients (EN + AR names, real-life portions). Values are estimates.
- `tools/make_icon.dart` draws the launcher icon; then `dart run flutter_launcher_icons`.

## Status
- [x] v1
- [x] v2
- [ ] v3
- [ ] final
