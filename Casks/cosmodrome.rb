cask "cosmodrome" do
  version "1.2.0"
  sha256 :no_check # Update with actual SHA256 after first release

  url "https://github.com/rinaldofesta/cosmodrome/releases/download/v#{version}/Cosmodrome.dmg"
  name "Cosmodrome"
  desc "Native macOS terminal for developers running multiple AI agents in parallel"
  homepage "https://github.com/rinaldofesta/cosmodrome"

  depends_on macos: ">= :sonoma"

  app "Cosmodrome.app"

  binary "#{appdir}/Cosmodrome.app/Contents/MacOS/cosmoctl", target: "cosmoctl"

  zap trash: [
    "~/Library/Application Support/Cosmodrome",
    "~/Library/Preferences/com.cosmodrome.terminal.plist",
  ]
end
