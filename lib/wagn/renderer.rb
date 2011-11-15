require 'diff'


class StubCardController < CardController
  def url_options
    default_url_options
  end
  
  def params()  {} end
  def session() {} end
end


module Wagn
 class Renderer
    module NoControllerHelpers
      def logged_in?
        User.logged_in?
      end
    end
  
    include ReferenceTypes
  
    VIEW_ALIASES = {
      :view  => :open,
      :card  => :open,
      :line  => :closed,
      :bare  => :core,
      :naked => :core
    }
    
    UNDENIABLE_VIEWS = [ 
      :deny_view, :edit_virtual, :too_slow, :too_deep, :open_missing, :closed_missing, :name, :link, :url
    ]
  
    RENDERERS = {
      :html => :RichHtml,
      :css  => :Text,
      :txt  => :Text
    }
  
    cattr_accessor :max_char_count, :max_depth, :set_views,
      :current_slot, :ajax_call, :fallback
    self.max_char_count = 200
    self.max_depth = 10
  
    attr_reader :action, :inclusion_map, :params, :layout, :relative_content,
        :template, :root, :format, :controller
    attr_accessor :card, :main_content, :main_card, :context, :char_count,
        :depth, :item_view, :form, :type, :base, :state, :sub_count,
        :render_args, :layout, :flash, :showname #, :requested_view
  
    # View definitions
    #
    #   When you declare:
    #     define_view(:view_name, "<set>") do |args|
    #
    #   Methods are defined on the renderer
    #
    #   The external api with checks:
    #     render(:viewname, args)
    #
    #   Roughly equivalent to:
    #     render_viewname(args)
    #
    #   The internal call that skips the checks:
    #     _render_viewname(args)
    # 
    #   Each of the above ultimately calls:
    #     _final(_set_key)_viewname(args)
    
    
    module DefineView
      def define_view(view, opts={}, &final)
        fallback[view] = opts.delete(:fallback) if opts.has_key?(:fallback)
        view_key = get_pattern(view, opts)
        class_eval do
          define_method( "_final_#{view_key}", &final )
          if view_key == view
            define_method( "_render_#{view}" ) do |*a| a = [{}] if a.empty?
              final_meth = view_method( view )
              send(final_meth, *a) { raw(yield) }
            end
  
            define_method( "render_#{view}" ) do |*a|
              denial=deny_render(view, *a) and return denial
              send( "_render_#{view}", *a) { raw(yield) }
            end
          end
        end
      end

      def alias_view(view, opts={}, *aliases)
        view_key = get_pattern(view, opts)
        aliases.each do |aview|
          aview_key = case aview
            when String; aview
            when Symbol; (view_key==view ? aview.to_sym : view_key.to_s.sub(/_#{view}$/, "_#{aview}").to_sym)
            when Hash;   get_pattern( aview[:view] || view, aview)
            else; raise "Bad view #{aview.inspect}"
            end
#          raise "aview_key = #{aview_key}"
          class_eval do
            define_method( "_final_#{aview_key}".to_sym ) do |*a|
              #Rails.logger.debug "ALIAS call: #{aview_key} called, calling #{view_key}"
              send("_final_#{view_key}", *a)
            end
          end
        end
      end
  
    end
  
    extend DefineView

    class << self
      def get_pattern(view,opts)
        unless pkey =  Wagn::Model::Pattern.method_key(opts) #and opts.empty?
          raise "Bad Pattern opts: #{pkey.inspect} #{opts.inspect}"
        end
        return (pkey.blank? ? view : "#{pkey}_#{view}").to_sym
      end
  
      def register_view(view_key, nview_key)
        if @@set_views.has_key?(nview_key)
          raise "Attempt to redefine view: #{nview_key}, #{view_key}"
        end
        @@set_views[nview_key.to_sym] = "_final_#{view_key}".to_sym
      end
  
      @@set_views, @@fallback = {},{} unless @@set_views
  
      def new(card, opts={})
        if self==Renderer
          fmt = (opts[:format] ? opts[:format].to_sym : :html)
          renderer = (RENDERERS.has_key?(fmt) ? RENDERERS[fmt] : fmt.to_s.camelize).to_sym
          if Renderer.const_defined?(renderer)
            return Renderer.const_get(renderer).new(card, opts) 
          end
        end
        new_renderer = self.allocate
        new_renderer.send :initialize, card, opts
        new_renderer
      end
  
      def set_view(key) @@set_views[key.to_sym] end
      def view_aliases() VIEW_ALIASES end
    end
  
    def initialize(card, opts=nil)
      Renderer.current_slot ||= self unless(opts[:not_current])
      @card = card
      if opts
        [ :main_content, :main_card, :base, :action, :context,
          :params, :relative_content, :format, :flash, :layout, :controller].
            map {|s| instance_variable_set "@#{s}", opts[s]}
      end
      inclusion_map( opts )
  
      @relative_content ||= {}
      @format ||= :html
      
      @sub_count = @char_count = 0
      @depth = 0
      @root = self
    end
  
  
    def params()  @params ||= controller.params  end
    def flash()   @flash  ||= controller.request ? controller.flash : {} end
  
    def controller
      @controller ||= StubCardController.new
    end
  
    def template
      @template ||= begin
        t = ActionView::Base.new( CardController.view_paths)
        t.extend CardController._helpers
        t.extend NoControllerHelpers
        t.controller = controller
        t._routes = controller._routes 
        t
      end
    end
    
    
    
    def method_missing(method_id, *args, &proc)
      proc = proc { raw yield } if proc
      template.send(method_id, *args, &proc) 
    end
    
    def session
      @controller ? @controller.session : {}
    end
  
    def ajax_call?() @@ajax_call end
    def outer_level?() @depth == 0 end
  
    def too_deep?() @depth >= max_depth end
  
    def subrenderer(subcard, ctx_base=nil)
      subcard = Card.fetch_or_new(subcard) if String===subcard
      self.sub_count += 1
      sub = self.clone
      sub.depth = @depth+1
      sub.item_view = sub.main_content = sub.main_card = sub.showname = nil
      sub.sub_count = sub.char_count = 0
      sub.context = "#{ctx_base||context}_#{sub_count}"
      sub.card = subcard
      sub
    end
  
    def inclusion_map(opts=nil)
      VIEW_ALIASES
    end
  
    def process_content(content=nil, opts={})
      return content unless card
      content = card.content if content.blank?
  
  #Rails.logger.debug "process_content(#{content}, #{card&&card.content}),  #{card&&card.name}"
  
      wiki_content = WikiContent.new(card, content, self, inclusion_map)
      update_references(wiki_content) if card.references_expired
  
      wiki_content.render! do |opts|
        expand_inclusion(opts) { yield }
      end
    end
    alias expand_inclusions process_content
  
  
    def deny_render(action, args={})
      return false if UNDENIABLE_VIEWS.member?(action)
      ch_action = case
        when too_deep?      ; :too_deep
        when !card          ; false
        when [:edit, :edit_in_form].member?(action)
          allowed = card.ok?(card.new_card? ? :create : :update)
          !allowed && :deny_view #should be deny_create or deny_update...
        else
          !card.ok?(:read) and :deny_view #should be deny_read
      end
      ch_action and render(ch_action, args)
    end
    
    def canonicalize_view( view )
      (v=!view.blank? && VIEW_ALIASES[view.to_sym]) ? v : view
    end
  
    def render(view=:view, args={})
      args[:home_view] ||= view
      self.render_args = args.clone
      denial = deny_render(view, args) and return denial
  
      view = canonicalize_view(view)
      @state ||= case view
        when :edit, :edit
        when :closed; :line
        else :view
      end
  
      result = 
        if render_meth = view_method(view)
          send(render_meth, args) { yield }
        else
          "<strong>#{card.name} - unknown card view: '#{view}' M:#{render_meth.inspect}</strong>"
        end
  
      result.strip
    rescue Exception=>e
      warn "Error #{e.message} #{e.backtrace*"\n"}"
      raise e unless Card::PermissionDenied===e
      return "Permission error: #{e.message}"
    end
  
    def view_method(view)
      return "_final_#{view}" unless card
      card.method_keys.each do |method_key|
        meth = "_final_"+(method_key.blank? ? "#{view}" : "#{method_key}_#{view}")
        return meth if respond_to?(meth.to_sym)
      end
      return @@fallback[view]
    end
    
    def form_for_multi
      block = Proc.new {}
      builder = ActionView::Base.default_form_builder
      card.name = card.name.gsub(/^#{Regexp.escape(root.card.name)}\+/, '+') if root.card.new_card?  ##FIXME -- need to match other relative inclusions.
      builder.new("card[cards][#{card.cardname.pre_cgi}]", card, template, {}, block)
    end
  
    def form
      @form ||= form_for_multi
    end
  
    def resize_image_content(content, size)
      size = (size.to_s == "full" ? "" : "_#{size}")
      content.gsub(/_medium(\.\w+\")/,"#{size}"+'\1')
    end
  
    def render_partial( partial, locals={} )
      raw template.render(:partial=>partial, :locals=>{ :card=>card, :slot=>self }.merge(locals))
    end
  
    def render_view_action(action, locals={})
      render_partial "views/#{action}", locals
    end
  
    def replace_references( old_name, new_name )
      #warn "replacing references...card name: #{card.name}, old name: #{old_name}, new_name: #{new_name}"
      wiki_content = WikiContent.new(card, card.content, self)
  
      wiki_content.find_chunks(Chunk::Link).each do |chunk|
        if chunk.cardname
          link_bound = chunk.cardname == chunk.link_text
          chunk.cardname = chunk.cardname.replace_part(old_name, new_name)
          chunk.link_text=chunk.cardname.to_s if link_bound
          #Rails.logger.info "repl ref: #{chunk.cardname.to_s}, #{link_bound}, #{chunk.link_text}"
        end
      end
  
      wiki_content.find_chunks(Chunk::Transclude).each do |chunk|
        chunk.cardname =
          chunk.cardname.replace_part(old_name, new_name) if chunk.cardname
      end
  
      String.new wiki_content.unrender!
    end
  
    def expand_inclusion(options)
      return options[:comment] if options.has_key?(:comment)
      # Don't bother processing inclusion if we're already out of view
      return '' if (state==:line && self.char_count > Renderer.max_char_count)
  
      tname=options[:tname]
      if is_main = tname=='_main'
        tcard, tcont = root.main_card, root.main_content
        return self.wrap_main(tcont) if tcont
        return "{{#{options[:unmask]}}}" || '{{_main}}' unless @depth == 0 and tcard
  
        tname = tcard.cardname
        [:item, :view, :size].each{ |key| val=symbolize_param(key) and options[key]=val }
        # main card uses these CGI options as inclusion args      
        options[:context] = 'main'
        options[:view] ||= :open
      end
  
      options[:home_view] = options[:view] ||= context == 'layout_0' ? :core : :content
      tcardname = tname.to_cardname
      options[:fullname] = fullname = tcardname.fullname(card.cardname, base, options, params)
      options[:showname] = tcardname.to_show(fullname)      #Rails.logger.debug "fullname [#{tname.inspect}](#{card&&card.name||card.inspect}, #{base.inspect}, #{options.inspect}"
  
      tcard ||= begin
        case
        when state ==:edit   ;  Card.fetch_or_new(fullname, new_inclusion_card_args(tname, options))
        when base.respond_to?(:name);   base
        else                 ;  Card.fetch_or_new(fullname)
        end
      end
  
      result = process_inclusion(tcard, options)
      result = resize_image_content(result, options[:size]) if options[:size]
      @char_count += (result ? result.length : 0) #should we strip html here?
      is_main ? self.wrap_main(result) : result
    rescue Card::PermissionDenied
      ''
    end
  
    def wrap_main(content)
      content  #no wrapping in base renderer
    end
  
    def symbolize_param(param)
      val = params[param]
      (val && !val.to_s.empty?) ? val.to_sym : nil
    end
  
    def resize_image_content(content, size)
      size = (size.to_s == "full" ? "" : "_#{size}")
      content.gsub(/_medium(\.\w+\")/,"#{size}"+'\1')
    end
  
  
    def process_inclusion(tcard, options)
      sub = subrenderer(tcard, options[:context])
      oldrenderer, Renderer.current_slot = Renderer.current_slot, sub  #don't like depending on this global var switch
      sub.item_view = options[:item] if options[:item]
      sub.type = options[:type] if options[:type]
      sub.showname = options[:showname] || tcard.cardname
  
      new_card = tcard.new_card? && !tcard.virtual?
  
      requested_view = options[:home_view] = (options[:view] || :content).to_sym
#      sub.requested_view = requested_view
      approved_view = case

        when [:name, :link, :linkname, :closed_rule, :open_rule].member?(requested_view)  ; requested_view
        when :edit == state
         tcard.virtual? ? :edit_virtual : :edit_in_form
        when new_card
          case
            when requested_view==:raw    ; :blank
            when state==:line            ; :closed_missing
            else                         ; :open_missing
          end
        when state==:line       ; :closed_content
        else                    ; requested_view
        end
      result = raw( sub.render(approved_view, options) )
      Renderer.current_slot = oldrenderer
      result
    rescue Exception=>e
      Rails.logger.info "inclusion-error #{e.message}"
      Rails.logger.debug "Trace:\n#{e.backtrace*"\n"}"
      %{<span class="inclusion-error">error rendering #{link_to_page((tcard ? tcard.name : 'unknown card'), nil, :title=>CGI.escapeHTML(e.message))}</span>}
    end
  
    def get_inclusion_content(cardname)
      #Rails.logger.debug "get_inclusion_content(#{cardname.inspect})"
      content = relative_content[cardname.to_s.gsub(/\+/,'_')]
  
      # CLEANME This is a hack to get it so plus cards re-populate on failed signups
      if relative_content['cards'] and card_params = relative_content['cards'][cardname.pre_cgi]
        content = card_params['content']
      end
      content if content.present?  #not sure I get why this is necessary - efm
    end
  
    def new_inclusion_card_args(tname, options)
      args = { :type =>options[:type] }
      args[:loaded_trunk]=card if tname =~ /^\+/
      if content=get_inclusion_content(options[:tname])
        args[:content]=content
      end
      args
    end
  
    def update_references(rendering_result=nil)
      return unless card
      WikiReference.delete_all ['card_id = ?', card.id]
  
      if card.id
        card.connection.execute("update cards set references_expired=NULL where id=#{card.id}")
        rendering_result ||= WikiContent.new(card, _render_refs, self)
        rendering_result.find_chunks(Chunk::Reference).each do |chunk|
          reference_type =
            case chunk
              when Chunk::Link;       chunk.refcard ? LINK : WANTED_LINK
              when Chunk::Transclude; chunk.refcard ? TRANSCLUSION : WANTED_TRANSCLUSION
              else raise "Unknown chunk reference class #{chunk.class}"
            end
  
         #ref_name=> (rc=chunk.refcardname()) && rc.to_key() || '',
          #raise "No name to ref? #{card.name}, #{chunk.inspect}" unless chunk.refcardname()
          WikiReference.create!( :card_id=>card.id,
            :referenced_name=> (rc=chunk.refcardname()) && rc.to_key() || '',
            :referenced_card_id=> chunk.refcard ? chunk.refcard.id : nil,
            :link_type=>reference_type
           )
        end
      end
    end
  
    def main_card?() context=~/^main_\d$/ end
      
    def build_link(href, text)
      #Rails.logger.info "build_link(#{href.inspect}, #{text.inspect})"
      klass = case href
        when /^https?:/; 'external-link'
        when /^mailto:/; 'email-link'
        when /^\//
          href = full_uri(href.to_s)      
          'internal-link'
        else
          known_card = !!Card.fetch(href)
          cardname = href.to_cardname
          text = cardname.to_show(card.name) unless text
          href = href.to_cardname
          href = '/wagn/' + (known_card ? href.to_url_key : CGI.escape(href.escape))
          #href+= "?type=#{type.to_url_key}" if type && card && card.new_card?  WANT THIS; NEED TEST
          href = full_uri(href.to_s)
          known_card ? 'known-card' : 'wanted-card'
      end
      #Rails.logger.info "build_link(#{href.inspect}, #{text.inspect}) #{klass}"
      %{<a class="#{klass}" href="#{href.to_s}">#{text.to_s}</a>}      
    end
    
    def full_uri(relative_uri)
      relative_uri
    end
  
  end
  

  class Renderer::Text < Renderer
    def initialize card, opts
      super card,opts
    
      if format=='css' && controller
        controller.response.headers["Cache-Control"] = "public"
      end
    end
  end

  class Renderer::Kml < Renderer
  end

  class Renderer::Rss < Renderer::RichHtml
    def full_uri(relative_uri)  System.base_url + relative_uri  end
  end

  class Renderer::EmailHtml < Renderer::RichHtml
    def full_uri(relative_uri)  System.base_url + relative_uri  end
  end
end