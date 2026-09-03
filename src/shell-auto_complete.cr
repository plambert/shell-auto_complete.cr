module Shell::AutoComplete
  {% begin %}
    VERSION = {{ `shards version #{__DIR__}/..`.stringify.chomp }}

    # The version of the project being compiled — not this shard's own, which
    # is `VERSION` above. It is the last-resort fallback for `--version` when a
    # command has no `tool_version` and no `VERSION` constant in scope.
    #
    # Captured once, here, because `shards version` is a subprocess run during
    # macro expansion: two independent invocations in one compile read
    # `shard.yml` at two different moments, and disagree if the file changes in
    # between — which is exactly what happens while cutting a release. Every
    # consumer, `Command.version_string` and the specs alike, reads this
    # constant so the value cannot differ within a build.
    SHARDS_PROJECT_VERSION = {{ `shards version 2>/dev/null || echo unknown`.strip.stringify }}
  {% end %}
end

require "./shell-auto_complete/candidate"
require "./shell-auto_complete/completion_context"
require "./shell-auto_complete/completion/directive"
require "./shell-auto_complete/completion/quote"
require "./shell-auto_complete/completion/positional"
require "./shell-auto_complete/annotations"
require "./shell-auto_complete/errors"
require "./shell-auto_complete/help"
require "./shell-auto_complete/command"
require "./shell-auto_complete/completion/install_flag"
require "./shell-auto_complete/completion/bash"
require "./shell-auto_complete/completion/zsh"
require "./shell-auto_complete/completion/fish"
require "./shell-auto_complete/completion/dispatcher"
require "./shell-auto_complete/parser"
require "./shell-auto_complete/hash_flag"
require "./shell-auto_complete/macros/command"
require "./shell-auto_complete/macros/flag"
require "./shell-auto_complete/macros/positional"
require "./shell-auto_complete/macros/ordered_flag_group"
require "./shell-auto_complete/macros/common_flag"
require "./shell-auto_complete/macros/before_run"
require "./shell-auto_complete/macros/delimited_flag"
require "./shell-auto_complete/macros/external_subcommands"
require "./shell-auto_complete/macros/version"
require "./shell-auto_complete/transformers/string"
require "./shell-auto_complete/transformers/numeric"
require "./shell-auto_complete/transformers/char"
require "./shell-auto_complete/transformers/path"
require "./shell-auto_complete/transformers/stdlib"
require "./shell-auto_complete/transformers/enum"
require "./shell-auto_complete/transformers/collection"
require "./shell-auto_complete/types/positive_int"
require "./shell-auto_complete/types/non_negative_int"
require "./shell-auto_complete/types/percentage"
require "./shell-auto_complete/types/epoch_time"
require "./shell-auto_complete/types/date"
require "./shell-auto_complete/types/env_var"
require "./shell-auto_complete/types/dir_path"
require "./shell-auto_complete/types/set_delta"
