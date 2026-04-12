cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.32"
  sha256 arm: "8a90ffc6e15c8877735a90d4e95cad6c8e3b7c127e1bb3edaefbafe82ecd8c7e", intel: "ba38d876b1bbb8b53c8e24814dc4aa4961f436dc999a43aac2dcf1f56d801f35"

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
