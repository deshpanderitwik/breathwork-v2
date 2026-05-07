cask "breathe" do
  version "0.1.0"
  sha256 "FILL_IN_AFTER_FIRST_RELEASE_SEE_README"

  url "https://github.com/deshpanderitwik/breathwork-v2/releases/download/v#{version}/Breathe-macos-#{version}.zip"
  name "Breathe"
  desc "Breathing metronome with rounds, as a menu bar app"
  homepage "https://github.com/deshpanderitwik/breathwork-v2"

  app "Breathe.app"

  # Bundle identifier matches Info.plist (apps/macos/Info.plist).
  zap trash: [
    "~/Library/Preferences/com.breathe.macos.plist",
  ]
end
