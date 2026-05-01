cask "utv" do
  version "2026.1" # This will be automatically updated by GitHub Actions
  sha256 "930702c9e2145050b4028bf3146e622c15f9e41a1d7587865b8032638b2eea60"

  url "https://github.com/OpenUTV/utv/releases/download/#{version}/UTV-#{version}-macOS-arm64.zip"
  name "UTV"
  desc "Lightweight and distributable framecycler and sequence viewer"
  homepage "https://github.com/OpenUTV/utv"

  app "UTV.app"

  zap trash: [
    "~/Library/Preferences/com.OpenUTV.UTV.plist",
    "~/Library/Saved Application State/com.OpenUTV.UTV.savedState",
  ]
end
