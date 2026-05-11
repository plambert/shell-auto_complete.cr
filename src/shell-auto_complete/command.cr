module Shell::AutoComplete
  abstract class Command
    macro inherited
      def self.command_name : String
        {% ann = @type.annotation(::Shell::AutoComplete::CommandDef) %}
        {% if ann && ann[:name] %}
          {{ ann[:name] }}
        {% else %}
          File.basename(PROGRAM_NAME)
        {% end %}
      end
    end

    def run
      raise NotRunnable.new("#{self.class} must override #run")
    end
  end
end
