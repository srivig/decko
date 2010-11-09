module Chunk
  class Transclude < Reference
    attr_reader :stars
    attr_accessor :format
    unless defined? TRANSCLUDE_PATTERN
      #  {{+name|attr:val;attr:val;attr:val}}
      TRANSCLUDE_PATTERN = /\{\{(([^\|]+?)\s*(\|([^\}]+?))?)\}\}/
    end         
    
    def self.pattern() TRANSCLUDE_PATTERN end
  
    def initialize(match_data, content)
      super   
      @format = content.format
      #warn "FOUND TRANSCLUDE #{match_data} #{content}"
      @card_name, @options, @configs = self.class.parse(match_data)
      @renderer = @content.renderer
      @card = @content.card or raise "No Card in Transclude Chunk!!"     
      @card_name.gsub!(/_self/,@card.name)
    end
  
    def self.parse(match)
      name = match[2].strip
      options = {
        :tname   =>name,
        :base  => 'self',
        :view  => nil,
        :item  => nil,
        :type  => nil,
        :size  => nil,
      }
      style = {}
      configs = Hash.new_from_semicolon_attr_list match[4]
      configs.each_pair do |key, value|
        if options.key? key.to_sym
          options[key.to_sym] = value
        else
          style[key] = value
        end
      end
      options[:style] = style.map{|k,v| CGI.escapeHTML("#{k}:#{v};")}.join
      [name, options, configs]  
    end                        
    
    def unmask_text(&block)
      return @unmask_text if @unmask_text
      return @card_name unless block_given?
Rails.logger.info("unmask TR #{@card_name}::#{@options.inspect}")
      ret = case @card_name
      when /^\#\#/            ; return '' # invisible comment
	       	                              # visible comment
      when /^\#/||nil?||blank?; return "<!-- #{CGI.escapeHTML match[1]} -->"
      else
        case view = @options[:view] and view = view.to_sym
        when :name;     refcard ? refcard.name : @card_name
        when :key;      refcard_name.to_key
	when :link;     card_link
        when :linkname; Cardname.escape(refcard_name)
        when :titled;   content_tag( :h1, less_fancy_title(refcard_name) ) + self.render( :content )
        when :rss_titled;
          # content includes wrap  (<object>, etc.) , which breaks at least safari rss reader.
          content_tag( :h2, less_fancy_title(refcard_name) ) + self.render( :expanded_view_content )

        else
Rails.logger.info("unmask TR: #{@card_name}::#{@options.compact.inspect}")
          block.call(@card_name, @options)
        end
      end
Rails.logger.info("unmask TR[#{ret}] V:#{view.inspect}")
      ret
    end

    def revert                             
      configs = @configs.to_semicolon_attr_list;  
      configs = "|#{configs}" unless configs.blank?
      @text = "{{#{@card_name}#{configs}}}"
      super
    end
    
    private
    def base_card 
      case @options[:base]
      when 'self'; @card
      when 'parent'; @card.trunk
      else invalid_option(:base)
      end
    end
    
    def invalid_option(key)
      raise Wagn::Oops, "Invalid argument {'#{key}': '#{@options[key]}'} in transclusion syntax"
    end

  end
end
