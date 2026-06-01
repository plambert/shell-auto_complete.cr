require "../spec_helper"

private def compile_fragment(body : String) : Process::Status
  project_root = Path.new(__DIR__, "..", "..").normalize.to_s
  # Tempfile lives in the project root; relative require resolves from its location
  src = <<-CR
    require "./src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-union", ".cr", dir: project_root)
  begin
    File.write(tmp.path, src)
    Process.run("crystal", ["build", "--no-debug", "--no-codegen", tmp.path],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close)
  ensure
    tmp.delete
  end
end

describe "union type compile guard" do
  it "rejects a multi-type union without transform_with:" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadUnion, name: "x", description: "x" do
        flag mixed : String | Int32, "--mixed", "m"
      end
      FRAGMENT
    status.success?.should be_false
  end

  it "accepts a multi-type union with transform_with:" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command OkUnion, name: "x", description: "x" do
        flag mixed : String | Int32 | Nil, "--mixed", "m", transform_with: :custom

        def self.custom(value : String) : String | Int32
          value.to_i? || value
        end
      end
      FRAGMENT
    status.success?.should be_true
  end

  it "accepts a nullable type (T | Nil) without transform_with:" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command OkNullable, name: "x", description: "x" do
        flag value : Int32?, "--value", "v"
      end
      FRAGMENT
    status.success?.should be_true
  end
end
