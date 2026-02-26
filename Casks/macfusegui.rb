cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.19"
  sha256 arm: "b4f7633de4541fd43a634fa06a7b621ec0f7a14b178bb7fecb8badd20a538de5", intel: "bbf04608d0ff7032ddf4db89d1809758e293899e2668a82315473333fcbc0e98"

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
