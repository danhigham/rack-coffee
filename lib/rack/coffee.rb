require 'time'
require 'rack/file'
require 'rack/utils'

module Rack
  class Coffee
    F = ::File

    attr_accessor :class_urls, :urls, :root
    DEFAULTS = {:static => true}
    
    def initialize(app, opts={})
      opts = DEFAULTS.merge(opts)
      @app = app
      @urls = *opts[:urls] || '/javascripts'
      @class_urls = opts[:class_urls] || '/javascripts/classes'
      @root = opts[:root] || Dir.pwd
      @server = opts[:static] ? Rack::File.new(root) : app
      @cache = opts[:cache]
      @ttl = opts[:ttl] || 86400
      @output_path = opts[:output_path] || '/public'
      
      define_command opts
    end
    
    def define_command(opts={})
      if @cache
        @command = ['coffee', '-o', opts[:output_path]] 
      else
        @command = ['coffee', '-p']      
      end
      
      @command.push('--bare') if opts[:nowrap] || opts[:bare]
      @command = @command.join(' ')
    end
    
    def brew(coffee)
      if @cache
        out = IO.popen("#{@command} #{coffee}")
        out.readlines
      else
        IO.popen("#{@command} #{coffee}")
      end
    end
    
    def read_file(path)
      output = nil
      F.open(path, "r") do |file|
        output = file.read
      end
      output
    end
    
    def call(env)
      path = Utils.unescape(env["PATH_INFO"])
      return [403, {"Content-Type" => "text/plain"}, ["Forbidden\n"]] if path.include?('..')
      return @app.call(env) unless urls.any?{|url| path.index(url) == 0} and (path =~ /\.js$/)
 
      coffee = F.join(root, path.sub(/\.js$/,'.coffee'))
      
      if F.file?(coffee)
          
        # modified_time = F.mtime(coffee)
        # 
        # if env['HTTP_IF_MODIFIED_SINCE']
        #   cached_time = Time.parse(env['HTTP_IF_MODIFIED_SINCE'])
        #   if modified_time <= cached_time
        #     return [304, {}, 'Not modified']
        #   end
        # end

        headers = {"Content-Type" => "application/javascript", "Last-Modified" => F.mtime(coffee).httpdate}
        
        if @cache
          headers['Cache-Control'] = "max-age=#{@ttl}"
          headers['Cache-Control'] << ', public' if @cache == :public
        end
        
        bare = !coffee.match(Regexp.new("^#{@root}#{@class_urls}")).nil?
        
        output_path = bare ? F.join(".", @output_path, @class_urls) : F.join(".", @output_path, @urls)
        define_command :bare => bare, :output_path => output_path
        
        if @cache
          brew(coffee)

          out = read_file F.join(output_path, path.match(/[^\/]+$/)[0])
        
          [200, headers, out]
        else
          [200, headers, brew(coffee)]
        end
      else
        @server.call(env)
      end
    end
  end
end
