module Shell::AutoComplete
  abstract class Command
    record FlagInfo,
      canonical : String,
      aliases : Array(String),
      short : String?,
      description : String

    macro inherited
      def self.command_name : String
        {% ann = @type.annotation(::Shell::AutoComplete::CommandDef) %}
        {% if ann && ann[:name] %}
          {{ ann[:name] }}
        {% else %}
          File.basename(PROGRAM_NAME)
        {% end %}
      end

      def self.flag_info(ivar_name : String) : ::Shell::AutoComplete::Command::FlagInfo
        \{% for ivar in @type.instance_vars %}
          \{% if fann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
            if ivar_name == \{{ivar.name.stringify}}
              return ::Shell::AutoComplete::Command::FlagInfo.new(
                canonical: \{{fann[:canonical]}},
                aliases: \{{fann[:aliases]}},
                short: \{{fann[:short]}},
                description: \{{fann[:description]}},
              )
            end
          \{% end %}
        \{% end %}
        raise "no flag named \#{ivar_name}"
      end
    end

    def run
      raise NotRunnable.new("#{self.class} must override #run")
    end
  end
end
