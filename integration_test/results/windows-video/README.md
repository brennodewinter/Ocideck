# Windows video evidence

`native-components-2026-11-17.json` retains the successful real WebView2
cross-origin autoplay-isolation and physical input probes from Windows Server
2022, upgraded to Microsoft's Authenticode-verified Evergreen runtime 157.
Ordinary WebViews remain blocked before and after the opt-in video plays.
Reserved keys dispatch once under opt-in, physical repeat does not duplicate
navigation, and disabling the handler restores the child's ArrowRight event.
The C++ contract tests separately cover the key-up/filter and deferral cases.

That run's public YouTube fixture returned provider error 150; it is explicitly
not a successful native YouTube playback/clip test. The follow-up uses another
public fixture and the actual parent origin in the player URL. Follow-up run
links and the exact final full quality-gate commit belong in PR #2978.

The supplemental Chromium report executes the production player literal with
fixed probe values and the valid official example video. It proves actual
playback and progress in that browser, not native Windows, clip-end enforcement
or the whole Flutter presentation flow. It contains only public test status,
not cookies, request headers or provider debug/session fields.
