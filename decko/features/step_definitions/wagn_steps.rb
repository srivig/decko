# -*- encoding : utf-8 -*-
# rubocop:disable Lint/AmbiguousRegexpLiteral
require "uri"
require "cgi"
support_paths_file = File.join File.dirname(__FILE__), "..", "support", "paths"
require File.expand_path support_paths_file

if RUBY_VERSION =~ /^2/
  require "byebug"
else
  require "debugger"
end

Given /^site simulates setup need$/ do
  Card::Auth.simulate_setup_need!
end

Given /^site stops simulating setup need$/ do
  Card::Auth.simulate_setup_need! false
  step "I am signed out"
end

Given /^I am signed in as (.+)$/ do |account_name|
  accounted = Card[account_name]
  visit "/update/:signin?card[subcards][%2B*email][content]="\
    "#{accounted.account.email}&card[subcards][%2B*password][content]=joe_pass"
  # could optimize by specifying simple text success page
end

Given /^I am signed out$/ do
  visit "/"
  step 'I follow "Sign out"' if page.has_content? "Sign out"
end

# Given /^I sign in as (.+)$/ do |account_name|
#   # FIXME: define a faster simulate method ("I am logged in as")
#   accounted = Card[account_name]
#   @current_id = accounted.id
#   visit "/:signin"
#   fill_in "card[subcards][+*email][content]", with: accounted.account.email
#   fill_in "card[subcards][+*password][content]", with: 'joe_pass'
#   click_button "Sign in"
#   page.should have_content(account_name)
# end

Given /^the card (.*) contains "([^\"]*)"$/ do |cardname, content|
  Card::Auth.as_bot do
    card = Card.fetch cardname, new: {}
    card.content = content
    card.save!
  end
end

When /^(.*) edits? "([^\"]*)"$/ do |username, cardname|
  signed_in_as(username) do
    visit "/card/edit/#{cardname.to_name.url_key}"
  end
end

wysiwyg_re = /^(.*) edits? "([^\"]*)" entering "([^\"]*)" into wysiwyg$/
When wysiwyg_re do |username, cardname, content|
  signed_in_as(username) do
    visit "/card/edit/#{cardname.to_name.url_key}"
    page.execute_script "$('#main .d0-card-content').val('#{content}')"
    click_button "Submit"
    wait_for_ajax
  end
end

edit_re = /^(.*) edits? "([^\"]*)" setting (.*) to "([^\"]*)"$/
When edit_re do |username, cardname, _field, content|
  signed_in_as(username) do
    visit "/card/edit/#{cardname.to_name.url_key}"
    set_content "card[content]", content
    click_button "Submit"
    wait_for_ajax
  end
end

filling_re = /^(.*) edits? "([^\"]*)" filling in "([^\"]*)"$/
When filling_re do |_username, cardname, content|
  visit "/card/edit/#{cardname.to_name.url_key}"
  fill_in "card[content]", with: content
end

When /^(.*) edits? "([^\"]*)" with plusses:/ do |username, cardname, plusses|
  signed_in_as(username) do
    visit "/card/edit/#{cardname.to_name.url_key}"
    plusses.hashes.first.each do |name, content|
      set_content "card[subcards][#{cardname}+#{name}][content]", content
    end
    click_button "Submit"
    wait_for_ajax
  end
end

def set_content name, content, _cardtype=nil
  Capybara.ignore_hidden_elements = false
  wait_for_ajax
  set_ace_editor_content(name, content) ||
    set_pm_editor_content(name, content) ||
    fill_in(name, with: content)
  Capybara.ignore_hidden_elements = true
end

def set_ace_editor_content name, content
  return unless all(".ace-editor-textarea[name='#{name}']").present? &&
                page.evaluate_script("typeof ace != 'undefined'")
  sleep(0.5)
  page.execute_script "ace.edit($('.ace_editor').get(0))"\
                      ".getSession().setValue('#{content}')"
  true
end

def set_pm_editor_content name, content
  (editors = all(".prosemirror-editor > [name='#{name}']"))
  return unless editors.present?
  editor_id = editors.first.first(:xpath, ".//..")[:id]
  escaped_quotes = content.gsub("'", "\\'")
  page.execute_script "$('##{editor_id} .ProseMirror').text('#{escaped_quotes}')"
  true
end

content_re = /^(.*) creates?\s*a?\s*([^\s]*) card "(.*)" with content "(.*)"$/
When content_re do |username, cardtype, cardname, content|
  create_card(username, cardtype, cardname, content) do
    set_content "card[content]", content, cardtype
  end
end

create_re = /^(.*) creates?\s*([^\s]*) card "([^"]*)"$/
When create_re do |username, cardtype, cardname|
  create_card username, cardtype, cardname
end

plus_re = /^(.*) creates?\s*([^\s]*) card "([^"]*)" with plusses:$/
When plus_re do |username, cardtype, cardname, plusses|
  create_card(username, cardtype, cardname) do
    plusses.hashes.first.each do |name, content|
      set_content "card[subcards][+#{name}][content]", content, cardtype
    end
  end
end

When /^(.*) deletes? "([^\"]*)"$/ do |username, cardname|
  signed_in_as(username) do
    visit "/card/delete/#{cardname.to_name.url_key}"
  end
end

When /^(?:|I )enter "([^"]*)" into "([^"]*)"$/ do |value, field|
  selector = ".RIGHT-#{field.to_name.safe_key} input.d0-card-content"
  find(selector).set value
end

When /^(?:|I )upload the (.+) "(.+)"$/ do |attachment_name, filename|
  Capybara.ignore_hidden_elements = false
  attach_file "card_#{attachment_name}", find_file(filename)
  Capybara.ignore_hidden_elements = true
  wait_for_ajax
end

def find_file filename
  roots = "{#{Cardio.root}/mod/**,#{Cardio.gem_root}/mod/**,#{Decko.gem_root}}"
  paths = Dir.glob(File.join(roots, "features", "support", filename))
  raise ArgumentError, "couldn't find file '#{filename}'" if paths.empty?
  paths.first
end

Given /^(.*) (is|am) watching "([^\"]+)"$/ do |user, _verb, cardname|
  Delayed::Worker.new.work_off
  user = Card::Auth.current.name if user == "I"
  signed_in_as user do
    step "the card #{cardname}+#{user}+*follow contains \"[[*always]]\""
  end
end

Given /^(.*) (is|am) not watching "([^\"]+)"$/ do |user, _verb, cardname|
  user = Card::Auth.current.name if user == "I"
  signed_in_as user do
    step "the card #{cardname}+#{user}+*follow contains \"[[*never]]\""
  end
end

When /I wait a sec/ do
  sleep 1
end

When /I wait (\d+) seconds?$/ do |period|
  sleep period.to_i
end

def wait_for_ajax
  Timeout.timeout(Capybara.default_max_wait_time) do
    sleep(0.5) until finished_all_ajax_requests?
  end
end

def finished_all_ajax_requests?
  jquery_undefined? || page.evaluate_script("jQuery.active").zero?
end

def jquery_undefined?
  page.evaluate_script("typeof(jQuery) === 'undefined'")
end

When /^I wait for ajax response$/ do
  wait_for_ajax
end

# Then /what/ do
#   save_and_open_page
# end
#
Then /debug/ do
  require "pry"
  #
  nil
end
#   if RUBY_VERSION =~ /^2/
#   else
#     debugger
#   end
#   nil
# end

def create_card username, cardtype, cardname, content=""
  signed_in_as(username) do
    if cardtype == "Pointer"
      Card.create name: cardname, type: cardtype, content: content
    else
      visit "/card/new?card[name]=#{CGI.escape(cardname)}&type=#{cardtype}"
      yield if block_given?
      click_button "Submit"
      wait_for_ajax
    end
  end
end

def signed_in_as username
  sameuser = (username == "I")
  sameuser ||= (Card::Auth.current.key == username.to_name.key)
  was_signed_in = Card::Auth.current_id if Card::Auth.signed_in?
  step "I am signed in as #{username}" unless sameuser
  yield
  return if sameuser
  msg = if was_signed_in
          "I am signed in as #{Card[was_signed_in].name}"
        else
          'I follow "Sign out"'
        end
  step msg
end

When /^In (.*) I follow "([^\"]*)"$/ do |section, link|
  within scope_of(section) do
    click_link link
  end
end

When /^In (.*) I click "(.*)"$/ do |section, link|
  within scope_of(section) do
    click_link link
  end
end

When /^I click "(.*)" within "(.*)"$/ do |link, selector|
  within selector do
    click_link link
  end
end

link_re = /^In (.*) I find link with class "(.*)" and click it$/
When link_re do |section, css_class|
  within scope_of(section) do
    find("a.#{css_class}").click
  end
end

When /^In (.*) I find link with icon "(.*)" and click it$/ do |section, icon|
  within scope_of(section) do
    find("a > i.material-icons", text: icon).click
  end
end

When /^In (.*) I find button with icon "(.*)" and click it$/ do |section, icon|
  within scope_of(section) do
    find("button > i.material-icons", text: icon).click
  end
end

Given /^Jobs are dispatched$/ do
  Delayed::Worker.new.work_off
end

Then /^No errors in the job queue$/ do
  if (last = Delayed::Job.last) && (last.last_error)
    puts last.last_error
    expect(last.last_error).to be_blank
  end
end


Then /I submit$/ do
  click_button "Submit"
end

When /^I open the main card menu$/ do
  slot = "$('#main .menu-slot .vertical-card-menu._show-on-hover .card-slot')"
  page.execute_script "#{slot}.show()"
  page.find("#main .menu-slot .card-menu a").click
end

When /^I close the modal window$/ do
  page.find(".modal-menu .close-modal").click
end

# When /^I pick (.*)$/ do |menu_item|
# end

Then /the card (.*) should contain "([^\"]*)"$/ do |cardname, content|
  visit path_to("card #{cardname}")
  within scope_of("main card content") do
    expect(page).to have_content(content)
  end
end

Then /the card (.*) should not contain "([^\"]*)"$/ do |cardname, content|
  visit path_to("card #{cardname}")
  within scope_of("main card content") do
    expect(page).not_to have_content(content)
  end
end

Then /the card (.*) should point to "([^\"]*)"$/ do |cardname, content|
  visit path_to("card #{cardname}")
  within scope_of("pointer card content") do
    expect(page).to have_content(content)
  end
end

Then /the card (.*) should not point to "([^\"]*)"$/ do |cardname, content|
  visit path_to("card #{cardname}")
  within scope_of("pointer card content") do
    expect(page).not_to have_content(content)
  end
end

Then /^In (.*) I should see "([^\"]*)"$/ do |section, text|
  within scope_of(section) do
    if text.index("|")
      expect(text.split("|").any? { |t| have_content(t) }).to be
    else
      expect(page).to have_content(text)
    end
  end
end

Then /^In (.*) I should not see "([^\"]*)"$/ do |section, text|
  within scope_of(section) do
    expect(page).not_to have_content(text)
  end
end

class_re = /^In (.*) I should (not )?see a ([^\"]*) with class "([^\"]*)"$/
Then class_re do |selection, neg, element, selector|
  # checks for existence of a element with a class in a selection context
  element = "a" if element == "link"
  within scope_of(selection) do
    verb = neg ? :should_not : :should
    page.send(verb, have_css([element, selector].join(".")))
  end
end

content_re = /^In (.*) I should (not )?see a ([^\"]*) with content "([^\"]*)"$/
Then content_re do |selection, neg, element, content|
  # checks for existence of a element with a class in a selection context
  element = "a" if element == "link"
  within scope_of(selection) do
    verb = neg ? :should_not : :should
    page.send(verb, have_css(element, text: content))
  end
end

Then /^the "([^"]*)" field should contain "([^"]*)"$/ do |field, value|
  expect(field_labeled(field).value).to match(/#{value}/)
end

Then /^"([^"]*)" should be selected for "([^"]*)"$/ do |value, field|
  element = field_labeled(field).element
  selected = element.search ".//option[@selected = 'selected']"
  expect(selected.inner_html).to match /#{value}/
end

Then /^"([^"]*)" should be signed in$/ do |user| # "
  has_css?(".my-card-link", text: user)
end

When /^I press enter to search$/ do
  find("#_keyword").native.send_keys(:return)
end

## variants of standard steps to handle """ style quoted args
Then /^I should see$/ do |text|
  expect(page).to have_content(text)
end

Then /^I should see a preview image of size (.+)$/ do |size|
  find("span.preview img[src*='#{size}.png']")
end

Then /^I should see an image of size "(.+)" and type "(.+)"$/ do |size, type|
  find("img[src*='#{size}.#{type}']")
end

img_sld = /^within "(.+)" I should see an image of size "(.+)" and type "(.+)"$/
Then img_sld do |selector, size, type|
  within selector do
    find("img[src*='#{size}.#{type}']")
  end
end

img_should = /^I should see a non-coded image of size "(.+)" and type "(.+)"$/
Then img_should do |size, type|
  element = find("img[src*='#{size}.#{type}']")
  expect(element[:src]).to match(%r{/~\d+/})
end

Then /^I should see "([^\"]*)" in color (.*)$/ do |text, css_class|
  page.has_css?(".diff-#{css_class}", text: text)
end

Then /^I should see css class "([^\"]*)"$/ do |css_class|
  find(css_class)
end

css_should = /^I should see css class "([^\"]*)" within "(.*)"$/
Then css_should do |css_class, selector|
  within selector do
    find(css_class)
  end
end

When /^I fill in "([^\"]*)" with$/ do |field, value|
  fill_in(field, with: value)
end

When(/^I scroll (-?\d+) pixels$/) do |number|
  page.execute_script "window.scrollBy(0, #{number})"
end

When(/^I scroll (\d+) pixels down$/) do |number|
  page.execute_script "window.scrollBy(0, #{number})"
end

When(/^I scroll (\d+) pixels up$/) do |number|
  page.execute_script "window.scrollBy(0, -#{number})"
end

module Capybara
  module Node
    # adapt capybara methods to fill in forms to decko's form interface
    module Actions
      alias_method :original_fill_in, :fill_in
      alias_method :original_select, :select

      def fill_in locator, options={}
        decko_fill_in(locator, options) || original_fill_in(locator, options)
      end

      def select value, options={}
        decko_select(value, options) || original_select(value, options)
      end

      def decko_fill_in locator, options
        el = labeled_field(:input, locator) || labeled_field(:textarea, locator)
        return unless el
        el.set options[:with]
        true
      end

      def decko_select value, options
        el = labeled_field :select, options[:from], visible: false
        return unless el
        value = el.find("option", text: value, visible: false)["value"]
        choose_value el, value
        true
      end

      def choose_value el, value
        id = el["id"]
        session.execute_script("$('##{id}').val('#{value}')")
        # session.execute_script("$('##{id}').trigger('chosen:updated')")
        # session.execute_script("$('##{id}').change()")
      end

      def labeled_field type, label, options={}
        label.gsub!(/^\+/, "") # because '+' is in an extra span,
        # descendant-or-self::text doesn't find it
        first :xpath,
              "//label[descendant-or-self::text()='#{label}']/..//#{type}",
              options.merge(wait: 5)
      end
    end
  end
end
