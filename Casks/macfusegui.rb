cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.33"
  sha256 arm: "2b374c2141a43726539f6ac9d2cdbfa578c430354d65b7c07039d87345d57fab", intel: "213b19cac49e397cf72d530bf62c90c4b23c9221e5a73b6ff6dd385846d72751"

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
