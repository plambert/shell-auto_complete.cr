module Shell::AutoComplete
  # Defines a named, reusable flag in a catalog, outside any command. Pull
  # selected entries into a command with `import_flags`. The flag expands in
  # the importing command's own context, so it registers in that command's
  # name registry, participates in duplicate detection and `override:`, and
  # appears in that command's help and completion exactly as a directly
  # declared flag would. Different commands can import different subsets of
  # the catalog.
  #
  # ```
  # Shell::AutoComplete.common_flag :format,
  #   format : String?, "--format", "Pretty-print with a Go template", placeholder: "TEMPLATE"
  # Shell::AutoComplete.common_flag :quiet,
  #   quiet : Bool = false, "--quiet", "-q", "Only display IDs"
  #
  # Shell::AutoComplete.command Ps, name: "ps", description: "List containers" do
  #   import_flags :format, :quiet
  #
  #   def run
  #     ...
  #   end
  # end
  # ```
  #
  # Implemented as a macro that defines a uniquely-named macro per catalog
  # entry; `import_flags` invokes those, so the catalogued declaration is
  # replayed verbatim — type, default, spellings, and options — in each
  # importing command.
  macro common_flag(name, decl, *flag_strings, **opts)
    {% raise "common_flag name must be a symbol or string literal; got #{name.class_name}" unless name.is_a?(SymbolLiteral) || name.is_a?(StringLiteral) %}

    macro __sac_common_flag_{{ name.id }}
      flag {{ decl }}, {{ flag_strings.splat }}{% unless opts.empty? %}, {{ opts.double_splat }}{% end %}
    end
  end

  abstract class Command
    # Imports named flags previously defined with
    # `Shell::AutoComplete.common_flag`, replaying each catalogued `flag`
    # declaration in this command's context. An unknown name is a compile
    # error (`undefined macro method`).
    macro import_flags(*names)
      {% for flag_name in names %}
        {% raise "import_flags names must be symbols or string literals; got #{flag_name.class_name}" unless flag_name.is_a?(SymbolLiteral) || flag_name.is_a?(StringLiteral) %}
        __sac_common_flag_{{ flag_name.id }}
      {% end %}
    end
  end
end
