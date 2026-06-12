module Shell::AutoComplete
  module Help
    alias FlagRow = NamedTuple(canonical: String, aliases: Array(String), short: String?, description: String, placeholder: String?, group: String?)
    alias SubcommandRow = NamedTuple(name: String, description: String)
    alias PositionalRow = NamedTuple(name: String, description: String, variadic: Bool)

    DEFAULT_SECTION_ORDER = [:description, :options, :subcommands, :positionals]

    # Renders a command's help text. The header and `Usage:` line always
    # lead and the footer always trails; *section_order* controls the middle
    # sections (any subset/ordering of `:description`, `:options`,
    # `:subcommands`, `:positionals`). Flags with a `group:` render under
    # their own heading after the ungrouped options, in first-appearance
    # order.
    def self.render(command_name : String,
                    description : String,
                    flags : Array(FlagRow),
                    subcommands : Array(SubcommandRow) = [] of SubcommandRow,
                    positionals : Array(PositionalRow) = [] of PositionalRow,
                    header : String? = nil,
                    footer : String? = nil,
                    usage : String? = nil,
                    qualified_name : String? = nil,
                    section_order : Array(Symbol)? = nil) : String
      order = section_order || DEFAULT_SECTION_ORDER
      String.build do |str|
        if header
          str << header << "\n\n"
        end
        str << "Usage: " << (usage || default_usage(qualified_name || command_name, flags, subcommands, positionals)) << "\n"
        order.each do |section|
          case section
          when :description
            str << "\n" << description << "\n"
          when :options
            render_options(str, flags)
          when :subcommands
            unless subcommands.empty?
              str << "\n"
              str << "Subcommands:\n"
              subcommands.each do |sub|
                str << "  " << sub[:name].ljust(20) << "  " << sub[:description] << "\n"
              end
            end
          when :positionals
            unless positionals.empty?
              str << "\n"
              str << "Positional arguments:\n"
              positionals.each do |pos|
                label = pos[:variadic] ? "<#{pos[:name]}...>" : "<#{pos[:name]}>"
                str << "  " << label.ljust(20) << "  " << pos[:description] << "\n"
              end
            end
          else
            raise ArgumentError.new("unknown help section: #{section} (expected :description, :options, :subcommands, :positionals)")
          end
        end
        if footer
          str << "\n" << footer << "\n"
        end
      end
    end

    private def self.render_options(str : String::Builder, flags : Array(FlagRow)) : Nil
      return if flags.empty?
      ungrouped = flags.select { |flag_row| flag_row[:group].nil? }
      group_names = [] of String
      flags.each do |flag_row|
        if group_name = flag_row[:group]
          group_names << group_name unless group_names.includes?(group_name)
        end
      end
      unless ungrouped.empty?
        str << "\n"
        str << "Options:\n"
        ungrouped.each { |flag_row| render_flag_row(str, flag_row) }
      end
      group_names.each do |group_name|
        str << "\n"
        str << group_name << ":\n"
        flags.each do |flag_row|
          render_flag_row(str, flag_row) if flag_row[:group] == group_name
        end
      end
    end

    private def self.render_flag_row(str : String::Builder, flag_row : FlagRow) : Nil
      forms = [flag_row[:canonical]] + flag_row[:aliases]
      short = flag_row[:short]
      forms << short.as(String) if short
      left = forms.join(", ")
      if value_placeholder = flag_row[:placeholder]
        left += " " + value_placeholder
      end
      str << "  " << left.ljust(30) << "  " << flag_row[:description] << "\n"
    end

    private def self.default_usage(name : String, flags : Array(FlagRow), subcommands : Array(SubcommandRow) = [] of SubcommandRow, positionals : Array(PositionalRow) = [] of PositionalRow) : String
      parts = [name]
      parts << "[options]" unless flags.empty?
      positionals.each do |pos|
        parts << (pos[:variadic] ? "<#{pos[:name]}...>" : "<#{pos[:name]}>")
      end
      parts << "<subcommand>" unless subcommands.empty?
      parts.join(" ")
    end
  end
end
