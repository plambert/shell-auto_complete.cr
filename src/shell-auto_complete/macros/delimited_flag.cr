module Shell::AutoComplete
  abstract class Command
    # Declares a flag that captures a run of raw argv tokens into a collection,
    # ending at a delimiter token (default `--`, discarded). Every token
    # between the flag and the delimiter is appended verbatim, so flag-looking
    # tokens in the captured run are taken literally:
    #
    # ```
    # Shell::AutoComplete.command Tool, name: "tool", description: "..." do
    #   delimited_flag command : Array(String), "--command", "Command to run"
    #   flag json : Bool = false, "--json", "JSON output"
    # end
    #
    # # tool --command echo hello -- --json path
    # #   @command => ["echo", "hello"]
    # #   @json    => true          (parsing resumes after the delimiter)
    # ```
    #
    # The captured value is built by calling `.new` on the declared type and
    # appending each token with `<<(String)`, so the type only has to answer
    # those two — `Array(String)`, `Set(String)`, or any custom type. Parsing
    # resumes normally after the discarded delimiter, so a following `--json`
    # is a flag, not a positional. If the delimiter never appears, capture runs
    # to the end of argv. When the flag is absent the property holds an empty
    # `.new` (or `nil`, if the declared type is nilable).
    #
    # The delimiter is configurable with `delimiter:`. Only the space-separated
    # capture form is supported; `--command=x` is not a delimited invocation.
    #
    # `external_command: true` marks the captured value as an external command
    # for completion: inside the capture, the shell completes the first word as
    # a command name and the rest with that command's own completion (falling
    # back to file completion). It does not change parsing.
    macro delimited_flag(decl, *args, **opts)
      {%
        raise "delimited_flag #{decl} expects `name : Type` (got #{decl})" unless decl.is_a?(TypeDeclaration)

        flag_strings = [] of ::StringLiteral
        descriptions = [] of ::StringLiteral
        args.each do |arg|
          raise "delimited_flag #{decl.var}: expected string arguments, got #{arg}" unless arg.is_a?(StringLiteral)
          if arg.starts_with?("-")
            flag_strings << arg
          else
            descriptions << arg
          end
        end
        raise "delimited_flag #{decl.var} needs at least one spelling, e.g. \"--command\"" if flag_strings.empty?

        opts.keys.each do |opt_key|
          unless ["delimiter", "description", "external_command"].includes?(opt_key.stringify)
            raise "delimited_flag #{decl.var}: unknown option #{opt_key} (expected delimiter:, description:, external_command:)"
          end
        end

        delimiter = opts[:delimiter] || "--"
        raise "delimited_flag #{decl.var}: delimiter: must be a string literal" unless delimiter.is_a?(StringLiteral)

        external_command = opts[:external_command] == nil ? false : opts[:external_command]
        raise "delimited_flag #{decl.var}: external_command: must be true or false" unless external_command.is_a?(BoolLiteral)

        description = opts[:description] || (descriptions.empty? ? "" : descriptions[0])

        canonical = flag_strings[0]

        # The declared collection type. A nilable declaration defaults to nil
        # and is built on first capture; a plain type defaults to an empty
        # `.new`, so the property is always the declared collection.
        decl_type = decl.type
        nilable = decl_type.is_a?(Union) && decl_type.types.any? { |type_node| type_node.resolve == Nil }
        inner_type = nilable ? decl_type.types.find { |type_node| type_node.resolve != Nil } : decl_type
        inner_type_q = (inner_type.stringify.starts_with?("::") || inner_type.stringify.starts_with?("(")) ? inner_type : "::#{inner_type}".id

        # Register every spelling in the per-command duplicate-name registry
        # (issue #10), so a delimited flag colliding with a flag (or another
        # delimited flag) is a compile error naming both.
        reg_names = @type.constant("FLAG_REGISTRY_NAMES")
        reg_owners = @type.constant("FLAG_REGISTRY_OWNERS")
        var_name = decl.var.stringify
        flag_strings.each do |spelling|
          produced = spelling.id.stringify
          (0...reg_names.size).each do |reg_idx|
            if reg_names[reg_idx] == produced
              raise "duplicate flag name #{produced.id} on #{@type}: already declared by flag `#{reg_owners[reg_idx].id}`; add `override: true` to replace the existing flag"
            end
          end
          reg_names << produced
          reg_owners << var_name
        end
      %}

      @[::Shell::AutoComplete::DelimitedFlagDef(
        canonical: {{ canonical }},
        names: {{ flag_strings }},
        delimiter: {{ delimiter }},
        description: {{ description }},
        external_command: {{ external_command }},
      )]
      {% if nilable %}
        property {{ decl.var }} : {{ inner_type_q }}? = nil
      {% else %}
        property {{ decl.var }} : {{ inner_type_q }} = {{ inner_type_q }}.new
      {% end %}
    end
  end
end
