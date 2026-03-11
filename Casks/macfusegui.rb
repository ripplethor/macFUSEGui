cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.27"
  sha256 arm: "53382d4269ba2855e23155447043ec4711b51e381f41e6d001661624e95d7203", intel: "c77da39899b89af6be988a390683dac24389244c142f0c16390250fae58c12a2"

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
