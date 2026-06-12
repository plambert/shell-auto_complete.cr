module Shell::AutoComplete
  abstract class Command
    # Declares a group of value-taking long options whose occurrences are
    # delivered, in command-line order, to the block — for rsync/tar-style
    # tagged rule lists where interleaving between spellings is the semantics
    # (`--include a --exclude b --include c` means exactly that sequence).
    #
    # ```
    # ordered_flag_group "Filter rules (applied in command-line order)",
    #   {"--include" => "PATTERN: include matching files",
    #    "--exclude" => "PATTERN: exclude matching files"} do |key, value|
    #   @rules << {key, value} # key arrives with "--" stripped
    # end
    # ```
    #
    # The block runs at parse time on the fresh instance, once per occurrence,
    # in argv order — it should record into properties and do nothing else.
    # An `ArgumentError` raised from the block converts to a clean
    # `ParseError` carrying the matched spelling, giving these flags
    # parse-time per-item validation. Group spellings register in the
    # duplicate-name checker, render in help, and complete like any flag.
    macro ordered_flag_group(description, members, &block)
      {%
        raise "ordered_flag_group description must be a string literal" unless description.is_a?(StringLiteral)
        raise "ordered_flag_group members must be a hash literal of \"--spelling\" => \"description\"" unless members.is_a?(HashLiteral)
        raise "ordered_flag_group requires a block taking |key, value|" if block.is_a?(Nop)
        raise "ordered_flag_group block must take exactly two arguments (key, value); got #{block.args.size}" unless block.args.size == 2

        spellings = [] of StringLiteral
        member_descriptions = [] of StringLiteral
        members.keys.each do |member_key|
          raise "ordered_flag_group member #{member_key} must be a string literal" unless member_key.is_a?(StringLiteral)
          raw = member_key.id.stringify
          unless raw.starts_with?("--") && raw.size > 2
            raise "ordered_flag_group members must be long options (\"--name\"); got #{member_key}"
          end
          member_description = members[member_key]
          raise "ordered_flag_group description for #{member_key} must be a string literal" unless member_description.is_a?(StringLiteral)
          spellings << member_key
          member_descriptions << member_description
        end
        raise "ordered_flag_group needs at least one member" if spellings.empty?

        # Reserved-name check, mirroring the flag macro.
        if @type.has_constant?("SHELL_COMPLETION_FLAG")
          completion_reserved = @type.constant("SHELL_COMPLETION_FLAG")
        else
          completion_reserved = "--shell-completion"
        end
        reserved = ["--help", "-h", "--all-help", completion_reserved]
        spellings.each do |spelling|
          raise "#{spelling.id} is a reserved flag name" if reserved.includes?(spelling.id.stringify)
        end

        # Duplicate-name registry (issue #10): group spellings participate in
        # the same collision checks as flag declarations. Groups cannot be
        # overridden, so collisions are always errors.
        group_index = @type.methods.select { |meth| meth.annotation(::Shell::AutoComplete::OrderedFlagGroupDef) }.size
        handler_name = "__ordered_flag_group_handler_#{group_index}__"
        reg_names = @type.constant("FLAG_REGISTRY_NAMES")
        reg_owners = @type.constant("FLAG_REGISTRY_OWNERS")
        spellings.each do |spelling|
          spelling_str = spelling.id.stringify
          (0...reg_names.size).each do |reg_idx|
            if reg_names[reg_idx] == spelling_str
              raise "duplicate flag name #{spelling_str.id} on #{@type}: already declared by flag `#{reg_owners[reg_idx].id}`"
            end
          end
          reg_names << spelling_str
          reg_owners << handler_name
        end
      %}

      @[::Shell::AutoComplete::OrderedFlagGroupDef(
        description: {{ description }},
        spellings: {{ spellings }},
        descriptions: {{ member_descriptions }},
      )]
      def {{ handler_name.id }}({{ block.args[0] }} : ::String, {{ block.args[1] }} : ::String) : ::Nil
        {{ block.body }}
      end
    end
  end
end
