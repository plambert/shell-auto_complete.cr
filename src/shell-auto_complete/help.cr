module Shell::AutoComplete
  module Help
    alias FlagRow = NamedTuple(canonical: String, aliases: Array(String), short: String?, description: String)
    alias SubcommandRow = NamedTuple(name: String, description: String)
    alias PositionalRow = NamedTuple(name: String, description: String, variadic: Bool)

    def self.render(command_name : String,
                    description : String,
                    flags : Array(FlagRow),
                    subcommands : Array(SubcommandRow) = [] of SubcommandRow,
                    positionals : Array(PositionalRow) = [] of PositionalRow,
                    header : String? = nil,
                    footer : String? = nil,
                    usage : String? = nil,
                    qualified_name : String? = nil) : String
      String.build do |str|
        if header
          str << header << "\n\n"
        end
        str << "Usage: " << (usage || default_usage(qualified_name || command_name, flags, subcommands, positionals)) << "\n"
        str << "\n"
        str << description << "\n"
        unless flags.empty?
          str << "\n"
          str << "Options:\n"
          flags.each do |flag_row|
            forms = [flag_row[:canonical]] + flag_row[:aliases]
            short = flag_row[:short]
            forms << short.as(String) if short
            str << "  " << forms.join(", ").ljust(30) << "  " << flag_row[:description] << "\n"
          end
        end
        unless subcommands.empty?
          str << "\n"
          str << "Subcommands:\n"
          subcommands.each do |sub|
            str << "  " << sub[:name].ljust(20) << "  " << sub[:description] << "\n"
          end
        end
        unless positionals.empty?
          str << "\n"
          str << "Positional arguments:\n"
          positionals.each do |pos|
            label = pos[:variadic] ? "<#{pos[:name]}...>" : "<#{pos[:name]}>"
            str << "  " << label.ljust(20) << "  " << pos[:description] << "\n"
          end
        end
        if footer
          str << "\n" << footer << "\n"
        end
      end
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
