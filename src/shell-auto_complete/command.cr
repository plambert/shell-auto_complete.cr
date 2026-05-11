module Shell::AutoComplete
  abstract class Command
    def run
      raise NotRunnable.new("#{self.class} must override #run")
    end
  end
end
