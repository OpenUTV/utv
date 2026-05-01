cask "utv" do
  version "2026.1" # This will be automatically updated by GitHub Actions
  sha256 "e26f757e749ebead993e2d0da70f10d178a9c09683f88c7bb6b9ddf000cfbc3c"

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
