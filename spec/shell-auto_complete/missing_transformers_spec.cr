require "../spec_helper"
require "socket"

Shell::AutoComplete.command CharCli, name: "ch", description: "x" do
  flag letter : Char?, "--letter", "l"
end

Shell::AutoComplete.command FileCli, name: "fi", description: "x" do
  flag input : File?, "--input", "i"
end

Shell::AutoComplete.command DirCli, name: "di", description: "x" do
  flag path : Dir?, "--path", "p"
end

Shell::AutoComplete.command IPCli, name: "ip", description: "x" do
  flag bind : Socket::IPAddress?, "--bind", "b"
end

describe "Char transformer" do
  it "parses a single character" do
    CharCli.parse(["--letter", "x"]).letter.should eq('x')
  end

  it "raises on multi-character input" do
    expect_raises(Shell::AutoComplete::ParseError, /--letter: /) do
      CharCli.parse(["--letter", "xy"])
    end
  end
end

describe "File transformer" do
  it "returns a Path when the file exists" do
    tmp = File.tempfile("sac-file-test")
    begin
      FileCli.parse(["--input", tmp.path]).input.should eq(Path.new(tmp.path))
    ensure
      tmp.delete
    end
  end

  it "raises when the file does not exist" do
    expect_raises(Shell::AutoComplete::ParseError, /--input: .*(not.*exist|no such)/i) do
      FileCli.parse(["--input", "/nonexistent/path/xyz"])
    end
  end
end

describe "Dir transformer" do
  it "returns a Path when the directory exists" do
    DirCli.parse(["--path", "/tmp"]).path.should eq(Path.new("/tmp"))
  end

  it "raises when the directory does not exist" do
    expect_raises(Shell::AutoComplete::ParseError, /--path: .*(not.*directory|not.*exist)/i) do
      DirCli.parse(["--path", "/nonexistent/xyz"])
    end
  end
end

describe "Socket::IPAddress transformer" do
  it "parses host:port" do
    addr = IPCli.parse(["--bind", "127.0.0.1:8080"]).bind
    addr.should_not be_nil
    addr.try(&.address).should eq("127.0.0.1")
    addr.try(&.port).should eq(8080)
  end

  it "parses host-only with port 0" do
    addr = IPCli.parse(["--bind", "127.0.0.1"]).bind
    addr.should_not be_nil
    addr.try(&.port).should eq(0)
  end
end
