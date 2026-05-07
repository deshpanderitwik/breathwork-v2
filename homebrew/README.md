# Homebrew tap

This directory holds the cask definition that ships the macOS menu bar
app via Homebrew. It exists as a skeleton in this repo for reference;
the **live tap lives in a separate `homebrew-tap` repo** so users can
install with the conventional one-liner:

```bash
brew tap deshpanderitwik/tap
brew install --cask breathe
```

## Why a separate repo?

Homebrew's short-form `brew tap user/tap` resolves to the GitHub repo
named `user/homebrew-tap`. Putting the cask here in `breathwork-v2`
would force users into the longer form `brew tap deshpanderitwik/breathwork-v2`,
which works but breaks the convention. So this directory is the
**source of truth** for the cask; the `homebrew-tap` repo is the
**delivery channel**.

## Releasing a new version

The cask points at a GitHub Release artifact in this repo. Each
release follows the same five steps:

1. **Bump version** in `apps/macos/Makefile` (or wherever the version
   string lives — currently the macOS app has no explicit version, so
   you're picking one) and tag it: `git tag v0.1.0 && git push --tags`.
2. **Build the .app bundle**:
   ```bash
   cd apps/macos && make build
   ```
3. **Zip it for distribution**:
   ```bash
   cd apps/macos/build
   ditto -c -k --keepParent Breathe.app Breathe-macos-0.1.0.zip
   shasum -a 256 Breathe-macos-0.1.0.zip   # copy this hash
   ```
   `ditto` (not `zip`) preserves resource forks and code signatures.
4. **Create the GitHub Release** with `gh`:
   ```bash
   gh release create v0.1.0 \
     apps/macos/build/Breathe-macos-0.1.0.zip \
     --title "v0.1.0" --notes "First Homebrew release"
   ```
5. **Update the cask** in this directory with the new `version` and
   `sha256`, then copy the file into the live tap repo:
   ```bash
   cp homebrew/Casks/breathe.rb ../homebrew-tap/Casks/
   cd ../homebrew-tap && git add . && git commit -m "breathe 0.1.0" && git push
   ```

After step 5, `brew install --cask breathe` (or `brew upgrade`) picks
up the new version on any machine that has the tap.

## First-time tap repo setup

You only do this once:

```bash
gh repo create deshpanderitwik/homebrew-tap --public \
  --description "Homebrew taps for my software"
git clone https://github.com/deshpanderitwik/homebrew-tap.git
mkdir -p homebrew-tap/Casks
cp breathwork-v2/homebrew/Casks/breathe.rb homebrew-tap/Casks/
cd homebrew-tap
git add . && git commit -m "Add breathe cask" && git push
```

## Gatekeeper note

The cask installs an **unsigned** `.app` (we're not paying Apple $99/yr
for a Developer ID certificate). On first launch macOS Gatekeeper will
refuse to open it with the standard "damaged" or "unverified developer"
error.

For the user, the bypass is one of:

```bash
# Either: clear the quarantine attribute Homebrew set
xattr -d com.apple.quarantine /Applications/Breathe.app

# Or: right-click the app in Finder → Open → Open anyway
```

This is the trade you make for not paying Apple. If you ever decide
to notarize the bundle, the cask installs cleanly with no Gatekeeper
prompt — but that needs an Apple Developer account.
