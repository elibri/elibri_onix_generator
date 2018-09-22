module Elibri
  module ONIX
    module Model

      class Contributor

        attr_accessor :role_onix_code, :name, :last_name, :language_onix_code, :full_name

        def initialize(attributes = {})
          attributes.each do |key, value|
            self.send("#{key}=", value)
          end
        end

        def generated_full_name
          full_name || "#{name} #{last_name}".strip
        end
      end
    end
  end
end
