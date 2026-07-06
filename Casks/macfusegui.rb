cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.36"
  sha256 arm: "f16406555da867989553252f20aeb391a1f023dd21c38fb1b9d5890ae71aa278", intel: "60e948c1acea9b71670b0f156fdc3bf2fcb007e3465a3a447f40c66c79d2d55b"

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
