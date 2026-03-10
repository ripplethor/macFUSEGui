cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.26"
  sha256 arm: "65a2e00d606b3cf7657aba8bda09fa4aaa9f1750f63f93e720343c1f4acd6056", intel: "30aaa1f17e256be0238bade2999f41577139ec2dd0ba457002c2be69663584ed"

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
