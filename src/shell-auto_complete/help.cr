module Shell::AutoComplete
  module Help
    alias FlagRow = NamedTuple(canonical: String, aliases: Array(String), short: String?, description: String)
    alias SubcommandRow = NamedTuple(name: String, description: String)

    def self.render(command_name : String,
                    description : String,
                    flags : Array(FlagRow),
                    subcommands : Array(SubcommandRow) = [] of SubcommandRow,
                    header : String? = nil,
                    footer : String? = nil,
                    usage : String? = nil) : String
      String.build do |str|
        if header
          str << header << "\n\n"
        end
        str << "Usage: " << (usage || default_usage(command_name, flags, subcommands)) << "\n"
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
        if footer
          str << "\n" << footer << "\n"
        end
      end
    end

    private def self.default_usage(name : String, flags : Array(FlagRow), subcommands : Array(SubcommandRow) = [] of SubcommandRow) : String
      parts = [name]
      parts << "[options]" unless flags.empty?
      parts << "<subcommand>" unless subcommands.empty?
      parts.join(" ")
    end
  end
end
