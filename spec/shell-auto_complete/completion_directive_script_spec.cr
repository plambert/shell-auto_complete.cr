require "../spec_helper"

Shell::AutoComplete.command DirectiveScriptCli, name: "dscli", description: "x" do
  positionals paths : Array(Path), "dirs"

  def run
  end
end

private FILES = Shell::AutoComplete::Completion::Directive::FILES
private DIRS  = Shell::AutoComplete::Completion::Directive::DIRS

describe "generated completion scripts delegate path directives" do
  it "bash falls back to compgen -f/-d on the directives" do
    script = DirectiveScriptCli.completion_script(:bash)
    script.should contain(FILES)
    script.should contain(DIRS)
    script.should contain("compgen -f")
    script.should contain("compgen -d")
    script.should contain("compopt -o filenames")
  end

  it "bash reads candidates line by line so spaces/globs survive" do
    script = DirectiveScriptCli.completion_script(:bash)
    # The space-safe idiom: read one candidate per line into COMPREPLY rather
    # than `COMPREPLY=( $(compgen ...) )`, which word-splits and globs results.
    script.should contain("while IFS= read -r line")
    script.should_not contain("COMPREPLY=( $(compgen")
  end

  it "zsh delegates to _files / _files -/" do
    script = DirectiveScriptCli.completion_script(:zsh)
    script.should contain(FILES)
    script.should contain("_files")
    script.should contain("_files -/")
  end

  it "fish delegates to __fish_complete_path / __fish_complete_directories" do
    script = DirectiveScriptCli.completion_script(:fish)
    script.should contain(FILES)
    script.should contain("__fish_complete_path")
    script.should contain("__fish_complete_directories")
  end
end
