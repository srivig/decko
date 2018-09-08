format :html do
  view :server_error, template: :haml

  view :unsupported_view, perms: :none, tags: :unknown_ok do
    %(
      <strong>
        view <em>#{voo.unsupported_view}</em>
        not supported for <em>#{error_cardname}</em>
      </strong>
    )
  end

  view :message, perms: :none, tags: :unknown_ok do
    frame { params[:message] }
  end

  view :missing do
    return "" unless card.ok? :create  # should this be moved into ok_view?
    path_opts = voo.type ? { card: { type: voo.type } } : {}
    link_text = "Add #{_render_title}"
    klass = "slotter missing-#{@denied_view || voo.home_view}"
    wrap { link_to_view :new, link_text, path: path_opts, class: klass }
  end

  view :closed_missing, perms: :none do
    wrap_with :span, h(title_in_context), class: "faint"
  end

  view :conflict, cache: :never do
    actor_link = link_to_card card.last_action.act.actor.name
    class_up "card-slot", "error-view"
    wrap do # ENGLISH below
      alert "warning" do
        %(
          <strong>Conflict!</strong>
          <span class="new-current-revision-id">#{card.last_action_id}</span>
          <div>#{actor_link} has also been making changes.</div>
          <div>Please examine below, resolve above, and re-submit.</div>
          #{render_act}
        )
      end
    end
  end

  view :errors, perms: :none do
    return if card.errors.empty?
    voo.title = card.name.blank? ? "Problems" : tr(:problems_name, cardname: card.name)
    voo.hide! :menu
    class_up "d0-card-frame", "card card-warning card-inverse"
    class_up "alert", "card-error-msg"
    frame { standard_errors }
  end

  view :not_found do
    voo.hide! :menu
    voo.title = "Not Found"
    frame do
      [not_found_errors, sign_in_or_up_links("to create it")]
    end
  end

  view :denial do
    focal? ? loud_denial : quiet_denial
  end

  def view_for_unknown view
    case
    when focal? && ok?(:create) then :new
    when commentable?(view)     then view
    else super
    end
  end

  def commentable? view
    return false unless self.class.tagged(view, :comment) &&
      show_view?(:comment_box, :hide)
    ok? :comment
  end

  def rendering_error exception, view
    debug_error exception if Auth.always_ok?
    details = Auth.always_ok? ? backtrace_link(exception) : error_cardname
    wrap_with :span, class: "render-error alert alert-danger" do
      [tr(:error_rendering, scope: [:lib, :card, :format, :error],
                            cardname: details,
                            view: view)]
    end
  end

  def backtrace_link exception
    class_up "alert", "render-error-message errors-view admin-error-message"
    warning = alert("warning", true) do
      %{
        <h3>Error message (visible to admin only)</h3>
        <p><strong>#{CGI.escapeHTML exception.message}</strong></p>
        <div>#{exception.backtrace * "<br>\n"}</div>
      }
    end
    link = link_to_card error_cardname, nil, class: "render-error-link"
    link + warning
  end

  def standard_errors
    card.errors.map do |attrib, msg|
      alert "warning", true do
        attrib == :abort ? h(msg) : standard_error_message(attrib, msg)
      end
    end
  end

  def standard_error_message attribute, message
    "<strong>#{h attribute.to_s.upcase}:</strong> #{h message}"
  end

  def not_found_errors
    if card.errors.any?
      standard_errors
    else
      haml :not_found
    end
  end

  def sign_in_or_up_links to_task
    return if Auth.signed_in?
    links = [signin_link, signup_link].compact.join " #{tr :or} "
    wrap_with(:div) do
      [tr(:please), links, to_task].join(" ") + "."
    end
  end

  def signin_link
    link_to_card :signin, tr(:sign_in)
  end

  def signup_link
    return unless signup_ok?
    link_to tr(:sign_up), path: { action: :new, mark: :signup }
  end

  def signup_ok?
    Card.new(type_id: Card::SignupID).ok? :create
  end

  def quiet_denial
    wrap_with :span, class: "denied" do
      "<!-- Sorry, you don't have permission (#{@denied_task}) -->"
    end
  end

  def loud_denial
    frame do
      [wrap_with(:h1, tr(:sorry)),
       wrap_with(:div, loud_denial_message)]
    end
  end

  def loud_denial_message
    to_task = @denied_task ? tr(:denied_task, denied_task: @denied_task) : tr(:to_do_that)

    case
    when not_denied_task_read?
      tr(:read_only)
    when Auth.signed_in?
      tr(:need_permission_task, task: to_task)
    else
      Env.save_interrupted_action request.env["REQUEST_URI"]
      sign_in_or_up_links to_do_unauthorized_task
    end
  end

  def not_denied_task_read?
    @denied_task != :read && Card.config.read_only
  end

  def to_do_unauthorized_task
    @denied_task ? tr(:denied_task, denied_task: @denied_task) : tr(:to_do_that)
  end
end
