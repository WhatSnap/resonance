# Signing options for Resonance (HQ-446)

2026-11-16 · research only, nothing built, signed or run. Sources are web pages and this repo; no test on a Mac.

## Answer

| | (a) ad-hoc (today) | (b) self-signed cert on Luis's Mac | (c) Developer ID + notarization |
|---|---|---|---|
| Grant survives a rebuild? | **No.** Identity is the cdhash, which changes with every build | **Yes** (same cert, same bundle id), on the Mac that holds the cert | **Yes**, on any Mac |
| Other Macs open the DMG? | Warning; user must use Settings → Open Anyway | Same warning as (a). A self-signed cert is no "identified developer" | **No warning.** Opens by double-click |
| Cost | 0 | 0 | 99 USD/year (individual or organization) |
| Setup | none | one cert, ~10 min, one line in `build-dmg.sh` | enroll, cert, hardened runtime, `notarytool`, staple. Organization also needs a D-U-N-S number |

**Personal use only: (b). Conviction Alta (85%).** It fixes the one real problem (the prompt on every rebuild) for free. Caveat: if the cert is ever lost or regenerated, the grant resets once.

**Public distribution (resonance.whatsnap.ai): (c). Conviction Alta (90%).** (b) fixes nothing for other people: their Macs see the same "unidentified developer" wall as today, and a self-signed cert does not travel. Only (c) gives other Macs a stable identity *and* a clean open. Apple's own DTS engineer says ad-hoc signing "will cause problems if you're building a Mac app that you intend to distribute widely" and recommends Developer ID for direct distribution ([Apple Developer Forums 795739](https://developer.apple.com/forums/thread/795739)).

Order that costs least: do (b) now so Luis's own rebuild loop stops prompting; move to (c) when the DMG goes public. Switching later resets the grant once, on every Mac.

## Evidence

**TCC identity.** macOS tracks code identity by its designated requirement (DR). Ad-hoc code "does not include a stable DR", so version N+1 is not recognised as version N ([Apple DTS, forums 795739](https://developer.apple.com/forums/thread/795739)). One write-up reports the stored DR for ad-hoc code is the cdhash, and that signing with a self-signed cert pins the DR to the cert's leaf hash plus identifier, so every build signed with that cert keeps the grant ([tcc cdhash trap](https://nickboy-github-io.pages.dev/posts/tcc-cdhash-trap/)). That post is a single author's experiment about Accessibility, not Apple documentation; the mechanism is the same DR matching, but see open question 1. Apple's reference on requirements is TN3127 (cited by the DTS answer; not read).

**Developer ID.** Its DR is anchored to Apple's CA plus team id and bundle id, so it is stable across builds and across Macs (my reading of how Developer ID DRs work; not quoted from a source here).

**Gatekeeper.** Since Catalina the default requires a Developer ID signature plus notarization. An un-notarized app shows an alert; the user must try to open it, then go to System Settings → Privacy & Security → Open Anyway → Open ([Apple Support 102445](https://support.apple.com/en-us/102445)). Self-signed and ad-hoc land in the same bucket. Today's `build-dmg.sh:80-88` ad-hoc signs the whole bundle, which at least avoids the "damaged" error (script comment at `build-dmg.sh:66-74`).

**Notarization requirements.** Developer ID Application cert, hardened runtime (`--options runtime`), secure timestamp (`--timestamp`), `xcrun notarytool submit --wait`, then `xcrun stapler staple`. No separate fee. The Apple page itself would not load, so this list comes from the model's summary of general knowledge ([Apple: Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)). Not verified against Apple's text.

**Cost and account.** 99 USD per membership year; companies need a D-U-N-S number matching their legal entity name; individuals need neither. D-U-N-S can take days to weeks ([Apple: Choosing a Membership](https://apple.co/303Kt8j) and third-party guides, e.g. [Buildfire](https://help.buildfire.com/how-to-enroll-in-the-apple-developer-program-)). An organization account would put "WhatSnap" as the publisher name on the signature; an individual account would show Luis's personal name.

## Open questions

1. **Not verified:** that the System Audio Recording grant (`kTCCServiceAudioCapture`) behaves like Accessibility for DR matching. The mechanism should be the same, but nobody tested it. The acceptance check in HQ-446 (two rebuilds, no second prompt) is that test, and costs nothing once (b) is in place.
2. **Does WhatSnap already have an Apple Developer account?** Unknown (HQ-446 assumption). If yes, (c) costs 0 extra and the team id is the only input. This is the question for Luis.
3. **Organization or individual enrollment** for (c)? Org shows WhatSnap as publisher but needs the D-U-N-S wait.
4. **Gap found in `build-dmg.sh`:** the generated Info.plist has only `NSMicrophoneUsageDescription` (lines ~57-62). The tap flow needs `NSAudioCaptureUsageDescription` ([routing dossier](./resonance-audio-routing.md), tap row). The HQ-429 spike worked, but a DMG build should carry the key. Belongs to HQ-433/446, not changed here.
5. **Hardened runtime under (c)** may need an audio entitlement for the tap; not checked. Test during the notarized build.
6. **Bundle id `com.resonance.app`** is generic; changing it later is another grant reset. Pick the final id before the first signed public build.
7. **Cert for (b):** where to create it without the keychain being touched by agents. Luis (or a build session with his OK) makes it in Keychain Access; this research did none of that.
