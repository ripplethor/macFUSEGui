cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.30"
  sha256 arm: "ff09b9cae81b63aa83c1c9dac48ccf798e9b0bc9bc4ce7985860acd3f1895965", intel: "16cb05715c1f1e0924a3353182c68d1d295c498591f7b6412d98b5303c3a46ce"

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
