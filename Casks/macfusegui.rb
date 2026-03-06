cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.23"
  sha256 arm: "e7c6634c54fa9dfc5b0c7ef877d303575df481b89a15e54a4f2b6f3ddf0c04aa", intel: "d89ca241d7d55f3551c5c99201771dcd404bf18ddf3aad4e7a8630a3788af0d3"

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
