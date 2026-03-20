cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.28"
  sha256 arm: "007c58ef4a9038490439c34858e6eeb3fc2d4c426d75939d69c18eb1b2a0a350", intel: "a8d53b839fe61d86dcd047aba2e1bef7f7ffca7b0464d9b41ece4f0113215522"

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
