cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.24"
  sha256 arm: "4576f3ead9b4c6f0f6230ea1559403cdc993bb72d12d01420ab96883ec59fe5c", intel: "b042afe016d8f72295d2f7443dc9938a0a0c1bba805aa183f6800e12935ad9c2"

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
