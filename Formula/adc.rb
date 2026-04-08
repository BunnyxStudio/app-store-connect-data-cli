class Adc < Formula
  desc "App Store Connect Data CLI for official Apple reporting data"
  homepage "https://github.com/BunnyxStudio/app-store-connect-data-cli"
  url "https://github.com/BunnyxStudio/app-store-connect-data-cli/archive/refs/tags/v0.1.7.tar.gz"
  sha256 "8fcbeaff60c491263c29d32aadc8758e25695b1db890cf98b79271f1488198aa"
  license "Apache-2.0"
  depends_on :macos

  resource "swift-argument-parser" do
    url "https://github.com/apple/swift-argument-parser/archive/refs/tags/1.5.0.tar.gz"
    sha256 "946a4cf7bdd2e4f0f8b82864c56332238ba3f0a929c6d1a15f55affdb10634e6"
  end

  def install
    resource("swift-argument-parser").stage buildpath/"vendor/swift-argument-parser"

    inreplace "Package.swift",
      '.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")',
      '.package(path: "vendor/swift-argument-parser")'

    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "adc"
    bin.install ".build/release/adc"
  end

  test do
    (testpath/".app-connect-data-cli").mkpath
    output = shell_output("#{bin}/adc capabilities list --output json")
    assert_match "\"sales\"", output
    assert_match "\"analytics\"", output
  end
end
