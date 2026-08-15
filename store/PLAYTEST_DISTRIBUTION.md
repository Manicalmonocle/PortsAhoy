# Getting the game to testers without paying anything

## The short version

Send them the **web build**. It sidesteps Play Protect completely, because
nothing is being installed from an unknown source — it is just a web page.
It also reaches iPhone testers, who you cannot reach at all with an APK.

`~/ports-ahoy-web.zip` (14 MB) is ready to upload. It is built with a relative
base href, so it works whether it is served from a domain root or a subpath.

## Three free hosts, in order of least effort

### 1. itch.io — best for playtesting
Free, no card. Create the project, set **Kind of project: HTML**, upload the
zip, tick *"This file will be played in the browser"*.

Why it suits this: you can set the project to **Restricted** and hand out a
secret URL or per-tester keys, testers can leave comments, and you get devlogs
for build notes. It is where playtesting happens for small games.

Also upload `ports-ahoy.apk` alongside as a downloadable, for anyone who wants
the native build.

### 2. Netlify Drop — fastest possible
Go to app.netlify.com/drop and drag the **unzipped folder** onto the page. You
get an HTTPS URL in about ten seconds. An account keeps it permanently; without
one it is temporary.

### 3. GitHub Pages — best if you want it in version control anyway
Needs a repo. The project is not one yet. If you set that up, note that Pages
serves from `username.github.io/reponame/`, which is exactly the subpath case
the relative base href already handles.

## It installs like an app

The build is a PWA. On Android Chrome, testers get an "Add to Home Screen"
prompt; on iOS Safari it is Share → Add to Home Screen. After that it launches
fullscreen with the ship icon and no browser chrome, and works offline — the
service worker caches everything on first load.

For most testers this is indistinguishable from an installed app, and it
updates the moment you redeploy, with no reinstall.

## What you give up versus native

* Slightly slower first load (14 MB, cached afterwards).
* Rendering is a little heavier on old phones.
* Saves live in browser storage. Clearing site data wipes a save — worth
  telling testers, since it is the one way they can lose progress.

None of that matters much for finding bugs, which is the job right now.

## If a tester insists on the APK

They will hit "Unsafe app blocked". It is Play Protect doing its job — it
cannot distinguish your build from a malicious one, because it has never seen
this signing key. They can proceed via **More details → Install anyway**.

Tell them to expect it. Otherwise a scary warning reads as "the developer
shipped me something broken".

## When the $25 is worth paying

When you want the 12-tester clock running, since **only closed testing counts**
toward production access and it needs 12 testers opted in for 14 unbroken days.
That is the long pole for shipping — but it is not the long pole for *finding
bugs*, which is what this stage is for. Web first, Play when you are close.
