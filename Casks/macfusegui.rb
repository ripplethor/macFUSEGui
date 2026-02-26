cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.13"
  sha256 arm: "79597358f8fad1a08b67e5ea227a03cf35b6b239245efef4c8bd91fb19701b65", intel: "160e4cf9678dcf67b5bab5b1c7cf4bdad6034eb3cde63b2ba35cc473a5b97e6c"

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
