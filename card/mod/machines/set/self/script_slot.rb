include_set Abstract::CodeFile

def source_files
  %w[decko_mod decko_editor decko_layout decko_navbox decko_upload decko].map do |n|
    "#{n}.js.coffee"
  end
end
