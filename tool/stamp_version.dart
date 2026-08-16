// Copy the version out of pubspec.yaml into lib/version.dart.
//
// Run after bumping the version, or just let tool/build_apk.sh do it. A test
// asserts the two agree, so forgetting turns the suite red rather than shipping
// a build that misreports itself.
// ignore_for_file: avoid_print
import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
  if (match == null) {
    stderr.writeln('No version: line in pubspec.yaml');
    exit(1);
  }
  final version = match.group(1)!;

  final out = File('lib/version.dart');
  final existing = out.readAsStringSync();
  final updated = existing.replaceFirst(
      RegExp(r"const String kAppVersion = '[^']*';"),
      "const String kAppVersion = '$version';");

  if (updated == existing) {
    print('lib/version.dart already at $version');
    return;
  }
  out.writeAsStringSync(updated);
  print('lib/version.dart stamped to $version');
}
