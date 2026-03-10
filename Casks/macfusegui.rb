cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.26"
  sha256 arm: "055c45d06068660913c939a2548adc6b747801404a5686cfa9c2760f4a615163", intel: "ae1754a2ee2b06a588a4b6da26b6f7dce6665b86574c74afc3d2116d09d76038"

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
