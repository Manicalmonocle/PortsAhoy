# Getting Ports Ahoy! onto Google Play

## Why bother, given sideloading works

Play Protect warns on anything it has not seen signed by a known developer.
That warning is doing its job — it cannot tell your build from a malicious one —
and testers will hit it on every install. Distributing through Play removes it,
because the install comes from Play.

It also starts the clock you need anyway. **Internal testing does NOT count
toward the 12-tester requirement — only closed testing does.** Start closed
testing early or it becomes the long pole at the end.

## What to upload

    build/app/outputs/bundle/release/app-release.aab

Play requires an Android App Bundle (.aab) for new apps, not an APK. Rebuild with:

    export JAVA_HOME=$HOME/android/jdk
    export ANDROID_HOME=$HOME/android/sdk
    export PATH=$JAVA_HOME/bin:$HOME/flutter/bin:$PATH
    flutter build appbundle --release

Signed with the upload key in `~/ports_ahoy_keys/`. Fingerprint:

    SHA256: E7:2F:9E:56:4C:98:0F:1E:01:C1:C1:27:45:AF:C2:5A:D3:CC:69:ED:BC:77:F3:8B:C2:C6:29:AA:EB:EA:41:F5

If an upload is ever rejected for the wrong key, check `android/key.properties`
still exists — without it the build silently falls back to debug signing.

## Every upload needs a higher version code

`pubspec.yaml` line 19:

    version: 1.0.0+1
                   ^ this is the versionCode Play sorts on

Bump the number after `+` for every single upload, even a re-upload of the same
build. Play rejects a duplicate. Bump the part before it when the *release*
changes meaningfully.

## Setup, in order

1. **Register** — $25 once, at play.google.com/console. Personal account is fine.
2. **Create the app** — name "Ports Ahoy!", free, game.
3. **Upload the .aab to a CLOSED testing track.** Not internal — internal does
   not count toward production access.
4. **Add testers** by email, or make an email list. You need **12 who stay
   opted in for 14 unbroken days**. The clock starts when the *twelfth* joins,
   so add everyone before you start counting.
5. **Fill in the declarations** — content rating questionnaire, data safety,
   target audience, ads (declare: none), news (no), COVID (no).
6. **Store listing** — short description, full description, at least 2
   screenshots, a 512×512 icon (`store/play-icon-512.png`) and a 1024×500
   feature graphic.
7. After 14 days with 12 testers, **apply for production access** on the
   dashboard.

## Declarations that are unusually easy here

Because the game genuinely has none of it:

* **Ads** — none.
* **In-app purchases** — none.
* **Data collection** — none. Nothing leaves the device. The only stored data
  is the save file in local `SharedPreferences`. In the Data Safety form this
  is "No data collected", "No data shared".
* **Permissions** — the manifest requests exactly one, an internal Flutter
  broadcast-receiver permission. No internet, no location, no storage, no ads
  identifier.

A privacy policy URL is still required for the listing even with no data
collected. One paragraph stating that the app collects and transmits nothing is
enough, hosted anywhere public.

## While you are still sideloading

Testers will see "Unsafe app blocked" or similar. They can proceed via
**More details → Install anyway**. It is worth telling them up front that this
is expected for any app not yet distributed through Play, so nobody assumes
something is wrong with the build.
