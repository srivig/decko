# -*- encoding : utf-8 -*-

class AddCardVirtualsTable < Card::Migration::Core
  def up
    drop_table :card_virtuals if table_exists? :card_virtuals
    create_table :card_virtuals do |t|
      t.integer :left_id
      t.integer :right_id, limit: 16777215
      t.text :content
    end

    add_index :card_virtuals, :right_id, name: "left_id_index"
    add_index :card_virtuals, :left_id, name: "right_id_index"
  end

  def down
    drop_table :card_virtuals
  end
end
