module Wagn::Set::Type::Image  
  def self.included(base)
    super
    Rails.logger.debug "included(#{base}) #{self}"
    base.class_eval { card_attachment CardImage }
  end
end
