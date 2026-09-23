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


## R tab update

Built the native R pane and tested it with the installed R 4.6.1. File → New R Tab (⌘R) started an R session alongside data and help tabs. Running the prefilled script produced paired t = 4.9258, df = 8, P = 0.001156 and mean difference 56.11111. Additional ANOVA code entered by the user also ran in that tab.

An isolated instance of the same RPane implementation verified that a variable assigned before a deliberate R error remained available in the next run; the error was displayed and the session returned to Ready. Stop / Reset terminated a script sleeping for 60 seconds. The next run started a fresh process and confirmed the old variable was absent. The corrected layout was visually inspected in that isolated instance so the user's active script and session were not interrupted.

The first R build is running in the user's current session. The final layout and contextual Save Script label are installed for the next app launch. The full calculation engine was unchanged by this update.


## Window frame controls

Added explicit titlebar Close, Minimise, Resize / Restore and Move controls using native AppKit window operations. An isolated window using the same frame-control implementation was visually inspected. Resize enlarged the window and restored its prior size; the Close control closed the test window. The move control uses AppKit's window-drag API, and custom sizing remains available by dragging the native window edges. The main viewer retains its miniaturizable window style. Closing the main window also checks for unsaved/running R work.

The on-disk executable was replaced atomically and re-signed, preserving the running user's R process and unsaved script. The final frame controls appear on the next launch.
