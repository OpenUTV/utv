cask "utv" do
  version "2026.2" # This will be automatically updated by GitHub Actions
  sha256 "19024b756b4276fb23167175f7b2df0e3b4f57222b45ae0786be6851cb017fc9"

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
  depends_on formula: "libtiff"
  depends_on formula: "opencolorio"
  depends_on formula: "openexr"
  depends_on formula: "openimageio"
  depends_on formula: "openjpeg"
  depends_on formula: "openjph"
  depends_on formula: "qt"
  depends_on formula: "spdlog"
  depends_on formula: "webp"
  depends_on formula: "yaml-cpp"

  zap trash: [
    "~/Library/Preferences/com.OpenUTV.UTV.plist",
    "~/Library/Saved Application State/com.OpenUTV.UTV.savedState",
  ]
end
