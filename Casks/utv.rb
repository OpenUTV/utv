cask "utv" do
  version "2026.1" # This will be automatically updated by GitHub Actions
  sha256 "930702c9e2145050b4028bf3146e622c15f9e41a1d7587865b8032638b2eea60"

  url "https://github.com/OpenUTV/utv/releases/download/#{version}/UTV-#{version}-macOS-arm64.zip"
  name "UTV"
  desc "Lightweight and distributable framecycler and sequence viewer"
  homepage "https://github.com/OpenUTV/utv"

  app "UTV.app"

  depends_on formula: "qt"
  depends_on formula: "ffmpeg"
  depends_on formula: "openexr"
  depends_on formula: "imath"
  depends_on formula: "opencolorio"
  depends_on formula: "libraw"
  depends_on formula: "libtiff"
  depends_on formula: "libpng"
  depends_on formula: "boost"
  depends_on formula: "openimageio"
  depends_on formula: "openjpeg"
  depends_on formula: "webp"
  depends_on formula: "yaml-cpp"
  depends_on formula: "spdlog"
  depends_on formula: "icu4c"
  depends_on formula: "openjph"
  depends_on formula: "jpeg-turbo"

  zap trash: [
    "~/Library/Preferences/com.OpenUTV.UTV.plist",
    "~/Library/Saved Application State/com.OpenUTV.UTV.savedState",
  ]
end
