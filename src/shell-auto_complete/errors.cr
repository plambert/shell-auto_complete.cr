module Shell::AutoComplete
  class Error < Exception
  end

  class NotRunnable < Error
  end

  class ParseError < Error
  end
end
