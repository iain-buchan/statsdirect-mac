# Verification — full headless engine, 23 September 2026

The updated application was built, launched and exercised on this Apple Silicon Mac. Code-signature verification passed for the local app bundle.

## Full engine

- Compiles the complete numerical/Builtins calculation source with the platform exclusions documented in FullEngine/README.md.
- Loads 284 original operation definitions.
- Original unmodified OperationsTester: paired t test passes all 15 specified outputs, exact sign passes all 11; one empty test is skipped. This checkout has no other populated operation tests.
- All 871 vendored source and asset files match the hashes recorded from upstream commit c56f888bd95604f9d656e90ad0236493a96f2ae7.
- The original C#/VB script engine compiles the paired operation's expression during execution.

## Application bridge

Tests/test_engine.py invokes a native test driver that loads the same hostfxr library and managed engine as the app. The driver avoids Apple's protected system Python process, which cannot host CoreCLR on this Mac.

- The live operation output agrees with all ten numerical fixture values and the formatted power.
- The engine's original HTML renderer produces the title, mean, confidence limits, P value and power expected in the help example.
- Swapping before/after reverses the mean, confidence interval and t statistic while preserving two-sided P.
- Doubling units doubles location/spread outputs while preserving t/P.
- Incomplete pairs are removed pairwise.
- Constant differences, insufficient usable pairs and invalid confidence levels fail explicitly.
- Editing the data changes the calculated report.

## Native UI

Using the application's native menu, Analysis → Parametric methods → Paired t test — PEFR example created Report 1. It displayed the original engine HTML: mean 56.111111, CI 29.842662 to 82.37956, t 4.925774, two-sided P 0.0012 at the engine's display precision, and power 98.98%.

Method help opened the original paired t topic in a separate tab, retaining the data and report tabs. Editing the first before value from 312 to 332 and pressing ⌘T created Report 2 with mean 58.333333, t 5.556956 and power 99.78%. Returning to Report 1 confirmed its original values were unchanged. The data value was restored to 312, and Report 1 was left selected.

## Limits

This verifies the paired viewer path and the two populated upstream tests. It does not establish coverage of every built procedure. Full chart rendering, external R integration, Office/RTF export, printing fidelity and notarization are not verified by this update. The optional agreement outputs are checked by the upstream paired test, but agreement rendering is off in the viewer.
