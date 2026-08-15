# Publishing the playtest build on GitHub Pages

The repo is initialised and committed. Nothing sensitive is in it — the
keystore lives outside the project and `android/key.properties` is gitignored,
both verified before the commit.

## 1. Create the repo on github.com

**New repository** → name it `ports-ahoy` → **Public** (Pages needs public on a
free account) → do NOT tick "add a README", the repo already has one.

## 2. Push

Copy the URL GitHub shows you, then:

    cd ~/ports_ahoy
    git remote add origin https://github.com/YOUR-USERNAME/ports-ahoy.git
    git push -u origin main

It will ask for your username and a password. **The password is a Personal
Access Token, not your GitHub password** — github.com/settings/tokens →
Generate new token (classic) → tick `repo` → copy it and paste it as the
password. GitHub stopped accepting account passwords over HTTPS in 2021.

## 3. Turn on Pages

Repo → **Settings** → **Pages** → Source: *Deploy from a branch* →
Branch: `main`, folder: **`/docs`** → Save.

A minute later the game is live at:

    https://YOUR-USERNAME.github.io/ports-ahoy/

That is the link to send testers.

## Why /docs rather than a gh-pages branch

Pages will serve from `/docs` on the main branch, which means one branch and
no build step. `docs/` holds the release web build; `.nojekyll` is in there
because Pages otherwise runs Jekyll, which silently drops files and folders
beginning with an underscore — and Flutter ships some.

The build uses `<base href="./">`, which is what makes it work at
`/ports-ahoy/` rather than only at a domain root. Do not change it to `/`.

## Shipping a new build

    flutter build web --release --base-href /PLACEHOLDER/
    rm -rf docs && mkdir docs
    cp -r build/web/* docs/
    rm -rf docs/dl
    sed -i 's|<base href="/PLACEHOLDER/">|<base href="./">|' docs/index.html
    touch docs/.nojekyll
    git add -A && git commit -m "New playtest build" && git push

Testers get it on next load — no reinstall. The service worker caches
aggressively, so tell them to pull-to-refresh if they think they are on a stale
version.

## One caveat worth telling testers

Saves live in browser storage for that origin. Clearing site data wipes a save.
It also means a save made at the LAN address will not follow them to the
github.io address — they start fresh there, once.
