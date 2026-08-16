# Play Store listing copy

## App name (30 char limit)
    Ports Ahoy!

## Short description (80 char limit)
    Run an age-of-sail trading port. No ads, no purchases, no timers. Ever.
                                                                     (71 chars)

## Full description (4000 char limit)

Take the harbourmaster's post at a small port in a cold northern archipelago.
Five souls, two sheds, and one tide.

Fell timber, saw it into planks, lay rope, weave sailcloth, forge tools. Post
your handful of workers where they will do the most good, and move them again
when the wind changes. Every shed runs at the rate of its scarcest input, so a
sawmill without timber is just a building.

Sell on your own quay and watch the price fall — dump two hundred rope in an
afternoon and rope is worthless for days. Or load your own hull and send it to
a port that actually wants the cargo: the shipyards at Ostmark, the garrison at
Greyhaven, or the long haul out to the Reaches where nobody asks what is in the
hold.

The sea has opinions. A north-easterly closes the quay. Rot takes the retting
pools. The sound freezes every winter, and you can see it coming thirty days
out — so put something by. Every event warns you first, and tells you the truth
about how long it will last.

And if you want it, there is a darker trade. Build a still and free traders
start calling. Contraband pays what nothing else will, and the Revenue starts
watching. What you keep in plain sight can be taken; what you hide costs you
the hands that hide it. You can run an entirely honest port and still win.

Finish the Saltwind Light and the port is made.

WHAT THIS GAME WILL NEVER DO

• No adverts. Not banners, not video, not "watch this to continue".
• No in-app purchases. There is nothing to buy, at any price.
• No energy meter, no lives, no daily reward loop.
• No paid speed-ups. Fast-forward to 4x is a free button.
• No account, no sign-in, no data collection of any kind.
• Fully offline. It never touches the network.

Time away is uncapped — your port keeps working while the app is closed, and
the only thing that limits it is storage you built yourself. Nothing is ever
taken from you while you are not looking.

The difficulty is in deciding where the hands go, not in waiting.

## Category
    Games → Simulation
    (Strategy is a reasonable alternative; Simulation fits the loop better.)

## Tags / keywords
    resource management, trading, age of sail, offline, idle, simulation,
    no ads, city builder, strategy, premium

## Content rating questionnaire — the honest answers
    Violence:            none
    Sexuality:           none
    Language:            none
    Controlled substance: REFERENCES ONLY — the game has a distillery producing
                         "spirits" and a smuggling mechanic. Declare it. It is
                         a trade good in an 18th-century setting with no
                         depiction of consumption, but do not omit it; an
                         inaccurate questionnaire is grounds for removal.
    Gambling:            none. Simulated or otherwise.
    User interaction:    none. No chat, no sharing, no user content.

Expected outcome: PEGI 7 / ESRB Everyone 10+, roughly.

## Data safety form
    Does your app collect or share any user data?   NO
    Is all user data encrypted in transit?          N/A — no data leaves device
    Do you provide a way to delete data?            N/A — uninstalling removes
                                                    the local save

## Privacy policy URL
    https://manicalmonocle.github.io/PortsAhoy/privacy.html

## Ads declaration
    Does your app contain ads?   NO

## Assets in this folder
    play-icon-512.png            512x512 app icon
    play-feature-1024x500.png    1024x500 feature graphic
    screenshots/*.png            five 1080x1920 phone screenshots

Screenshots are rendered from the real game by `test/screenshots_test.dart`.
Regenerate after any UI change:

    flutter test test/screenshots_test.dart --update-goldens
    cp test/store/*.png store/screenshots/
