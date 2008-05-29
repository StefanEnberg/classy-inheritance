$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

module ActiveRecord::Validations::ClassMethods
  def validates_associated(association, options = {})
    class_eval do
      validates_each(association) do |record, associate_name, value|
        associate = record.send(associate_name)
        if associate && !associate.valid?
          associate.errors.each do |key, value|
            record.errors.add(key, value)
          end
        end
      end
    end
  end
end

module Stonean
  module DependsOn
    def self.included(base)
      base.extend Stonean::ClassyInheritance::ClassMethods
    end

    module ClassMethods
      def depends_on(model_sym, options = {}) 
        define_relationship(model_sym,options)

        validates_presence_of model_sym
        validates_associated model_sym

        # Before save functionality to create/update the requisite object
        define_save_method(model_sym, options[:as])

        define_find_method(model_sym)


        options[:attrs].each{|attr| define_accessors(model_sym, attr)}
      end

      #model_instance = instance_variable_get("@#{model_sym}")
      private
      def define_relationship(model_sym, options)
        if options[:as]
          has_one model_sym, polymorphic_constraints(options[:as])
        else
          belongs_to model_sym
        end
      end

      def define_save_method(model_sym, polymorphic_name = nil)
        define_method "save_requisite_#{model_sym}" do
          if polymorphic_name
            eval("self.#{model_sym}.#{polymorphic_name}_type = self.class.name")
            eval("self.#{model_sym}.#{polymorphic_name}_id = self.id")
          end

          eval("self.#{model_sym}.save")
        end

        before_save "save_requisite_#{model_sym}".to_sym
      end

      def define_find_method(model_sym)
        self.class.send :define_method, "find_with_#{model_sym}" do |*args|
          eval <<-CODE
            if args[1] && args[1].is_a?(Hash)
              if args[1].has_key?(:include)
                inc_val = args[1][:include]
                new_val = inc_val.is_a?(Array) ? inc_val.push(:#{:model_sym}) : [inc_val, :#{model_sym}] 
                args[1][:include] = new_val
              else
                args[1].merge({:include => :#{model_sym}})
              end
            else
              args << {:include => :#{model_sym}}
            end
            find(*args)
          CODE
        end
      end

      def define_accessors(model_sym, attr)
        define_method attr do
          eval("self.#{model_sym} ? self.#{model_sym}.#{attr} : nil")
        end

        define_method "#{attr}=" do |val|
          model_defined = eval("self.#{model_sym}")

          unless model_defined
            klass = model_sym.to_s.classify
            eval("self.#{model_sym} = #{klass}.new")
          end

          eval("self.#{model_sym}.#{attr}= val")
        end
      end

      def polymorphic_constraints(polymorphic_name)
        { :foreign_key => "#{polymorphic_name}_id",
          :conditions => "#{polymorphic_name}_type = '#{self.name}'"}
      end

    end # ClassMethods
  end # ClassyInheritance module
end # Stonean module
ActiveRecord::Base.send :include, Stonean::ClassyInheritance