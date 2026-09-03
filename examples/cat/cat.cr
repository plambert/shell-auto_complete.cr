require "../../src/shell-auto_complete"

Shell::AutoComplete.command CatCli, name: "cat",
  description: "Concatenate files to stdout" do
  flag number_nonblank : Bool = false, "--number-nonblank", "-b",
    "Number non-blank output lines (overrides --number)"

  flag squeeze_blank : Bool = false, "--squeeze-blank", "-s",
    "Squeeze multiple consecutive blank lines into one"

  flag number : Bool = false, "--number", "-n",
    "Number all output lines"

  flag unbuffered : Bool = false, "--unbuffered", "-u",
    "Flush output after each line"

  flag show_nonprinting : Bool = false, "--show-nonprinting", "-v",
    "Show non-printing characters with ^X / M- notation"

  # The `head -20` shape: the number is the flag. It sets the same property
  # the long form does, so `-20 --lines 5` is 5, and the value goes through
  # Int32's transform and the range check like any other value.
  flag lines : Int32? = nil, "--lines N", "Stop after N lines",
    bare_number: true, range: 1..

  positionals files : Array(Path), "Files to read (use - for stdin)"

  def run
    line_no = 0
    printed = 0
    last_was_blank = false
    limit = lines

    sources = files.empty? ? [Path.new("-")] : files

    sources.each do |path|
      io = path.to_s == "-" ? STDIN : File.open(path.to_s, "r")
      begin
        io.each_line(chomp: false) do |line|
          is_blank = line.chomp.empty?

          if squeeze_blank && is_blank && last_was_blank
            next
          end
          last_was_blank = is_blank

          rendered = show_nonprinting ? render_nonprinting(line) : line

          if number_nonblank
            if is_blank
              STDOUT.print rendered
            else
              line_no += 1
              STDOUT.printf "%6d\t", line_no
              STDOUT.print rendered
            end
          elsif number
            line_no += 1
            STDOUT.printf "%6d\t", line_no
            STDOUT.print rendered
          else
            STDOUT.print rendered
          end

          STDOUT.flush if unbuffered

          printed += 1
          return if limit && printed >= limit
        end
      ensure
        io.close unless io == STDIN
      end
    end
  end

  # Translate non-printing bytes for -v.
  private def render_nonprinting(line : String) : String
    String.build do |str|
      line.each_byte do |byte_value|
        case byte_value
        when 0x09, 0x0A # tab, newline — passthrough
          str.write_byte(byte_value)
        when 0x00..0x1F
          str << '^'
          str.write_byte((byte_value + 0x40).to_u8)
        when 0x7F
          str << "^?"
        when 0x80..0xFF
          str << "M-"
          inner = byte_value & 0x7F
          if inner < 0x20
            str << '^'
            str.write_byte((inner + 0x40).to_u8)
          elsif inner == 0x7F
            str << "^?"
          else
            str.write_byte(inner.to_u8)
          end
        else
          str.write_byte(byte_value)
        end
      end
    end
  end
end

CatCli.dispatch(ARGV)
