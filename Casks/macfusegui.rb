cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.31"
  sha256 arm: "51ee7c3f1cdf7416b552e508e132ca75f96c3ba0872c6bdd187f187b7fc4f345", intel: "24160078adaa653f7dc5d2fca339374213241fb3e69734d7bc5f6c1780b58f12"

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
