cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.12"
  sha256 arm: "16a1826f60661c027cecf3a59052d266a146bc95f1552b4f998ac4402db7f250", intel: "f8b8cdf140bf692c6601735a18e5ff82e2fd23512e9ffa1f68b37f26b27bd139"

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
