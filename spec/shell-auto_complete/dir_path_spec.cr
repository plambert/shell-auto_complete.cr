require "../spec_helper"

# Types::DirPath fills the combination the stock path types leave open:
# directory-only completion (like Dir) with no existence check (like Path),
# for directories on another host or ones the program creates later.

private alias DirPath = Shell::AutoComplete::Types::DirPath

private DP_DIRS  = Shell::AutoComplete::Completion::Directive::DIRS
private DP_FILES = Shell::AutoComplete::Completion::Directive::FILES

Shell::AutoComplete.command DpCli, name: "dpcli", description: "x" do
  flag remote : DirPath?, "--remote", "-r", "daemon-side directory"
  flag plain : Path?, "--plain", "any path"
  flag strict : Dir?, "--strict", "must exist"

  def run
  end
end

Shell::AutoComplete.command DpPos, name: "dppos", description: "x" do
  positional target : DirPath, "directory created later"

  def run
  end
end

Shell::AutoComplete.command DpVariadic, name: "dpvar", description: "x" do
  positionals dirs : Array(DirPath), "directories"

  def run
  end
end

private def dp_complete(klass, argv)
  output = IO::Memory.new
  klass.dispatch(argv, stdout: output)
  output.to_s.lines.map(&.strip)
end

describe "Types::DirPath" do
  describe "existence" do
    it "accepts a directory that does not exist locally" do
      inst = DpCli.parse(["--remote", "/srv/media/incoming"])
      inst.remote.should eq(Path.new("/srv/media/incoming"))
    end

    it "accepts a path under a parent that does not exist" do
      inst = DpCli.parse(["--remote", "/nonexistent-root/deeper/still"])
      inst.remote.to_s.should eq("/nonexistent-root/deeper/still")
    end

    it "accepts an existing directory too" do
      inst = DpCli.parse(["--remote", __DIR__])
      inst.remote.to_s.should eq(__DIR__)
    end

    it "does not reject a path naming an existing regular file" do
      # No filesystem assertion is made at all; the type expresses shape and
      # completion, not validation.
      inst = DpCli.parse(["--remote", __FILE__])
      inst.remote.to_s.should eq(__FILE__)
    end

    it "still rejects a nonexistent directory for a Dir flag" do
      expect_raises(Shell::AutoComplete::ParseError, /--strict: directory does not exist/) do
        DpCli.parse(["--strict", "/srv/media/incoming"])
      end
    end
  end

  describe "storage" do
    it "stores the value as a Path, like Path/File/Dir flags" do
      inst = DpCli.parse(["--remote", "/srv/x"])
      inst.remote.should be_a(Path?)
      inst.remote.not_nil!.should be_a(Path)
    end

    it "stores a scalar positional as a Path" do
      DpPos.parse(["/srv/x"]).target.should eq(Path.new("/srv/x"))
    end

    it "stores a variadic positional as an Array(Path)" do
      inst = DpVariadic.parse(["/srv/a", "/srv/b"])
      inst.dirs.should eq([Path.new("/srv/a"), Path.new("/srv/b")])
    end
  end

  describe "completion" do
    it "offers directory-only completion for a flag's canonical spelling" do
      dp_complete(DpCli, ["__complete", "2", "dpcli", "--remote", ""]).should eq([DP_DIRS])
    end

    it "offers directory-only completion for a flag's short form" do
      dp_complete(DpCli, ["__complete", "2", "dpcli", "-r", ""]).should eq([DP_DIRS])
    end

    it "offers directory-only completion for a scalar positional" do
      dp_complete(DpPos, ["__complete", "1", "dppos", ""]).should eq([DP_DIRS])
    end

    it "offers directory-only completion for a variadic positional" do
      dp_complete(DpVariadic, ["__complete", "1", "dpvar", ""]).should eq([DP_DIRS])
    end

    it "differs from Path, which also offers files" do
      dp_complete(DpCli, ["__complete", "2", "dpcli", "--plain", ""]).should eq([DP_FILES])
    end

    it "matches Dir's completion" do
      dp_complete(DpCli, ["__complete", "2", "dpcli", "--strict", ""]).should eq([DP_DIRS])
    end
  end

  describe "help" do
    it "derives a DIR placeholder, like Dir" do
      text = DpCli.help
      text.should contain("--remote, -r DIR")
      text.should contain("--strict DIR")
      text.should contain("--plain PATH")
    end
  end
end
