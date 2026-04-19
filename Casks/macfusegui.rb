cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.34"
  sha256 arm: "6a47df63e5c942007f4cb5fcd58459cb9292e68e3802e8810a2cb68111361cf9", intel: "1f37c72d63889bc4d2c5b03fbd7eadc7f0f24023e1c742b3597c48c462c1fcc0"

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
