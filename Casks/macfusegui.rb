cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.16"
  sha256 arm: "058032fe18bc3aaebe32b1e1e6c520d37261953265560b9beafbbf5f26a636f8", intel: "79eeeca3fa5bcd61485b3d5889f0cf8b0d2ff18c70fa01aac769f94da7871ceb"

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
