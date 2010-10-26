module Cardlib
  module Settings
    
    def setting setting_name, fallback=nil
      card = setting_card setting_name, fallback
      card && begin
        User.as(:wagbot){ card.content }
      end
    end
    
    def setting_card setting_name, fallback=nil
      ## look for pattern
      Wagn::Pattern.set_names( self ).each do |name|
        #next if setcard=Card.fetch(name) and setcard.virtual?
        if value = Card.fetch( "#{name}+#{setting_name.to_star}" , :skip_virtual => true)
          return value
        elsif fallback and value2 = Card.fetch("#{name}+#{fallback.to_star}", :skip_virtual => true)
          return value2              
        end
      end
      return nil
    end

    module ClassMethods
      def default_setting setting_name, fallback=nil
        card = default_setting_card setting_name, fallback
        return card && card.content
      end
      
      def default_setting_card setting_name, fallback=nil
        setting_card = Card.fetch( "*all+#{setting_name.to_star}" , :skip_virtual => true) or 
          (fallback ? default_setting_card(fallback) : nil)
      end
    end
      
    def self.append_features(base)
      super
      base.extend(ClassMethods)
    end

  end
end