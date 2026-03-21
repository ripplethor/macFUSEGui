cask "macfusegui" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.29"
  sha256 arm: "551416cb347ffe3af54fbfbbacdb4d7dfa42af5469a9ca1e95bc3e6c93c00dc3", intel: "70b1cf8e3115e7b0bbf85f49058367da0f9d63dfceb58a551f068401d06146c7"

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
