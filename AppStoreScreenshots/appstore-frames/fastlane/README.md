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

### ios background

```sh
[bundle exec] fastlane ios background
```

Create background.png (iPhone) and background-ipad.png that frameit puts behind the device: near-black green gradient with a WhatsApp-green glow and a pink glow (the app theme). Options: top:#17201B bottom:#0E1411 glow:37,211,102 glow2:255,95,162

### ios frame

```sh
[bundle exec] fastlane ios frame
```

Frame screenshots: device bezel + background + caption (see screenshots/Framefile.json and <locale>/title.strings)

### ios export

```sh
[bundle exec] fastlane ios export
```

Resize framed images to exact App Store sizes without alpha, one folder per App Store Connect slot: output/<locale>/iphone-6.9, iphone-6.3 (the required iPhone size) and ipad-13. Options: size:6.9|6.3|6.1 (only that iPhone size) mode:pad|crop|stretch bg:0x0e1411

### ios all

```sh
[bundle exec] fastlane ios all
```

Background -> frame -> export in one go. Options: size:6.9|6.3|6.1 mode:pad|crop|stretch bg:0x0e1411

### ios upload

```sh
[bundle exec] fastlane ios upload
```

Upload output/<locale>/<device>/ screenshots to App Store Connect (needs an Appfile and App Store Connect credentials)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
