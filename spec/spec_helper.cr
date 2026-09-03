require "spec"
require "../src/shell-auto_complete"

# Scratch directory for the specs that write a real file and shell out to the
# compiler: the compile-fragment helpers, and the ones that build and run a
# binary. They used to write into the project root, which put transient
# `sac-*.cr` / `sac-*.bin` files in `git status` for the length of a run, where
# a `git add -A` would pick them up. It sits one level under the root so a
# fragment's `require "../src/shell-auto_complete"` still resolves, and it is
# gitignored.
SPEC_TMP_DIR = File.expand_path(File.join(__DIR__, "..", ".spec-tmp"))

def spec_tmp_dir : String
  Dir.mkdir_p(SPEC_TMP_DIR)
  SPEC_TMP_DIR
end
