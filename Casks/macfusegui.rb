cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.7"
  sha256 arm: "0ebe6c956b5ad7034fa124db4abb82e7010e900290d04a236d96f1327cdb906e", intel: "57846266d40df4f7326879e4cbf6763501e2f56e7c7a529775057a9610d027ce"

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
