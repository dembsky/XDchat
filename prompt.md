# XDchat - Build dla dystrybucji

## Problem
Aplikacja XDchat zbudowana przez Xcode nie uruchamia sie na innych Macach. Blad: "zsh: killed" - system zabija proces przez brak notaryzacji Apple.

## Co trzeba zrobic
Zbudowac aplikacje XDchat w trybie ktory pozwoli ja uruchomic na dowolnym Macu bez notaryzacji Apple:

1. Build bez code signing lub z ad-hoc signing
2. Wylaczyc hardened runtime
3. Stworzyc ZIP lub DMG do dystrybucji

## Komendy do wyprobowania

```bash
cd /Users/dembsky/Documents/XDchat

# Build bez code signing
xcodebuild -scheme XDchat -configuration Release -derivedDataPath ./build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build

# Stworz ZIP
cd ./build/Build/Products/Release
zip -r ~/Desktop/XDchat.zip XDchat.app
```

## Na docelowym Macu (laptopie)

```bash
# Rozpakuj ZIP do /Applications
# Potem:
sudo xattr -rd com.apple.quarantine /Applications/XDchat.app
sudo codesign --force --deep --sign - /Applications/XDchat.app
open /Applications/XDchat.app
```

## Alternatywa - DMG z drag & drop
Mozna tez stworzyc DMG z instalatorem drag & drop do Applications.
