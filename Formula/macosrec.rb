class Macosrec < Formula
  desc "Take screenshots or videos of macOS windows from the command line."
  homepage "https://github.com/xenodium/macosrec"
  url "https://github.com/xenodium/macosrec/archive/refs/tags/macosrec-0.1.0.tar.gz"
  sha256 "289dd3210f60ae4ae5db9bd8a36b69d990f8a50cff8e1234fba7e049134eac44"
  license "GPL-3.0-or-later"

  depends_on :macos
  depends_on xcode: ["14.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/macosrec"
  end

  test do
    system "#{bin}/macosrec", "--help"
  end
end
