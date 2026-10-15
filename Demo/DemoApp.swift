import SwiftUI
import TokenTrace
import TokenTraceUI

/// The app owns its tracing configuration: the privacy policy, the sampling
/// rule and the price table are product decisions, so they live in the app
/// (and, in production, in remote config), not in the library.
enum DemoTracing {
    static var configuration: TracingConfiguration {
        // Start from the library's default-deny policy and classify this
        // app's own keys explicitly.
        var policy = AttributePolicy.standard
        policy.exact["app.screen"] = .allow

        return TracingConfiguration(
            limits: TraceLimits(maxOpenTraces: 32, maxSpansPerTrace: 64, traceTimeoutNanos: 60_000_000_000),
            sampling: SamplingPolicy(
                latencySLONanos: 2_500_000_000,          // keep anything slower than 2.5 s
                costThresholdPicoDollars: 5_000_000_000, // keep anything over $0.005
                healthyKeepRatio: 0.05                   // and 5% of healthy traces
            ),
            policy: policy,
            prices: LabPrices.table,                     // illustrative; real prices come from remote config
            buffer: BufferLimits(maxSpans: 500, maxBytes: 256 * 1024, maxBatchSpans: 100),
            // A real app generates this once and keeps it in the keychain.
            hashKey: Array("demo-install-secret".utf8),
            installID: "demo-install",
            applySkewCorrection: true
        )
    }
}

@main
struct TokenTraceDemoApp: App {
    var body: some Scene {
        WindowGroup {
            TraceLabView(configuration: DemoTracing.configuration)
        }
    }
}
