cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.8"
  sha256 arm: "e5011bdd556ada331a8390548c2a8d2c3c6fa83a7490c588c96bba9d751f6488", intel: "e452325ea6e65b20030c13e092478644545b6d6073ec0ab4ea738be65d800030"

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
