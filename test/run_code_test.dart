import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/journal.dart';
import 'package:ports_ahoy/sim/run_code.dart';
import 'package:ports_ahoy/report_endpoint.dart';
import 'package:ports_ahoy/sim/trade.dart';

RunJournal _sampleRun({int days = 200, int marks = 70}) {
  final j = RunJournal();
  for (var d = 1; d <= days; d++) {
    j.record(JournalDay(
      day: d,
      population: 8 + d ~/ 4,
      coin: 40 + d * 13,
      buildings: 3 + d ~/ 8,
      staffed: 1 + d ~/ 10,
      foodDays: 12.3,
      atSea: d % 3,
    ));
  }
  for (var i = 0; i < marks; i++) {
    final day = i * 3 + 1;
    if (i % 3 == 0) {
      j.mark(day, 'built a sawmill', code: RunCode.buildMark(day, 'sawmill'));
    } else if (i % 3 == 1) {
      j.mark(day, 'sent goods',
          code: RunCode.voyageMark(day, 34, 'The Reaches', 2.5, 412));
    } else {
      j.mark(day, 'hired someone',
          code: RunCode.hireMark(day, 'merchant', 2, 180));
    }
  }
  return j;
}

String _encode(RunJournal j, {int maxChars = 5500}) => RunCode.encode(
      j,
      version: '1.0.8+9',
      seed: 1234567,
      difficulty: 3,
      charters: const ['poor_soil', 'bitter_seas'],
      won: true,
      maxChars: maxChars,
    );

void main() {
  group('short codes', () {
    // Derived codes are only safe while they stay unique. A future building
    // called "forge" would collide with "forest_camp" and the decoder would
    // mislabel one of them silently, forever. This is the guard that makes
    // deriving them safe rather than lucky.
    test('every building id gets a distinct code', () {
      final seen = <String, String>{};
      for (final d in kBuildingDefs) {
        final c = shortCode(d.id);
        expect(seen.containsKey(c), isFalse,
            reason: 'building code "$c" is shared by ${seen[c]} and ${d.id} — '
                'give one of them a longer code in RunCode.shortCode');
        seen[c] = d.id;
      }
      expect(seen.length, kBuildingDefs.length);
    });

    test('every destination gets a distinct code', () {
      final seen = <String, String>{};
      for (final d in kDestinations) {
        final c = shortCode(d.name);
        expect(seen.containsKey(c), isFalse,
            reason: 'destination code "$c" is shared by ${seen[c]} and ${d.name}');
        seen[c] = d.name;
      }
      expect(seen.length, kDestinations.length);
    });
  });

  group('PA1 encoding', () {
    test('a 200-day run fits inside a URL at full daily resolution', () {
      final code = _encode(_sampleRun());
      expect(code.length, lessThan(5500));
      // Nothing was thinned: stride 1 means every day survived.
      expect(RunCode.decode(code).stride, 1);
    });

    // THIS IS THE PRIVACY TEST. Every character being unreserved means the
    // encoded length equals the raw length — but more importantly it means no
    // free text can have got in, because prose contains spaces and commas.
    // If someone ever interpolates JournalMark.what, or a player-typed name,
    // into the payload, this goes red before it ships.
    test('carries nothing but URL-safe characters', () {
      final code = _encode(_sampleRun());
      expect(RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(code), isTrue,
          reason: 'PA1 must contain no free text and no reserved characters');
      expect(Uri.encodeQueryComponent(code).length, code.length,
          reason: 'encoding must not inflate the payload');
    });

    test('marks without a code are never guessed at from prose', () {
      final j = RunJournal()
        ..record(const JournalDay(
            day: 1,
            population: 5,
            coin: 10,
            buildings: 3,
            staffed: 1,
            foodDays: 5,
            atSea: 0))
        ..mark(1, 'something a player typed, with commas & spaces');
      final code = _encode(j);
      expect(code, isNot(contains('player')));
      expect(RunCode.decode(code).marks, isEmpty);
    });

    test('round-trips days and marks unchanged', () {
      final j = _sampleRun(days: 60, marks: 12);
      final back = RunCode.decode(_encode(j));

      expect(back.version, '1.0.8-9');
      expect(back.seed, 1234567);
      expect(back.difficulty, 3);
      expect(back.charters, ['poor_soil', 'bitter_seas']);
      expect(back.won, isTrue);
      expect(back.days.length, j.days.length);

      for (var i = 0; i < j.days.length; i++) {
        expect(back.days[i].day, j.days[i].day);
        expect(back.days[i].population, j.days[i].population);
        expect(back.days[i].coin, j.days[i].coin);
        expect(back.days[i].buildings, j.days[i].buildings);
        expect(back.days[i].staffed, j.days[i].staffed);
        expect(back.days[i].atSea, j.days[i].atSea);
        expect(back.days[i].foodDays, closeTo(j.days[i].foodDays, 0.05));
      }

      final voyage = back.marks.firstWhere((m) => m.kind == 'voyage');
      expect(voyage.fields['units'], 34);
      expect(voyage.fields['destination'], 'the');
      expect(voyage.fields['days'], 2.5);
      expect(voyage.fields['quote'], 412);

      final hire = back.marks.firstWhere((m) => m.kind == 'hire');
      expect(hire.fields['track'], 'm');
      expect(hire.fields['level'], 2);
    });

    test('a run too long for the budget thins days instead of failing', () {
      final j = _sampleRun(days: 400, marks: 250);
      final code = _encode(j);
      final back = RunCode.decode(code);

      expect(code.length, lessThan(5500));
      expect(back.stride, greaterThan(1),
          reason: 'an over-long run must degrade by widening the stride');
      // Day numbering must stay honest after thinning, or every milestone
      // lines up against the wrong day.
      expect(back.days.first.day, 1);
      expect(back.days[1].day, 1 + back.stride);
    });

    test('reports when the journal stopped recording', () {
      final j = _sampleRun(days: RunJournal.maxDays + 50);
      expect(j.daysTruncated, isTrue);
      expect(RunCode.decode(_encode(j)).daysTruncated, isTrue);
      expect(
          j.report(charters: '', difficulty: 0, won: false), contains('TRUNCATED'));
    });

    test('truncation survives a save and load', () {
      final j = _sampleRun(days: RunJournal.maxDays + 10);
      expect(RunJournal.fromJson(j.toJson()).daysTruncated, isTrue);
    });

    test('rejects input that is not a run code', () {
      expect(() => RunCode.decode('hello'), throwsFormatException);
      expect(() => RunCode.decode('PA1~1~2'), throwsFormatException);
    });
  });

  _endpointTests();
}

void _endpointTests() {
  group('report endpoint', () {
    const payload = 'PA1~1.0.8-9~abc~0~~0~5~0~1~Mb7.far~D5.7w.3.2.1q.0';

    test('nothing is offered until a destination is configured', () {
      expect(ReportEndpoint.configuredFor(ReportDestination.none), isFalse);
      expect(ReportEndpoint.urlFor(ReportDestination.none, payload), isNull);
      // A half-filled form config must count as unconfigured, not build a
      // URL that 404s on the tester's phone.
      expect(
          ReportEndpoint.configuredFor(ReportDestination.googleForm,
              form: 'abc', entry: ''),
          isFalse);
    });

    test('a Google Form link carries the payload in the prefill field', () {
      final u = ReportEndpoint.urlFor(ReportDestination.googleForm, payload,
          form: 'FORMID', entry: '123456')!;
      expect(u.host, 'docs.google.com');
      expect(u.path, '/forms/d/e/FORMID/viewform');
      expect(u.queryParameters['entry.123456'], payload);
      expect(u.queryParameters['usp'], 'pp_url');
    });

    test('a GitHub link fences the payload and asks for no label', () {
      final u = ReportEndpoint.urlFor(ReportDestination.githubIssue, payload,
          gh: 'owner/repo')!;
      expect(u.host, 'github.com');
      expect(u.path, '/owner/repo/issues/new');
      expect(u.queryParameters['body'], contains(payload));
      // labels= makes GitHub serve a 404 to anyone without write access.
      expect(u.queryParameters.containsKey('labels'), isFalse);
    });

    // Measured against GitHub's own endpoint: ~6000 encoded characters is
    // accepted, 8000 kills the connection with no status at all, 12000 gives
    // a 414. Since navigation is one-way the app cannot detect the failure —
    // so an over-long payload must be refused here, before anything opens.
    test('an over-long payload is refused rather than sent and lost', () {
      final huge = 'PA1~${'a' * 9000}';
      expect(
          ReportEndpoint.urlFor(ReportDestination.githubIssue, huge,
              gh: 'owner/repo'),
          isNull);
      expect(
          ReportEndpoint.urlFor(ReportDestination.googleForm, huge,
              form: 'F', entry: '1'),
          isNull);
    });

    test('the GitHub budget is halved for the signed-out redirect', () {
      // A logged-out tester's whole URL is echoed back inside ?return_to=,
      // so the payload has to survive being carried twice.
      expect(ReportEndpoint.maxPayloadFor(ReportDestination.githubIssue),
          lessThan(ReportEndpoint.maxPayloadFor(ReportDestination.googleForm)));
    });

    test('an email link addresses the inbox and carries the payload', () {
      final u = ReportEndpoint.urlFor(ReportDestination.email, payload,
          mail: 'someone@example.com')!;
      expect(u.scheme, 'mailto');
      expect(u.path, 'someone@example.com');
      expect(u.queryParameters['body'], contains(payload));
      // Percent-encoded by Uri, not concatenated: a raw '&' in the body would
      // otherwise end the parameter and deliver half a run.
      expect(u.toString(), contains('%'));
    });

    // The whole reason email is acceptable as a transport. A mail client that
    // silently clips a long mailto: produces a payload indistinguishable from
    // a shorter run, and the analysis would read the truncation as a player
    // who stopped playing.
    test('a payload cut in transit is detected, not believed', () {
      final j = _sampleRun(days: 40, marks: 6);
      final code = _encode(j);
      expect(RunCode.decode(code).lostInTransit, isFalse);

      final cut = code.substring(0, code.length - 60);
      final back = RunCode.decode(cut);
      expect(back.lostInTransit, isTrue);
      expect(back.declaredDays, 40);
      expect(back.days.length, lessThan(40));
    });

    // The app must never hold a credential. Both identifiers here are public
    // by construction, and this is the guard that keeps it that way.
    test('no destination setting looks like a secret', () {
      for (final v in [ReportEndpoint.formId, ReportEndpoint.entryId,
          ReportEndpoint.repo, ReportEndpoint.inbox]) {
        expect(RegExp(r'gh[pousr]_|ghs_|github_pat_|AIza').hasMatch(v), isFalse,
            reason: 'a token must never be compiled into a public build');
      }
    });
  });
}
