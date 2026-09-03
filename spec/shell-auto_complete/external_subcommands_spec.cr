require "../spec_helper"
require "file_utils"

private def compile_fragment(body : String) : Process::Status
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-extsub", ".cr", dir: spec_tmp_dir)
  begin
    File.write(tmp.path, src)
    Process.run("crystal", ["build", "--no-debug", "--no-codegen", tmp.path],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close)
  ensure
    tmp.delete
  end
end

# Builds a small CLI that enables external_subcommands and has one declared
# subcommand, returning the binary path. exec cannot be exercised in-process
# (it replaces the runner), so the handoff is tested by running the binary.
private def build_ext_tool : String
  src = <<-CR
    require "../src/shell-auto_complete"
    Shell::AutoComplete.command ExtToolBuild, name: "build", description: "x" do
      def run
        puts "internal-build"
      end
    end
    Shell::AutoComplete.command ExtTool, name: "exttool", description: "x" do
      external_subcommands
      subcommand ExtToolBuild
      def run
        puts "root-run"
      end
    end
    ExtTool.dispatch(ARGV)
    CR
  # The source sits one level under the repo root so its
  # `require "../src/..."` resolves. Crystal writes the binary beside it;
  # both are cleaned up at exit.
  tmp = File.tempfile("sac-exttool", ".cr", dir: spec_tmp_dir)
  bin = tmp.path.chomp(".cr") + ".bin"
  File.write(tmp.path, src)
  status = Process.run("crystal", ["build", "--no-debug", tmp.path, "-o", bin],
    output: Process::Redirect::Close, error: Process::Redirect::Close)
  tmp.delete
  raise "fixture build failed" unless status.success?
  Spec.after_suite { File.delete?(bin) }
  bin
end

private def run_bin(bin : String, args : Array(String), path : String? = nil) : {String, String, Int32}
  stdout_io = IO::Memory.new
  stderr_io = IO::Memory.new
  env = path ? {"PATH" => path} : nil
  status = Process.run(bin, args, output: stdout_io, error: stderr_io, env: env)
  {stdout_io.to_s, stderr_io.to_s, status.exit_code}
end

describe "external_subcommands" do
  it "is a compile error on a parent:-derived command" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command ExtRoot, name: "root", description: "x" do
        def run
        end
      end
      Shell::AutoComplete.command ExtKid, name: "kid", description: "x", parent: ExtRoot do
        external_subcommands
        def run
        end
      end
      FRAGMENT
    status.success?.should be_false
  end

  it "compiles on a root command" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command ExtOk, name: "ok", description: "x" do
        external_subcommands
        def run
        end
      end
      FRAGMENT
    status.success?.should be_true
  end

  context "dispatch handoff" do
    bin = build_ext_tool

    # A temp dir on PATH holding `exttool-deploy`, which echoes its args and
    # exits 7 so both pass-through and status propagation are observable.
    ext_dir = File.tempname("sac-extpath")
    Dir.mkdir_p(ext_dir)
    helper = File.join(ext_dir, "exttool-deploy")
    File.write(helper, "#!/bin/sh\necho \"deploy: $@\"\nexit 7\n")
    File.chmod(helper, 0o755)
    path_with_helper = "#{ext_dir}:#{ENV["PATH"]}"
    Spec.after_suite { FileUtils.rm_rf(ext_dir) }

    it "runs a declared subcommand rather than looking on PATH" do
      out, _, code = run_bin(bin, ["build"], path_with_helper)
      out.should contain("internal-build")
      code.should eq(0)
    end

    it "execs the external command, passing every argument after the word" do
      out, _, code = run_bin(bin, ["deploy", "a", "b", "--json"], path_with_helper)
      out.should contain("deploy: a b --json")
      code.should eq(7)
    end

    it "raises unknown subcommand when nothing matches on PATH" do
      _, err, code = run_bin(bin, ["nope"], path_with_helper)
      err.should contain("unknown subcommand: nope")
      code.should eq(1)
    end

    it "never looks up a word containing a path separator" do
      _, err, code = run_bin(bin, ["../deploy"], path_with_helper)
      err.should contain("unknown subcommand: ../deploy")
      code.should eq(1)
    end

    it "offers declared and discovered external subcommands in completion" do
      out, _, _ = run_bin(bin, ["__complete", "1", "exttool", ""], path_with_helper)
      lines = out.lines.map(&.strip)
      lines.should contain("build")  # declared
      lines.should contain("deploy") # discovered on PATH as exttool-deploy
    end

    it "prefix-filters discovered external subcommands" do
      out, _, _ = run_bin(bin, ["__complete", "1", "exttool", "dep"], path_with_helper)
      out.lines.map(&.strip).should contain("deploy")
    end
  end

  context "search_path" do
    # A binary whose search_path is `cmds:<abs>`; `cmds` is relative and must
    # resolve against the binary's own directory, not PATH or the cwd.
    dir = File.tempname("sac-extsp")
    Dir.mkdir_p(dir)
    src = <<-CR
      require "../src/shell-auto_complete"
      Shell::AutoComplete.command SpTool, name: "sptool", description: "x" do
        external_subcommands search_path: "cmds:#{dir}/abs"
        def run
          puts "root"
        end
      end
      SpTool.dispatch(ARGV)
      CR
    tmp = File.tempfile("sac-sptool", ".cr", dir: spec_tmp_dir)
    bin = File.join(dir, "sptool")
    File.write(tmp.path, src)
    build_ok = Process.run("crystal", ["build", "--no-debug", tmp.path, "-o", bin],
      output: Process::Redirect::Close, error: Process::Redirect::Close).success?
    tmp.delete

    # Relative `cmds` sits beside the binary; `<dir>/abs` is the absolute entry.
    Dir.mkdir_p(File.join(dir, "cmds"))
    Dir.mkdir_p(File.join(dir, "abs"))
    rel_cmd = File.join(dir, "cmds", "sptool-near")
    abs_cmd = File.join(dir, "abs", "sptool-far")
    File.write(rel_cmd, "#!/bin/sh\necho \"near: $@\"\n")
    File.write(abs_cmd, "#!/bin/sh\necho \"far: $@\"\nexit 3\n")
    File.chmod(rel_cmd, 0o755)
    File.chmod(abs_cmd, 0o755)
    Spec.after_suite { FileUtils.rm_rf(dir) }

    it "builds with a search_path" do
      build_ok.should be_true
    end

    it "resolves a relative search dir against the binary's directory" do
      out, _, code = run_bin(bin, ["near", "x"])
      out.should contain("near: x")
      code.should eq(0)
    end

    it "uses an absolute search dir as-is, ignoring PATH" do
      # Run with an empty PATH to prove the lookup does not consult it.
      out, _, code = run_bin(bin, ["far"], "/nonexistent")
      out.should contain("far:")
      code.should eq(3)
    end

    it "offers external subcommands discovered across the search path" do
      out, _, _ = run_bin(bin, ["__complete", "1", "sptool", ""])
      lines = out.lines.map(&.strip)
      lines.should contain("near")
      lines.should contain("far")
    end
  end
end
