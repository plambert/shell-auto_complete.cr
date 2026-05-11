module Shell::AutoComplete
  module Help
    alias FlagRow = NamedTuple(canonical: String, aliases: Array(String), short: String?, description: String)

    def self.render(command_name : String,
                    description : String,
                    flags : Array(FlagRow),
                    header : String? = nil,
                    footer : String? = nil,
                    usage : String? = nil) : String
      String.build do |str|
        if header
          str << header << "\n\n"
        end
        str << "Usage: " << (usage || default_usage(command_name, flags)) << "\n"
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
        if footer
          str << "\n" << footer << "\n"
        end
      end
    end

    private def self.default_usage(name : String, flags : Array(FlagRow)) : String
      parts = [name]
      parts << "[options]" unless flags.empty?
      parts.join(" ")
    end
  end
end
