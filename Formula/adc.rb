class Adc < Formula
  desc "Read-only CLI for querying App Store Connect reporting data"
  homepage "https://github.com/BunnyxStudio/app-connect-data-cli"
  url "https://github.com/BunnyxStudio/app-connect-data-cli/archive/b5fbde11ba1757c1ba26cce03e3262343867b5a6.tar.gz"
  version "0.1.0-b5fbde1"
  sha256 "46d2041d03821c36b683c0a0497e465c73bbbae2c5b0c20713c32c07a9064d69"
  license "Apache-2.0"

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
    output = shell_output("#{bin}/adc capabilities list --output json")
    assert_match "\"sales\"", output
    assert_match "\"analytics\"", output
  end
end
