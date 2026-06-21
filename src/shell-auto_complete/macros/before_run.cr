module Shell::AutoComplete
  abstract class Command
    # Registers a block to run on the parsed command instance after parsing
    # and before `run` — for setup that must happen once before the command
    # executes: resolving an inherited flag into shared state, opening a
    # connection, configuring a global, or cross-flag validation a single
    # flag's validator can't express.
    #
    # ```
    # Shell::AutoComplete.command Db, name: "db", description: "..." do
    #   flag dsn : String?, "--dsn", "Connection string"
    #   getter! pool : DB::Database
    #
    #   before_run do
    #     target = dsn || ENV["DATABASE_URL"]?
    #     raise ArgumentError.new("no --dsn and DATABASE_URL is unset") unless target
    #     @pool = DB.open(target)
    #   end
    # end
    # ```
    #
    # Hooks are collected down the class hierarchy and run parent-first, so a
    # `parent:`-derived subcommand inherits its base's hooks automatically
    # without `super`. The block runs on the instance (all properties are in
    # scope) and takes no arguments. An `ArgumentError` raised from it becomes
    # a clean `ParseError` carrying the command path, the same as a parse-time
    # failure. Hooks run during `dispatch`, only for the command whose `run`
    # executes; multiple hooks in one class run in declaration order.
    macro before_run(&block)
      {%
        raise "before_run requires a block" if block.is_a?(Nop)
        raise "before_run block takes no arguments; it runs on the command instance (got #{block.args.size})" unless block.args.empty?

        # Index across the whole ancestry so an inherited hook and a new one
        # never share a generated name (mirrors ordered_flag_group).
        hook_index = ([@type] + @type.ancestors).map(&.methods).reduce([] of Def) { |acc, meths| acc + meths }.select { |meth| meth.annotation(::Shell::AutoComplete::BeforeRunDef) }.size
        hook_name = "__before_run_hook_#{hook_index}__"
      %}

      @[::Shell::AutoComplete::BeforeRunDef]
      def {{ hook_name.id }} : ::Nil
        {{ block.body }}
        nil
      end
    end
  end
end
