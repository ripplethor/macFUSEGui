cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.18"
  sha256 arm: "f99aaf686bf8f85736bdc0442b2502319d3e47bb8586a9c7d14514b6c37f7d3d", intel: "ece2fc39cbde37082186e1790d4829930c734e9b058d84a9ead96cfb12295f7e"

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
