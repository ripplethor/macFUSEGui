cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.21"
  sha256 arm: "41b6abe34af58373e162b0282cce1f3fb9a693873cf8be8942e505d464c6aceb", intel: "933a4108ed1f1c71bdf45c166bf8545fbe14284afbb275882307313f891c75bc"

  url "https://github.com/ripplethor/macfuseGUI/releases/download/v#{version}/macfuseGui-v#{version}-macos-#{arch}.dmg",
      verified: "github.com/ripplethor/macfuseGUI/"
  name "macfuseGui"
  desc "SSHFS GUI for macOS using macFUSE"
  homepage "https://www.macfusegui.app/"

  depends_on macos: ">= :ventura"

  app "macFUSEGui.app"

  caveats <<~EOS
    This app is unsigned and not notarized.
    If macOS blocks launch, run:
      xattr -dr com.apple.quarantine "/Applications/macFUSEGui.app"
  EOS
end
