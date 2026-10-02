cask "utv" do
  version "2026.10" # This will be automatically updated by GitHub Actions
  sha256 "6163952df1b178bfa84306e4284b29537f55d539c8e757e5c2616f7494094ed6"

  url "https://github.com/OpenUTV/utv/releases/download/#{version}/UTV-#{version}-macOS-arm64.zip"
  name "UTV"
  desc "Lightweight and distributable framecycler and sequence viewer"
  homepage "https://github.com/OpenUTV/utv"

  app "UTV.app"

  depends_on macos: ">= :sequoia"

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
