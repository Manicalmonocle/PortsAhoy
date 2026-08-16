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

  /// A prefilled email to [ReportEndpoint.inbox]. Needs no account and no
  /// setup, but see [ReportEndpoint.maxPayloadFor] — mail clients differ
  /// wildly in what length of mailto: they will carry, and the tester's own
  /// address is attached to whatever they send.
  email,
}

class ReportEndpoint {
  /// ── CHANGE THIS LINE TO TURN THE FEATURE ON ────────────────────────────
  ///
  /// Leave as [ReportDestination.none] and the Send button stays hidden; the
  /// Copy button behaves exactly as it does today. Nothing is half-shipped.
  static const ReportDestination destination = ReportDestination.email;

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

  // ── Email ──────────────────────────────────────────────────────────────
  //
  // A dedicated address, not a personal one: it ends up in a public APK and a
  // public web bundle, where anything readable will eventually be scraped.
  static const String inbox = 'portsahoy@gmail.com';

  /// Whether Send can be offered at all.
  static bool get configured => configuredFor(destination);

  /// Split out from [configured] so a test can check every branch. With the
  /// settings above being `const`, only the one that happens to be compiled in
  /// would otherwise be reachable — and the branch that ships untested is
  /// exactly the one that breaks the day it is switched on.
  static bool configuredFor(ReportDestination d,
          {String form = formId,
          String entry = entryId,
          String gh = repo,
          String mail = inbox}) =>
      switch (d) {
        ReportDestination.none => false,
        ReportDestination.googleForm => form.isNotEmpty && entry.isNotEmpty,
        ReportDestination.githubIssue => gh.isNotEmpty,
        ReportDestination.email => mail.isNotEmpty,
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
        // The least certain number here, and chosen knowing that. Mail
        // clients disagree violently about how long a mailto: may be — many
        // carry several KB, Outlook has historically cut near 2,000 — and
        // they cut SILENTLY rather than refusing.
        //
        // Set high enough to keep a typical 120-day run at full daily
        // resolution rather than half of it. That is the right trade only
        // because RunCode.decode now sets lostInTransit when fewer rows
        // arrive than the header declares: an over-long send costs one
        // report and teaches us the real limit, where an over-cautious
        // budget would silently halve the resolution of every report
        // forever. Verify the first real send decodes complete.
        ReportDestination.email => 2600,
      };

  /// The link to open. [payload] must already be a PA1 run code.
  static Uri? url(String payload) => urlFor(destination, payload);

  static Uri? urlFor(ReportDestination d, String payload,
      {String form = formId,
      String entry = entryId,
      String gh = repo,
      String mail = inbox}) {
    if (!configuredFor(d, form: form, entry: entry, gh: gh, mail: mail)) {
      return null;
    }
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
      // Query parameters, not a hand-built string: the body must be
      // percent-encoded, and concatenating it by hand is how a payload picks
      // up a stray '&' and arrives cut in half.
      ReportDestination.email => Uri(
          scheme: 'mailto',
          path: mail,
          queryParameters: {
            'subject': 'Ports Ahoy run report',
            'body': '$payload\n\nNothing to edit — just send. '
                'Anything you want to add can go below.\n',
          },
        ),
    };
  }

  /// Whether the tester's own identity rides along with the report.
  ///
  /// The consent sheet must never claim more privacy than the transport
  /// actually gives. Email attaches the sender's address by construction, and
  /// a GitHub issue is stamped with their username on a public page — telling
  /// a player "no name, no email" in either case would be exactly the kind of
  /// comfortable lie this project is meant not to tell.
  static bool get revealsSender => switch (destination) {
        ReportDestination.none => false,
        ReportDestination.googleForm => false,
        ReportDestination.githubIssue => true,
        ReportDestination.email => true,
      };

  /// How the sheet describes what identity travels, in the player's terms.
  static String get identityNote => switch (destination) {
        ReportDestination.none || ReportDestination.googleForm =>
          'It carries the day-by-day numbers and nothing else: no name, no '
              'email, no device id, no location.',
        ReportDestination.githubIssue =>
          'It carries the day-by-day numbers and nothing else — no device id, '
              'no location — but GitHub will show your username on the issue '
              'you file.',
        ReportDestination.email =>
          'It carries the day-by-day numbers and nothing else — no device id, '
              'no location — but it is an email, so your address comes with '
              'it. Use the Copy button instead if you would rather it did '
              'not.',
      };

  /// What to call the destination in the consent sheet, so the player is told
  /// where their run is actually going before they send it.
  static String get label => switch (destination) {
        ReportDestination.none => 'nowhere',
        ReportDestination.googleForm => 'a form in your browser',
        ReportDestination.githubIssue => 'a new issue on GitHub',
        ReportDestination.email => 'an email to $inbox',
      };
}
