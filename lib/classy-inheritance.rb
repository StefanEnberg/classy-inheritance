
module Stonean
  module ClassyInheritance
    VERSION = '0.6.3'

    def self.version
      VERSION
    end

    module ClassMethods
      def depends_on(model_sym, options = {}) 
        define_relationship(model_sym,options)

        # Optional presence of handling
        if options.has_key?(:validates_presence_if) && options[:validates_presence_if] != true
          if [Symbol, String, Proc].include?(options[:validates_presence_if].class)
            validates_presence_of model_sym, :if => options[:validates_presence_if]
          end
        else
          validates_presence_of model_sym
        end

        if options.has_key?(:validates_associated_if) && options[:validates_associated_if] != true
          if [Symbol, String, Proc].include?(options[:validates_associated_if].class)
            validates_associated_dependent model_sym, options, :if => options[:validates_associated_if]
          end
        else
          validates_associated_dependent model_sym, options 
        end

        # Before save functionality to create/update the requisite object
        define_save_method(model_sym, options[:as])

        # Adds a find_with_<model_sym> class method
        define_find_with_method(model_sym)

        if options[:as]
          define_can_be_method_on_requisite_class(options[:class_name] || model_sym.to_s.classify, options[:as])
        end

        options[:attrs].each{|attr| define_accessors(model_sym, attr, options)}
      end


      def can_be(model_sym, options = {})
        unless options[:as]
          raise ArgumentError, ":as attribute required when calling can_be"
        end

        klass = model_sym.to_s.classify

        define_method "is_a_#{model_sym}?" do
          eval("self.#{options[:as]}_type == '#{klass}'")
        end

        find_with_method = "find_with_#{self.name.underscore}"

        define_method "as_a_#{model_sym}" do
          eval("#{klass}.send(:#{find_with_method},self.#{options[:as]}_id)")
        end
      end

      private

      def classy_options
        [:as, :attrs, :prefix, :postfix, :validates_presence_if, :validates_associated_if]
      end

      def delete_classy_options(options, *keepers)
        options.delete_if do |key,value|
          classy_options.include?(key) && !keepers.include?(key)
        end
        options
      end

      def define_relationship(model_sym, options)
        opts = delete_classy_options(options.dup, :as)
        if opts[:as]
          as_opt = opts.delete(:as)
          opts = polymorphic_constraints(as_opt).merge(opts)
          has_one model_sym, opts
        else
          belongs_to model_sym, opts
        end
      end

      def define_save_method(model_sym, polymorphic_name = nil)
        define_method "save_requisite_#{model_sym}" do
          # Return unless the association exists
          eval("return unless self.#{model_sym}")

          # Set the polymorphic type and id before saving
          if polymorphic_name
            eval("self.#{model_sym}.#{polymorphic_name}_type = self.class.name")
            eval("self.#{model_sym}.#{polymorphic_name}_id = self.id")
          end

          if polymorphic_name
            # Save only if it's an update, has_one creates automatically
            eval <<-SAVEIT
              unless self.#{model_sym}.new_record?
                self.#{model_sym}.save
              end
            SAVEIT
          else
            eval("self.#{model_sym}.save")
          end
        end

        before_save "save_requisite_#{model_sym}".to_sym
      end

      def define_find_with_method(model_sym)
        self.class.send :define_method, "find_with_#{model_sym}" do |*args|
          eval <<-CODE
            if args[1] && args[1].is_a?(Hash)
              if args[1].has_key?(:include)
                inc_val = args[1][:include]
                new_val = inc_val.is_a?(Array) ? inc_val.push(:#{:model_sym}) : [inc_val, :#{model_sym}] 
                args[1][:include] = new_val
              else
                args[1].merge!({:include => :#{model_sym}})
              end
            else
              args << {:include => :#{model_sym}}
            end
            find(*args)
          CODE
        end
      end

      def define_accessors(model_sym, attr, options)
        accessor_method_name = attr

        if options[:prefix]
          accessor_method_name = (options[:prefix] == true) ? "#{model_sym}_#{accessor_method_name}" : "#{options[:prefix]}_#{accessor_method_name}"
        end

        if options[:postfix]
          accessor_method_name = (options[:postfix] == true) ? "#{accessor_method_name}_#{model_sym}" : "#{accessor_method_name}_#{options[:postfix]}"
        end

        define_method accessor_method_name do
          eval("self.#{model_sym} ? self.#{model_sym}.#{attr} : nil")
        end

        define_method "#{accessor_method_name}=" do |val|
          model_defined = eval("self.#{model_sym}")

          unless model_defined
            klass = options[:class_name] || model_sym.to_s.classify
            eval("self.#{model_sym} = #{klass}.new")
          end

          eval("self.#{model_sym}.#{attr}= val")
        end
      end

      def define_can_be_method_on_requisite_class(model_sym, polymorphic_name)
        klass = model_sym.to_s
        requisite_klass = eval(klass)
        unless requisite_klass.respond_to?(self.name.underscore.to_sym)
          requisite_klass.send :can_be, self.name.underscore, 
            :as => polymorphic_name 
        end
      end

      def polymorphic_constraints(polymorphic_name)
        { :foreign_key => "#{polymorphic_name}_id",
          :conditions => "#{polymorphic_name}_type = '#{self.name}'"}
      end
    end # ClassMethods
  end # ClassyInheritance module
end # Stonean module

if Object.const_defined?("ActiveRecord") && ActiveRecord.const_defined?("Base")
  module ActiveRecord::Validations::ClassMethods

    def validates_associated_dependent(model_sym, options, configuration = {})
      configuration = { :message => I18n.translate('activerecord.errors.messages.invalid'), :on => :save }.update(configuration)

      validates_each(model_sym, configuration) do |record, attr_name, value|
        associate = record.send(attr_name)
        if associate && !associate.valid?
          associate.errors.each do |key, value|
            if options[:prefix]
              key = (options[:prefix] == true) ? "#{model_sym}_#{key}" : "#{options[:prefix]}_#{key}"
            end
            if options[:postfix]
              key = (options[:postfix] == true) ? "#{key}_#{model_sym}" : "#{key}_#{options[:postfix]}"
            end
            record.errors.add(key, value) unless record.errors[key]
          end
        end
      end
    end
  end
                                    

  ActiveRecord::Base.class_eval do
    extend Stonean::ClassyInheritance::ClassMethods
  end
end
