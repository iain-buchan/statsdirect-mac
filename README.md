# StatsDirect for Mac

A native macOS preview of StatsDirect, using the [Windows calculation engine](https://github.com/iain-buchan/statsdirect) with tabbed worksheets, analyses, reports, help and R sessions.

## Download

**[Download the latest Mac release](https://github.com/iain-buchan/statsdirect-mac/releases/latest)** — Apple Silicon, macOS 14 or later.

Expand the application ZIP and move **StatsDirect Viewer.app** to Applications. This preview is not yet Apple Developer ID signed or notarised; see the release notes for installation details. **Help → Check for Updates** finds new releases; installation is currently manual.

## Get started

Open your data with **File → Open**, or choose **Help → Example workbook**, then select a method from **Analysis**.

- Read and write Excel (`.xlsx`), CSV and R data files.
- Keep results together in an active report, with SVG charts and PDF export.
- Continue supported analyses in editable R sessions; install R through the app if needed.
- Use **Help → Learning** for biostatistics, epidemiology, practice questions and a tutor connected to your open work. **Use my ChatGPT** signs in through your browser; your account’s Codex access and usage allowance apply.

## Build

Requires an Apple Silicon Mac, Xcode command line tools, Python 3 and the .NET 10 SDK.

```sh
git clone --recurse-submodules https://github.com/iain-buchan/statsdirect-mac.git
cd statsdirect-mac
./build.sh
```

The engine is pinned to a tested Git submodule revision. Prebuilt web content is included.

## Documentation

[Data grid](Grid/README.md) · [Learning](Learn/README.md) · [Engine and updates](FullEngine/README.md) · [Verification and limitations](Tests/verification.md)
