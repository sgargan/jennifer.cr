require "./expression_builder"
require "./aggregations"
require "./ordering"
require "./joining"
require "./executables"

module Jennifer
  module QueryBuilder
    class Query
      extend Ifrit
      include Aggregations
      include Ordering
      include Joining
      include Executables

      {% for method in %i(having table limit offset raw_select table_aliases from lock joins order relations groups lock unions distinct) %}
        def _{{method.id}}
          @{{method.id}}
        end

        def _{{method.id}}!
          @{{method.id}}.not_nil!
        end
      {% end %}

      @having : Condition | LogicOperator?
      @limit : Int32?
      @table : String = ""
      @distinct : Bool = false
      @offset : Int32?
      @raw_select : String?
      @from : String | Query?
      @lock : String | Bool?
      @joins : Array(Join)?
      @unions : Array(Query)?

      def_clone

      property tree : Condition | LogicOperator?

      def initialize
        @do_nothing = false
        @expression = ExpressionBuilder.new(@table)
        @order = {} of Criteria => String
        @relations = [] of String
        @groups = [] of Criteria
        @relation_used = false
        @table_aliases = {} of String => String
        @select_fields = [] of Criteria
      end

      def initialize(@table)
        initialize
      end

      def expression_builder
        @expression
      end

      def _select_fields : Array(Criteria)
        if @select_fields.empty?
          b = [] of Criteria
          b << @expression.star
          b
        else
          @select_fields
        end
      end

      protected def add_union(value : Query)
        @unions ||= [] of Query
        @unions.not_nil! << value
      end

      def self.build(*opts)
        q = new(*opts)
        q.expression_builder.query = q
        q
      end

      def self.[](*opts)
        build(*opts)
      end

      def to_sql
        Adapter::SqlGenerator.select(self)
      end

      def as_sql
        @tree ? @tree.not_nil!.as_sql : ""
      end

      def sql_args
        if @tree
          @tree.not_nil!.sql_args
        else
          [] of DB::Any
        end
      end

      def sql_args_count
        @tree ? @tree.not_nil!.sql_args_count : 0
      end

      def select_args
        args = [] of DB::Any
        args.concat(@from.as(Query).select_args) if @from.is_a?(Query)
        _joins!.each { |join| args.concat(join.sql_args) } if @joins
        args.concat(@tree.not_nil!.sql_args) if @tree
        args.concat(@having.not_nil!.sql_args) if @having
        args
      end

      def select_args_count
        count = 0
        count += @from.as(Query).select_args_count if @from.is_a?(Query)
        _joins!.each { |join| count += join.sql_args_count } if @joins
        count += @tree.not_nil!.sql_args_count if @tree
        count += @having.not_nil!.sql_args_count if @having
        count
      end

      def with_relation!
        @relation_used = true
      end

      def with_relation?
        @relation_used
      end

      def empty?
        @tree.nil? && @limit.nil? && @offset.nil? &&
          (@joins.nil? || @joins.not_nil!.empty?) && @order.empty? && @relations.empty?
      end

      def exec(&block)
        with self yield
        self
      end

      def where(&block)
        other = (with @expression yield)
        set_tree(other)
        self
      end

      def select(raw_sql : String)
        @raw_select = raw_sql
        self
      end

      def select(field : Criteria)
        @select_fields << field
        field.as(RawSql).without_brackets if field.is_a?(RawSql)
        self
      end

      def select(field_name : Symbol)
        @select_fields << @expression.c(field_name.to_s)
        self
      end

      def select(*fields : Symbol)
        fields.each { |f| @select_fields << @expression.c(f.to_s) }
        self
      end

      def select(fields : Array(Criteria))
        fields.each do |f|
          @select_fields << f
          f.as(RawSql).without_brackets if f.is_a?(RawSql)
        end
        self
      end

      def select(&block)
        fields = with @expression yield
        fields.each do |f|
          f.as(RawSql).without_brackets if f.is_a?(RawSql)
        end
        @select_fields.concat(fields)
        self
      end

      def from(_from : String | Query)
        @from = _from
        self
      end

      def none
        @do_nothing = true
        self
      end

      def having
        other = with @expression yield
        if @having.nil?
          @having = other
        else
          @having = @having.not_nil! & other
        end
        self
      end

      def union(query)
        add_union(query)
        self
      end

      def distinct
        @distinct = true
        self
      end

      # Groups by given column realizes it as is
      def group(column : String)
        @groups << @expression.sql(column, false)
        self
      end

      # Groups by given column realizes it as current table's field
      def group(column : Symbol)
        @groups << @expression.c(column.to_s)
        self
      end

      # Groups by given columns realizes them as are
      def group(*columns : String)
        columns.each { |c| @groups << @expression.sql(c, false) }
        self
      end

      # Groups by given columns realizes them as current table's ones
      def group(*columns : Symbol)
        columns.each { |c| @groups << @expression.c(c.to_s) }
        self
      end

      def group(column : Criteria)
        column.as(RawSql).without_brackets if column.is_a?(RawSql)
        @groups << column
        self
      end

      def group(&block)
        fields = with @expression yield
        fields.each { |f| f.as(RawSql).without_brackets if f.is_a?(RawSql) }
        @groups.concat(fields)
        self
      end

      def limit(count : Int32)
        @limit = count
        self
      end

      def offset(count : Int32)
        @offset = count
        self
      end

      def lock(type : String | Bool = true)
        @lock = type
        self
      end

      def to_s
        to_sql
      end

      def set_tree(other : LogicOperator | Condition)
        @tree = if !@tree.nil? && !other.nil?
                  @tree.as(Condition | LogicOperator) & other
                else
                  other
                end
        self
      end

      def set_tree(other : Query)
        set_tree(other.tree)
      end

      def set_tree(other : Criteria)
        set_tree(Condition.new(other))
      end

      def set_tree(other : Nil)
        raise ArgumentError.new("Condition tree couldn't be nil")
      end

      #
      # private methods
      #

      private def _groups(name : String)
        @group[name] ||= [] of String
      end
    end
  end
end
