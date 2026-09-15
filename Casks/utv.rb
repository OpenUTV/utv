cask "utv" do
  version "2026.4" # This will be automatically updated by GitHub Actions
  sha256 "1b76520e00021578b02eb695c833201ee3451c22b456c02943ee6b2a38d325b1"

  url "https://github.com/OpenUTV/utv/releases/download/#{version}/UTV-#{version}-macOS-arm64.zip"
  name "UTV"
  desc "Lightweight and distributable framecycler and sequence viewer"
  homepage "https://github.com/OpenUTV/utv"

  app "UTV.app"

  depends_on formula: "boost"
  depends_on formula: "ffmpeg-full"
  depends_on formula: "icu4c"
  depends_on formula: "imath"
  depends_on formula: "jpeg-turbo"
  depends_on formula: "libpng"
  depends_on formula: "libraw"
  depends_on formula: "libspng"
  depends_on formula: "libtiff"
  depends_on formula: "opencolorio"
  depends_on formula: "openexr"
  depends_on formula: "openimageio"
  depends_on formula: "openjpeg"
  depends_on formula: "openjph"
  depends_on formula: "pyside"
  depends_on formula: "qt"
  depends_on formula: "spdlog"
  depends_on formula: "webp"
  depends_on formula: "yaml-cpp"

  zap trash: [
    "~/Library/Preferences/com.OpenUTV.UTV.plist",
    "~/Library/Saved Application State/com.OpenUTV.UTV.savedState",
  ]
end
