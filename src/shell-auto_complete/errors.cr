module Shell::AutoComplete
  class Error < Exception
  end

  class NotRunnable < Error
  end

  class ParseError < Error
    property command_path : String? = nil
  end

  class SystemExit < Error
    getter status : Int32

    def initialize(@status : Int32)
      super("exit #{@status}")
    end
  end
end
