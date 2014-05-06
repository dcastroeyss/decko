include Factory
# #include Supplier
#

def factory_process input
end

 
factory_process do |input|
  # begin
  #   Sass.compile input.content, :style=>:compressed
  # rescue Exception=>e
  #   raise Card::Oops, "Stylesheet Error:\n#{ e.message }"
  # end
end

format :html do

  view :editor, :type=>:plain_text
  
  view :core do |args|
    # FIXME: scan must happen before process for inclusion interactions to work, but this will likely cause
    # problems with including other css?
    process_content ::CodeRay.scan( _render_raw, :css ).div, :size=>:icon
  end
  
end

event :reset_style_for_css, :after=>:store do
  Right::Style.delete_style_files
end