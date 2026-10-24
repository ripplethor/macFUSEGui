cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.38"
  sha256 arm: "ae8be04dda654d534efb8e1b34dc443be36cf3a5f547d801dd47d3d60524da5f", intel: "26c03c54db5e8b8fd47588a5633d3e503294df8da305b239f67de44f168812ed"

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
