# -*- encoding : utf-8 -*-
require 'byebug'
class Card
  def find_action_by_params args
    case 
    when args[:rev]
      actions[args[:rev].to_i-1] 
    when args[:rev_id]
      action = Card::Action.find(args[:rev_id])  #ACT restrict to same card or allow to overwrite card with changes of different card?
      if action.card_id == id 
        action 
      end
    end
  end
  
  def nth_revision index
    revision(actions[index-1])
  end
  
  def revision action
    if action.is_a? Integer
      action = Card::Action.find(action)
    end
    action and Card::TRACKED_FIELDS.inject({}) do |attr_changes, field|
      last_change = action.changes.find_by_field(field) || last_change_on(field, :not_after=>action)
      attr_changes[field.to_sym] = (last_change ? last_change.value : self[field])
      attr_changes
    end
  end
  
  
  class Action < ActiveRecord::Base
    belongs_to :act, :foreign_key=>:card_act_id
    belongs_to :card
    has_many :changes, :foreign_key=>:card_action_id
    
    # replace with enum if we start using rails 4 
    TYPE = [:create, :update, :delete]
    
    def action_type=(value)
      write_attribute(:action_type, TYPE.index(value))
    end
    
    def action_type
      TYPE[read_attribute(:action_type)]
    end
    
    def set_act
      self.set_act ||= self.acts.last
    end
  end
end


