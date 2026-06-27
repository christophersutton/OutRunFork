# Outreach to Tim Fraedrich (OutRun author)

Goal: get explicit permission to distribute the **Move: Feet** fork on Apple's
App Store, ideally as a **GPLv3 §7 "additional permission"** Tim adds upstream (or
grants to us). This resolves the GPLv3 ⇄ App Store conflict (the VLC issue) — see
`MOVEFEET_FORK_AUDIT.md` §1. It's the legally-safest and most respectful path.

**Contact:** timfraedrich@icloud.com (per the GPL headers). Alt: outrun@tadris.de.

---

## 1. The email (ready to send — edit names/links as needed)

**Subject:** Permission request — App Store distribution exception for an OutRun fork

Hi Tim,

I'm Chris Sutton. I've been a fan of OutRun for a long time — it's a genuinely
great, privacy-respecting workout tracker, and I was sorry to see it wind down.

I've built a fork called **Move: Feet**. It stays **fully open-source under
GPLv3** (it's a "GPLv3-or-later" work, same as OutRun), keeps all your copyright
notices and per-file license headers intact, and adds explicit attribution to you
and the original repo — in the app's Settings, in the README, and in a NOTICE file
with a dated statement of changes. It's free, with no ads or paid tiers. The main
work so far has been a modern SwiftUI rewrite plus a rebrand (new name, new icon).

I'd like to publish it on the App Store, and I want to do that *correctly*. As you
probably know, GPLv3 and Apple's App Store terms conflict (the old VLC situation):
GPLv3 §10 forbids a distributor from adding the usage restrictions Apple's terms
impose. You can distribute your own GPLv3 app because you're the copyright holder;
as a downstream fork, I can't, without your permission.

So my ask: **would you be willing to grant a GPLv3 §7 "additional permission"
allowing distribution of the OutRun code (and derivatives) via Apple's App Store?**
It's a short, one-paragraph grant, it keeps everything open-source, and you could
add it to the upstream repo so it benefits any future fork — or grant it to me
directly, whichever you prefer. I've drafted suggested wording below to make it
easy, but of course adapt it however you like.

Either way: thank you for building OutRun and open-sourcing it. Happy to share the
Move: Feet repo and answer anything.

Best,
Chris
<your links: Move: Feet repo · your email>

---

## 2. Suggested §7 additional-permission wording (for Tim to adopt)

> *Draft for Tim's consideration — he may want his own wording / counsel. The
> cleanest place for it is a short `LICENSE.exceptions` (or a note in the README)
> added by the copyright holder.*

```
Additional permission under GNU GPL version 3 section 7

As an additional permission under section 7 of the GNU General Public License
version 3, the copyright holders of OutRun grant permission to distribute this
program, and works based upon it, through Apple's App Store and other Apple
software distribution channels, and to accept and comply with the Apple App Store
Terms of Service and the Apple Licensed Application End User License Agreement to
the extent necessary to do so — notwithstanding the conditions in sections 4, 5,
6, and 10 that would otherwise prevent such distribution.

This additional permission may be propagated to, and relied upon by, downstream
recipients and forks of OutRun.
```

If Tim prefers, an even simpler email reply granting permission in plain words
(e.g. "I grant you permission to distribute Move: Feet on the App Store under the
App Store's terms; it stays GPLv3 otherwise") is also workable — save the reply.

---

## 3. If no reply (timebox ~3–4 weeks)

Proceed per the locked decision (`MOVEFEET_FORK_AUDIT.md` §7): the app is
meaningfully differentiated (new name/icon/features, so no Apple 4.1/4.3 copycat
flag) and OutRun is abandonware (low enforcement risk). Record the good-faith
outreach attempt (keep this file + the sent email) as the documented,
risk-accepted basis for shipping.
