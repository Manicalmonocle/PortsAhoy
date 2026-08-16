/// The build's own version, shown in the app and stamped into run reports.
///
/// WHY A CONSTANT AND NOT A PLUGIN. Reading the real package version at runtime
/// needs a dependency; this needs nothing, and a test asserts it matches
/// `pubspec.yaml` — so it cannot drift without turning the suite red. That is
/// the same guard used everywhere else here, because a version string that
/// silently lies is worse than none at all: a bug report stamped with the wrong
/// build sends you looking in the wrong place.
///
/// Regenerate with `dart run tool/stamp_version.dart` (build_apk.sh does it
/// for you).
const String kAppVersion = '1.2.0+18';
