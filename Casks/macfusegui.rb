cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.39"
  sha256 arm: "c04dcc9a65bd43d61dffd3fed948e7e3c8d1cef5d89624092e0cc86332a9af67", intel: "142ea74f6cc587258f549f1865996793007c4debe49db1dacee42431b289ca24"

  url "https://github.com/ripplethor/macfuseGUI/releases/download/v#{version}/macfuseGui-v#{version}-macos-#{arch}.dmg",
      verified: "github.com/ripplethor/macfuseGUI/"
  name "macfuseGui"
  desc "SSHFS GUI for macOS using macFUSE"
  homepage "https://www.macfusegui.app/"

  depends_on macos: :ventura

  app "macFUSEGui.app"

  caveats <<~EOS
    This app is unsigned and not notarized.
    If macOS blocks launch, run:
      xattr -dr com.apple.quarantine "/Applications/macFUSEGui.app"
  EOS
end
