# Tap → Token (TokenTrace demo)

**Tap a button. Watch one request cross four systems (the SwiftUI tap, the on-device model, your proxy, the Claude API) as one trace on one clock, and see what the phone decided to keep, hide and bill.**

This is the runnable companion to [**token-trace-kit**](https://github.com/rajatslakhina/token-trace-kit), a Swift 6 library for client-side tracing of hybrid on-device + cloud AI features. The app consumes the library as a remote Swift package resolved from its GitHub release (`upToNextMajorVersion` from 1.0.0). It contains no tracing logic of its own, only the configuration an app is supposed to own: the privacy policy, the sampling rule and the price table.

> **No screenshots.** This app has not been run on a Simulator yet (see *Verification* for why). Nothing on this page describes an image that doesn't exist.

## Why this matters

When an AI feature fails, it usually doesn't throw. The on-device model refuses, or the device can't run it, and the request quietly goes to the cloud. The user waits longer, you pay for tokens, and nothing in your error dashboard moves. To see that, you need the client spans and the server spans in **one** trace, and the phone makes that hard:

- its clock is seconds off, so the proxy's span appears **before** the tap that caused it;
- a 5% head sampler throws away 95% of exactly these traces;
- the attribute everyone adds while debugging is the prompt.

The demo makes each of those visible, then shows the library fixing it.

## What to try

| Do this | You'll see |
|---|---|
| Tap **"Summarize note"** with the defaults (on-device *refuses*, cloud *healthy*, device clock **+2.4 s**) | The trace is **kept: refusal**. A 5-span waterfall across device (blue), proxy (green) and vendor (orange), with the server spans inside their parent. `tracestate: tokentrace=k` was sent, so the server kept its half too. Cost **$0.000317** for 1,850 input / 240 output / 1,200 cached tokens at the app's illustrative prices |
| Toggle **"Show without skew correction"** | The device spans shift by 2.4 s. The proxy span now starts before the request that caused it, and *Child-before-parent violations* turns red |
| Look at **Attributes: recorded → exported** | On the root span, `debug.prompt` (a careless debug attribute holding the prompt) → **dropped**, and `enduser.id` → a keyed hash. The prompt itself only ever becomes a length bucket and a digest |
| Set on-device to **answers** and tap a few times | No cloud call. Most traces are **dropped** (healthy, outside the 5% ratio), and the cost table still counts every one |
| Cloud **429 then OK** | Two `ai.cloud.request` spans in one trace. The decision card lists both `traceparent` headers: the same trace id, two different parent ids |
| Cloud **slow** | The keep reasons gain **slow** (over the 2.5 s SLO), next to *refusal* with the default on-device setting |
| Cloud **fails** | Kept as **error**. Under `ai.cloud.request` in the attributes section, `app.error.message` goes from `upstream 500 for jane.doe@example.com, req 1` to `upstream 500 for [email], req 1` |
| Turn **Network online** off, run a few, tap **Flush** | *Last flush* reads "not acknowledged (offline or lost ack): batch kept for retry". Turn it back on and flush: *Last batch id* shows the batch that waited, and the spans arrive in the collector |
| Tap **"Summarize note"** once more, turn on **Collector loses acks**, flush, turn it off, flush again | The collector stored the batch the first time but the client never heard back. The retry carries the **same batch id**, so *duplicates deduped* goes to 1 and the spans are stored once |

Everything runs in **virtual time** with simulated tiers: no network, no model, no API key. The tracing pipeline is the real library code, and the simulated server really parses the `traceparent` header the client produced.

## How the app uses the library

```swift
@main
struct TokenTraceDemoApp: App {
    var body: some Scene {
        WindowGroup { TraceLabView(configuration: DemoTracing.configuration) }
    }
}
```

`DemoTracing.configuration` (in `Demo/DemoApp.swift`) starts from the library's default-deny `AttributePolicy.standard` and adds the app's own key. It sets the sampling rule (keep anything slower than 2.5 s or costing more than $0.005, plus 5% of healthy traces), the buffer limits and the price table. Those are product decisions, so they live in the app.

## Design decisions

**The app owns the policy, the sampling rule and the prices.** They are product decisions. A new attribute key has to be classified, a sampling ratio trades cost against coverage, and prices change. In production all three belong in remote config. The library ships defaults, and the app overrides them in one place (`DemoTracing`). *Rejected:* constants inside the library, because then a price change becomes a library release.

**Simulated tiers in virtual time, real tracing code.** The model, proxy and vendor are simulated on a manual clock, so every run is deterministic and needs no API key, no network and no Apple Intelligence-capable device. The part under test (propagation, sampling, redaction, cost, skew correction, buffering) is the real library. The simulated server really parses the `traceparent` the client produced: break propagation and its spans start their own trace. *Rejected:* calling a real model. Every run would cost money and give different timings, and the screenshots couldn't be reproduced.

**One screen, the collector's view.** The waterfall shows what a backend would hold once the buffer flushes, in server time, with device, proxy and vendor spans together. The *without correction* toggle doesn't re-run anything. It shifts the same device spans back by the offset that was applied, so the comparison is exact.

**A version range, not a path or a branch.** The app depends on `token-trace-kit` through `XCRemoteSwiftPackageReference` with `upToNextMajorVersion` from 1.0.0, the way a real consumer would. *Rejected:* a local path (it proves nothing about the published package) and `branch = main` (every clone would build whatever `main` is that day).

## How to run it

1. `git clone https://github.com/rajatslakhina/token-trace-demo-app.git`
2. Open `Demo.xcodeproj` in Xcode 16 or later. Xcode resolves `token-trace-kit` from GitHub: the requirement is `upToNextMajorVersion` from **1.0.0**, and the committed `Package.resolved` locks it to the v1.0.0 commit.
3. Select the **Demo** scheme and an iOS 17+ Simulator.
4. Build & Run (⌘R) and tap **"Summarize note"**.

## Verification

**Simulator: not run.** This run was unattended. Computer-use access to Xcode and Simulator was granted, but the screen already had someone else's work open: another Xcode workspace and a Simulator running a different app. Building and running here would have taken over that Simulator, so the run stopped before opening this project. The app builds for the iOS Simulator in CI (below), but **building is not the same as running**: nobody has watched it launch.

**CI ([Actions](https://github.com/rajatslakhina/token-trace-demo-app/actions)):** one `macos-15` job. It resolves `token-trace-kit` from GitHub against the committed `Package.resolved` (v1.0.0, commit `bcf5faf`), then builds the `Demo` scheme for `generic/platform=iOS Simulator` with code signing off. Every run of this job so far has passed, including the run on the commit that added this `Package.resolved` and README. That proves the remote package resolves and the app compiles against it. It does not prove the app launches.

**What else was checked:** the library behind it has 83 passing tests (Linux) and a green CI on both Linux and macOS, including an iOS Simulator build. Each "What to try" row above was traced through the view and the lab code by an independent reviewer, but not watched on a device.

## License

MIT
