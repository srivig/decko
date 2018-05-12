event :update_follow_rules, :finalize, on: :save, when: :update_all_users do
  defaults = item_names.map do |item|
    if (set_card = Card.fetch item.to_name.left) && set_card.type_code == :set
      option_card = Card.fetch(item.to_name.right) ||
                    Card[item.to_name.right.to_sym]
      option = if option_card.follow_option?
                 option_card.name
               else
                 "*always"
               end
      [set_card, option]
    elsif (set_card = Card.fetch sug) && set_card.type_code == :set
      [set_card, "*always"]
    end
  end.compact
  Auth.as_bot do
    Card.search(type: "user").each do |user|
      defaults.each do |set_card, option|
        follow_rule = Card.fetch(set_card.follow_rule_name(user.name), new: {})
        next unless follow_rule
        follow_rule.drop_item "*never"
        follow_rule.drop_item "*always"
        follow_rule.add_item option
        follow_rule.save!
      end
    end
  end
  Card.follow_caches_expired
end

format :html do
  view :edit, perms: :update, tags: :unknown_ok do
    frame_and_form :update, hidden: { success: "_self",
                                      card: { update_all_users: false } } do
      [
        _render_content_formgroup,
        _render_confirm_update_all,
        _render_edit_buttons
      ]
    end
  end

  view :edit_buttons do
    button_formgroup do
      [submit_and_update_button, simple_submit_button, cancel_to_edit_button]
    end
  end

  def submit_and_update_button
    submit_button text: "Submit and update all users",
                  disable_with: "Updating", class: "follow-updater"
  end

  def simple_submit_button
    button_tag "Submit", class: "follow"
  end

  def cancel_to_edit_button
    cancel_button href: path(view: :edit, id: card.id)
  end

  view :confirm_update_all do
    wrap do
      alert "info" do
        %(
          <h1>Are you sure you want to change the default follow rules?</h1>
          <p>You may choose to update all existing users.
             This may take a while. </p>
        )
      end
    end
  end
end
