require "decko/application"
require_relative "alias"
require "card/seed_consts"

CARD_TASKS =
  [
    :migrate,
    { migrate: [:cards, :structure, :core_cards, :deck_cards, :redo, :stamp] },
    :reset_cache
  ]

link_task CARD_TASKS, from: :decko, to: :card

decko_namespace = namespace :decko do
  desc "create a decko database from scratch, load initial data"
  task :seed do
    seed
  end

  desc "create a decko database from scratch, load initial data, don't reset the cache"
  task :seed_without_reset do
    # This variant is needed to generate test databases for decks
    # with custom codenames.
    # The cache reset loads the environment. That tends to fail
    # because of missing codenames that are added after the intial decko seed.
    seed with_cache_reset: false
  end

  desc "clear and load fixtures with existing tables"
  task reseed: :environment do
    ENV["SCHEMA"] ||= "#{Cardio.gem_root}/db/schema.rb"

    decko_namespace["clear"].invoke
    decko_namespace["load"].invoke
  end

  desc "empty the card tables"
  task :clear do
    conn = ActiveRecord::Base.connection

    puts "delete all data in bootstrap tables"
    DECKO_SEED_TABLES.each do |table|
      conn.delete "delete from #{table}"
    end
  end

  desc "Load bootstrap data into database"
  task :load do
    decko_namespace["load_without_reset"].invoke
    puts "reset cache"
    system "bundle exec rake decko:reset_cache" # needs loaded environment
  end

  desc "Load bootstrap data into database but don't reset cache"
  task :load_without_reset do
    require "decko/engine"
    puts "update card_migrations"
    decko_namespace["assume_card_migrations"].invoke

    if Rails.env == "test" && !ENV["GENERATE_FIXTURES"]
      puts "loading test fixtures"
      Rake::Task["db:fixtures:load"].invoke
    else
      puts "loading bootstrap"
      decko_namespace["bootstrap:load"].invoke
    end

    puts "set symlink for assets"
    decko_namespace["update_assets_symlink"].invoke
  end

  desc "update decko gems and database"
  task :update do
    ENV["NO_RAILS_CACHE"] = "true"
    # system 'bundle update'
    if Decko.paths["tmp"].existent
      FileUtils.rm_rf Decko.paths["tmp"].first, secure: true
    end
    Dir.mkdir Decko.paths["tmp"].first
    decko_namespace["migrate"].invoke
    # FIXME: remove tmp dir / clear cache
    puts "set symlink for assets"
    decko_namespace["update_assets_symlink"].invoke
  end

  desc "set symlink for assets"
  task :update_assets_symlink do
    assets_path = File.join(Rails.public_path, "assets")
    if Rails.root.to_s != Decko.gem_root && !File.exist?(assets_path)
      FileUtils.rm assets_path if File.symlink? assets_path
      FileUtils.ln_s(Decko::Engine.paths["gem-assets"].first, assets_path)
    end
  end


  alias_task :migrate, "card:migrate"

  desc "insert existing card migrations into schema_migrations_cards to avoid re-migrating"
  task :assume_card_migrations do
    require "decko/engine"

    Cardio.assume_migrated_upto_version :core_cards
  end

  def seed with_cache_reset: true
    ENV["SCHEMA"] ||= "#{Cardio.gem_root}/db/schema.rb"
    # FIXME: this should be an option, but should not happen on standard
    # creates!
    begin
      Rake::Task["db:drop"].invoke
    rescue
      puts "not dropped"
    end

    puts "creating"
    Rake::Task["db:create"].invoke

    puts "loading schema"

    Rake::Task["db:schema:load"].invoke

    load_task = "decko:load"
    load_task << "_without_reset" unless with_cache_reset
    Rake::Task[load_task].invoke
  end

  namespace :emergency do
    task rescue_watchers: :environment do
      follower_hash = Hash.new { |h, v| h[v] = [] }

      Card.where("right_id" => 219).each do |watcher_list|
        watcher_list.include_set_modules
        next unless watcher_list.left
        watching = watcher_list.left.name
        watcher_list.item_names.each do |user|
          follower_hash[user] << watching
        end
      end

      Card.search(right: { codename: "following" }).each do |following|
        Card::Auth.as_bot do
          following.update_attributes! content: ""
        end
      end

      follower_hash.each do |user, items|
        next unless (card = Card.fetch(user)) && card.account
        Card::Auth.as(user) do
          following = card.fetch trait: "following", new: {}
          following.items = items
        end
      end
    end
  end
end

def version
  ENV["VERSION"] ? ENV["VERSION"].to_i : nil
end
