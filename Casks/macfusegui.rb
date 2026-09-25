cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.37"
  sha256 arm: "79f592e4018ec9473998a74fd1860df7dd3e8ecbb223719a3b8204c1119e607e", intel: "2f8cc8bce077b04c77fa35612801d1c718b000f130fdaf52e895e7b0b6e1141e"

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
