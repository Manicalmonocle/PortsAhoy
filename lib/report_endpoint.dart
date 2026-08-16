/// Where a tester's run report goes when they tap Send.
///
/// WHY THIS IS A FILE AND NOT A DECISION BAKED INTO THE UI. The two sensible
/// destinations suit different people, and which one is right depends on who
/// is testing rather than on anything in the code:
///
///   GitHub issues — good for you and for anyone who already has an account.
///   Reports land next to the code, are searchable, and you can reply in
///   thread. MEASURED COSTS: a logged-out tester is 302'd to a sign-in wall
///   before they can see the form, the submission is permanently stamped with
///   their real username on a world-readable page, and GitHub's own endpoint
///   accepts about 6,000 characters of URL but kills the connection outright
///   near 8,000 — and the logged-out redirect echoes the whole URL back inside
///   `return_to`, so it has to fit roughly twice over. A PA1 run code is
///   2-5 KB, so it fits; it is the sign-in wall, not the size, that decides.
///
///   A Google Form — good for friends and family. No account, no sign-in, no
///   username attached, and responses collect themselves into a Sheet. Costs
///   you about five minutes to set up, and the form id has to be pasted below.
///
/// NEITHER HOLDS A SECRET. Both are public identifiers: a form id is in every
/// prefilled link the form itself hands out, and the repo is already public.
/// Nothing here is a credential, and nothing here would be dangerous in an
/// APK that anyone can unzip — which is exactly why the app links out to a
/// page the tester submits themselves, instead of posting anywhere directly.
/// A token that let the app write on your behalf could not survive shipping in
/// a public build, and GitHub's secret scanning would revoke it anyway.
library;

enum ReportDestination {
  /// No destination configured — Send is hidden, Copy still works.
  none,

  /// A prefilled Google Form. Set [ReportEndpoint.formId] and [entryId].
  googleForm,

  /// A prefilled GitHub issue. Requires the tester to have a GitHub account.
  githubIssue,
}

class ReportEndpoint {
  /// ── CHANGE THIS LINE TO TURN THE FEATURE ON ────────────────────────────
  ///
  /// Leave as [ReportDestination.none] and the Send button stays hidden; the
  /// Copy button behaves exactly as it does today. Nothing is half-shipped.
  static const ReportDestination destination = ReportDestination.githubIssue;

  // ── Google Form ────────────────────────────────────────────────────────
  //
  // To fill these in: make a form with one long-answer question, then
  // "Send" -> link, and "Get pre-filled link". Submit a dummy answer to get a
  // URL of the shape
  //   docs.google.com/forms/d/e/<formId>/viewform?usp=pp_url&entry.<n>=test
  // and copy the two ids out of it.
  //
  // TWO SETTINGS TO CHECK, or testers hit the wall this design exists to
  // avoid: turn OFF "Collect email addresses", and if the form is made on a
  // Workspace account (an @stevesilver.com one, say) turn OFF the default
  // "restrict to users in your organisation". Verify by opening the prefilled
  // link signed-out, in a private window, on a phone.
  static const String formId = '';
  static const String entryId = '';

  // ── GitHub issue ───────────────────────────────────────────────────────
  static const String repo = 'Manicalmonocle/PortsAhoy';

  /// Whether Send can be offered at all.
  static bool get configured => configuredFor(destination);

  /// Split out from [configured] so a test can check every branch. With the
  /// settings above being `const`, only the one that happens to be compiled in
  /// would otherwise be reachable — and the branch that ships untested is
  /// exactly the one that breaks the day it is switched on.
  static bool configuredFor(ReportDestination d,
          {String form = formId, String entry = entryId, String gh = repo}) =>
      switch (d) {
        ReportDestination.none => false,
        ReportDestination.googleForm => form.isNotEmpty && entry.isNotEmpty,
        ReportDestination.githubIssue => gh.isNotEmpty,
      };

  /// The most a destination will carry before it fails.
  ///
  /// GitHub's is halved deliberately: a signed-out tester's URL is echoed back
  /// inside `return_to`, so the payload has to survive being carried twice.
  /// Overshooting is not a clean error — at 8,000 characters the connection
  /// dies with no status at all, and the app cannot see that it happened
  /// because navigation is one-way.
  static int get maxPayload => maxPayloadFor(destination);

  static int maxPayloadFor(ReportDestination d) => switch (d) {
        ReportDestination.none => 0,
        ReportDestination.googleForm => 5500,
        ReportDestination.githubIssue => 2800,
      };

  /// The link to open. [payload] must already be a PA1 run code.
  static Uri? url(String payload) => urlFor(destination, payload);

  static Uri? urlFor(ReportDestination d, String payload,
      {String form = formId, String entry = entryId, String gh = repo}) {
    if (!configuredFor(d, form: form, entry: entry, gh: gh)) return null;
    if (payload.length > maxPayloadFor(d)) return null;
    return switch (d) {
      ReportDestination.none => null,
      ReportDestination.googleForm => Uri.parse(
          'https://docs.google.com/forms/d/e/$form/viewform'
          '?usp=pp_url&entry.$entry=$payload'),
      ReportDestination.githubIssue =>
        Uri.https('github.com', '/$gh/issues/new', {
          'title': 'Run report',
          // No `labels=` parameter: a tester without write access to the repo
          // gets a 404 instead of the issue form when one is present.
          'body': 'Paste from the game — nothing to edit.\n\n```\n$payload\n```',
        }),
    };
  }

  /// What to call the destination in the consent sheet, so the player is told
  /// where their run is actually going before they send it.
  static String get label => switch (destination) {
        ReportDestination.none => 'nowhere',
        ReportDestination.googleForm => 'a form in your browser',
        ReportDestination.githubIssue => 'a new issue on GitHub',
      };
}
