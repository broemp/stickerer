fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios check

```sh
[bundle exec] fastlane ios check
```

Check the metadata files against App Store Connect's limits (offline)

### ios create_app

```sh
[bundle exec] fastlane ios create_app
```

Create the app record in App Store Connect (once). Needs FASTLANE_USER and an Apple Developer login

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload text metadata (name, subtitle, description, keywords, URLs, review notes). Does not submit

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Upload the screenshots made by AppStoreScreenshots/make-screenshots.sh (run it first)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
