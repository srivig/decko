include All::Permissions::Accounts

view :raw do
  case
  when card.real? then card.content
  # following supports legacy behavior
  # (should be moved to User+*email+*type plus right)
  when card.left.account then card.left.account.email
  else ""
  end
end

view :core, :raw

event :validate_email, :validate, on: :save do
  if content.present? && content !~ /^([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})$/i
    errors.add :content, tr(:error_invalid_address)
  end
end

event :validate_unique_email, after: :validate_email, on: :save do
  if content.present?
    Auth.as_bot do
      wql = { right_id: Card::EmailID, eq: content, return: :id }
      wql[:not] = { id: id } if id
      wql_comment = tr(:search_email_duplicate, content: content)
      if Card.search(wql, wql_comment).first
        errors.add :content, tr(:error_not_unique)
      end
    end
  end
end

event :downcase_email, :prepare_to_validate, on: :save do
  return if !content || content == content.downcase
  self.content = content.downcase
end

def email_required?
  !built_in?
end

def ok_to_read
  if own_email? || Auth.always_ok?
    true
  else
    deny_because tr(:deny_email_restricted)
  end
end

def own_email?
  name.part_names[0].key == Auth.as_card.key
end
