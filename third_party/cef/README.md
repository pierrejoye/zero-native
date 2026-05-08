# CEF Vendor Layout

Chromium mode uses CEF as the bundled engine backend. zero-native does not vendor CEF binaries in git.

CEF is currently wired for macOS builds. Linux uses the system WebKitGTK backend until a Linux CEF host is added.

Install the default macOS CEF runtime with:

```sh
zero-native cef install
```

The default installer downloads zero-native's prepared runtime from GitHub Releases. It already includes `libcef_dll_wrapper.a`, so app developers do not need CMake.

Expected macOS layout:

```text
third_party/cef/macos/
  include/cef_app.h
  Release/Chromium Embedded Framework.framework/
  Resources/
  libcef_dll_wrapper/libcef_dll_wrapper.a
```

Use a custom location with:

```sh
zero-native cef install --dir /path/to/cef
zig build run-webview -Dcef-dir=/path/to/cef
```

Advanced users can install from official CEF archives and build the wrapper locally:

```sh
zero-native cef install --source official --allow-build-tools --dir /path/to/cef
```

Core maintainers can build CEF itself from source before a prepared zero-native release exists, or when testing a new CEF branch:

```sh
tools/cef/build-from-source.sh --platform macosarm64 --cef-branch <branch> --output zig-out/cef
```

That script uses CEF's `automate-git.py`, `depot_tools`, CMake, and Xcode Command Line Tools to produce the same `zero-native-cef-<version>-<platform>.tar.gz` asset uploaded by the CEF runtime release workflow. This is a maintainer path only; app developers should use `zero-native cef install`.

Verify the layout before building with:

```sh
zero-native doctor --manifest app.zon --cef-dir /path/to/cef
```

For local development, the build can opt into installing CEF automatically:

```sh
zig build run-webview -Dcef-auto-install=true
```

Normally Chromium is selected in `app.zon` with `.web_engine = "chromium"` and `.cef.dir`. The `-Dweb-engine`, `--web-engine`, `-Dcef-dir`, and `--cef-dir` flags are one-off overrides.

System WebView mode does not require this directory.
