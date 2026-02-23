cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.9"
  sha256 arm: "9e5538cc18347c590bb29711f3db9557b5604e812cf24ad5b52b9d1c5daab499", intel: "0291dec65c4b5d108400f81871aebfb9b82cfce73245338a723f64bb6b0392cd"

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
