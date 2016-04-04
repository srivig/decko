# -*- encoding : utf-8 -*-

class Card
  module Set
    include Event
    include Trait
    mattr_accessor :modules, :traits
    @@modules = { base: [], base_format: {}, nonbase: {}, nonbase_format: {},
                  abstract: {}, abstract_format: {} }

    #  A 'Set' is a group of Cards to which 'Rules' may be applied.
    #  Sets can be as specific as a single card, as general as all cards, or
    #  anywhere in between.
    #
    #  Rules take two main forms: card rules and code rules.
    #
    #  'Card rules' are defined in card content. These are generally configured
    #  via the web interface and are thus documented at http://wagn.org/rules.
    #
    #  'Code rules' can be defined in a 'set file' within any 'Mod' (short for
    #  both 'module' and 'modification'). In accordance with Wagn's 'MoVE'
    #  architecture, there are two main kinds of code rules you can create in
    #  set file: Views, and Events.
    #  Events are associated with the Card class, and Views are associated with
    #  a Format class.
    #  You can also use set files to add or override Card and/or Format methods
    #  directly.  The majority of Card code is contained in these files.
    #
    #      (FIXME - define mod, add generator)
    #
    #  Whenever you fetch or instantiate a card, it will automatically include
    #  all the set modules defined in set files associated with sets of which it
    #  is a member.  This entails both simple model methods and 'events', which
    #  are special methods explored in greater detail below.
    #
    #  For example, say you have a Plaintext card named 'Philipp+address', and
    #  you have set files for the following sets:
    #
    #      * all cards
    #      * all Plaintext cards
    #      * all cards ending in +address
    #
    #  When you run this:
    #
    #      mycard = Card.fetch 'Philipp+address'
    #
    #  ...then mycard will include the set modules associated with each of those
    #  ets in the above order.  (The order is determined by the set pattern;
    #  ee lib/card/set_pattern.rb for more information about set_ptterns and
    #  od/core/set/all/fetch.rb for more about fetching.)
    #
    #  imilarly, whenever a Format object is instantiated for a card, it
    #  ncludes all views associated with BOTH (a) sets of which the card is a
    #  ember and (b) the current format or its ancestors.  More on defining
    #  iews below.
    #
    #
    #  In order to have a set file associated with "all cards ending in
    #  +address", you could create a file in
    #  mywagn/mod/mymod/set/right/address.rb.
    #  The recommended mechanism for doing so is running `wagn generate set
    #  modname set_pattern set_anchor`. In the current example, this
    #  would translate to `wagn generate set mymod right address`.
    #  Note that both the set_pattern and the set_anchor must correspond to the
    #  codename of a card in the database to function correctly but you can add
    #  arbitrary subdirectories to organize your code rules. The rule above
    #  for example could be saved in
    #  mywagn/mod/mymod/set/right/address/america/north/canada.rb.
    #
    #
    #  When a Card application loads, it uses these files to autogenerate a
    #  tmp_file that uses this set file to create a Card::Set::Right::Address
    #  module which itself is extended with Card::Set. A set file is 'just ruby'
    #  but is generally quite concise because Card uses its file location to
    #  autogenerate ruby module names and then uses Card::Set module to provide
    #  additional API.
    #
    #
    # View definitions
    #
    #   When you declare:
    #     view :view_name do |args|
    #       #...your code here
    #     end
    #
    #   Methods are defined on the format
    #
    #   The external api with checks:
    #     render(:viewname, args)

    module Format
      mattr_accessor :views
      @@views = {}

      def view view, *args, &block
        view = view.to_viewname.key.to_sym
        views[self] ||= {}
        view_block = views[self][view] =
                       if block_given?
                         Card::Format.extract_class_vars view, args[0]
                         block
                       else
                         alias_block view, args
                       end
        define_method "_view_#{view}", view_block
      end

      def alias_block view, args
        opts = args[0].is_a?(Hash) ? args.shift : { view: args.shift }
        opts[:mod] ||= self
        opts[:view] ||= view
        views[opts[:mod]][opts[:view]] || raise
      rescue
        raise "cannot find #{opts[:view]} view in #{opts[:mod]}; " \
              "failed to alias #{view} in #{self}"
      end
    end

    def format *format_names, &block
      if format_names.empty?
        format_names = [:base]
      elsif format_names.first == :all
        format_names =
          Card::Format.registered.reject { |f| Card::Format.aliases[f] }
      end
      format_names.each do |f|
        define_on_format f, &block
      end
    end

    def define_on_format format_name=:base, &block
      # format class name, eg. HtmlFormat
      klass = Card::Format.format_class_name format_name

      # called on current set module, eg Card::Set::Type::Pointer
      mod = const_get_or_set klass do
        # yielding set format module, eg Card::Set::Type::Pointer::HtmlFormat
        m = Module.new
        register_set_format Card.const_get(klass), m
        m.extend Card::Set::Format
        m
      end
      mod.class_eval &block
    end

    def view *args, &block
      format do
        view *args, &block
      end
    end

    def stage_method method, opts={}, &block
      class_eval do
        define_method "_#{method}", &block
        define_method method do |*args|
          error =
            if !director.stage_ok? opts
              if !stage
                "phase method #{method} called outside of event phases"
              else
                "#{opts.inspect} method #{method} called in phase #{stage}"
              end
            elsif !on_condition_applies?(opts[:on])
              "on: #{opts[:on]} method #{method} called on #{@action}"
            end
          if error
            raise Card::Error, error
          else
            send "_#{method}", *args
          end
        end
      end
    end

    # include a set module and all its format modules
    # @param [Module] set
    # @param [Hash] opts choose the formats you want to include
    # @option opts [Symbol, Array<Symbol>] :only include only these formats
    # @option opts [Symbol, Array<Symbol>] :except don't include these formats
    # @example
    # include_set Type::Basic, except: :css
    def include_set set, opts={}
      set_type = set.abstract_set? ? :abstract : :nonbase
      @@modules[set_type][set.shortname].each do |set_mod|
        include set_mod
      end
      include_set_formats set, opts
    end

    def each_format set
      set_type = set.abstract_set? ? :abstract : :nonbase
      format_type = "#{set_type}_format".to_sym
      @@modules[format_type].each_pair do |format, set_format_mod_hash|
        next unless (format_mods = set_format_mod_hash[set.shortname])
        yield format, format_mods
      end
    end

    # include a format modules of a set
    # @param [Module] set
    # @param [Hash] opts choose the formats you want to include
    # @option opts [Symbol, Array<Symbol>] :only include only these formats
    # @option opts [Symbol, Array<Symbol>] :except don't include these formats
    # @example
    # include_set Type::Basic, except: :css
    def include_set_formats set, opts={}
      each_format set do |format, format_mods|
        match = format.to_s.match(/::(?<format>[^:]+)Format/)
        format_sym = match ? match[:format] : :base
        next if opts[:except] && Array(opts[:except]).include?(format_sym)
        next if opts[:only] && !Array(opts[:only]).include?(format_sym)
        format_mods.each do |format_mod|
          define_on_format format_sym do
            include format_mod
          end
        end
      end
    end

    def ensure_set &block
      set_module = yield
    rescue NameError => e
      if e.message =~ /uninitialized constant (?:Card::Set::)?(.+)$/
        Regexp.last_match(1).split('::').inject(Card::Set) do |set_mod, module_name|
          set_mod.const_get_or_set module_name do
            Module.new
          end
        end
      end
      # try again - there might be another submodule that doesn't exist
      ensure_set &block
    else
      set_module.extend Card::Set
    end
    # the set loading process has two main phases:

    #  1. Definition: interpret each set file, creating/defining set and
    #     set_format modules
    #  2. Organization: have base classes include modules associated with the
    #     'all' set, and clean up the other modules

    class << self
      # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # Definition Phase

      # each set file calls `extend Card::Set` when loaded
      def extended mod
        register_set mod
      end

      # make the set available for use
      def register_set set_module
        if set_module.all_set?
          # automatically included in Card class
          modules[:base] << set_module
        else
          set_type = set_module.abstract_set? ? :abstract : :nonbase
          # made ready for dynamic loading via #include_set_modules
          modules[set_type][set_module.shortname] ||= []
          modules[set_type][set_module.shortname] << set_module
        end
      end

      def write_tmp_file from_file, to_file, rel_path
        name_parts = rel_path.gsub(/\.rb/, '').split(File::SEPARATOR)
        submodules = name_parts.map { |a| "module #{a.camelize};" } * ' '
        file_content = <<EOF
# -*- encoding : utf-8 -*-
class Card; module Set; #{submodules} extend Card::Set
# ~~~~~~~~~~~ above autogenerated; below pulled from #{from_file} ~~~~~~~~~~~
#{File.read from_file}

# ~~~~~~~~~~~ below autogenerated; above pulled from #{from_file} ~~~~~~~~~~~
end;end;#{'end;' * name_parts.size}
EOF

        FileUtils.mkdir_p File.dirname(to_file)
        File.write to_file, file_content
        to_file
      end

      # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # Organization Phase

      # 'base modules' are modules that are permanently included on the Card or
      # Format class
      # 'nonbase modules' are included dynamically on singleton_classes
      def process_base_modules
        process_base_module_list modules[:base], Card
        modules[:base_format].each do |format_class, modules_list|
          process_base_module_list modules_list, format_class
        end
        modules.delete :base
        modules.delete :base_format
      end

      def process_base_module_list list, klass
        list.each do |mod|
          klass.send :include, mod if mod.instance_methods.any?
          if (class_methods = mod.const_get_if_defined(:ClassMethods))
            klass.send :extend, class_methods
          end
        end
      end

      def clean_empty_modules
        clean_empty_module_from_hash modules[:nonbase]
        modules[:nonbase_format].values.each do |hash|
          clean_empty_module_from_hash hash
        end
      end

      def clean_empty_module_from_hash hash
        hash.each do |mod_name, modlist|
          modlist.delete_if { |x| x.instance_methods.empty? }
          hash.delete mod_name if modlist.empty?
        end
      end
    end

    def register_set_format format_class, mod
      if all_set?
        # ready to include in base format classes
        modules[:base_format][format_class] ||= []
        modules[:base_format][format_class] << mod
      else
        format_type = abstract_set? ? :abstract_format : :nonbase_format
        # ready to include dynamically in set members' format singletons
        format_hash = modules[format_type][format_class] ||= {}
        format_hash[shortname] ||= []
        format_hash[shortname] << mod
      end
    end

    def shortname
      parts = name.split '::'
      first = 2 # shortname eliminates Card::Set
      pattern_name = parts[first].underscore
      last = if pattern_name == 'abstract'
               first + 1
             else
               set_class = Card::SetPattern.find pattern_name
               first + set_class.anchor_parts_count
             end
      parts[first..last].join '::'
    end

    def abstract_set?
      name =~ /^Card::Set::Abstract::/
    end

    def all_set?
      name =~ /^Card::Set::All::/
    end

    private

    def set_specific_attributes *args
      Card.set_specific_attributes ||= []
      Card.set_specific_attributes += args.map(&:to_s)
    end

    def attachment name, args
      include Abstract::Attachment
      set_specific_attributes name,
                              :load_from_mod,
                              :action_id_of_cached_upload,
                              :empty_ok,
                              "remote_#{name}_url".to_sym
      uploader_class = args[:uploader] || FileUploader
      mount_uploader name, uploader_class
    end
  end
end
