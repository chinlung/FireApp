require "singleton"
class Tray
  include Singleton
  attr_reader :logger
  attr_reader :watching_dir
  def initialize()
    @http_server = nil
    @compass_thread = nil
    @watching_dir = nil
    @logger = nil
    @history_dirs  = App.get_history
    @shell    = App.create_shell(Swt::SWT::ON_TOP | Swt::SWT::MODELESS)

    if org.jruby.platform.Platform::IS_MAC
      @standby_icon = App.create_image("icon/16_dark@2x.png")
      @active_icon = App.create_image("icon/16_white@2x.png")
      @watching_icon = App.create_image("icon/16@2x.png")
    else 
      @standby_icon = App.create_image("icon/16_dark.png")
      @active_icon = App.create_image("icon/16_white.png")
      @watching_icon = App.create_image("icon/16.png")
    end

    @tray_item = Swt::Widgets::TrayItem.new( App.display.system_tray, Swt::SWT::NONE)
    @tray_item.image = @standby_icon
    @tray_item.tool_tip_text = "Fire.app"
    @tray_item.addListener(Swt::SWT::Selection,  update_menu_position_handler) unless org.jruby.platform.Platform::IS_MAC
    @tray_item.addListener(Swt::SWT::MenuDetect, update_menu_position_handler)

    @menu = Swt::Widgets::Menu.new(@shell, Swt::SWT::POP_UP)
    @menu.addListener(Swt::SWT::Show, show_menu_handler)
    @menu.addListener(Swt::SWT::Hide, hide_menu_handler)

    @watch_item = add_menu_item( "Watch a Folder...", open_dir_handler)

    add_menu_separator

    @history_item = add_menu_item( "History:")

    build_history_menuitem

    add_menu_separator

    item =  add_menu_item( "Create Project", create_project_handler, Swt::SWT::CASCADE)

    item.menu = Swt::Widgets::Menu.new( @menu )
    build_compass_framework_menuitem( item.menu, create_project_handler )

    item =  add_menu_item( "Open Extensions Folder", open_extensions_folder_handler, Swt::SWT::PUSH)
    item =  add_menu_item( "Preference...", preference_handler, Swt::SWT::PUSH)

    item =  add_menu_item( "About", open_about_link_handler, Swt::SWT::CASCADE)
    item.menu = Swt::Widgets::Menu.new( @menu )
    add_menu_item( 'Homepage',                      open_about_link_handler,   Swt::SWT::PUSH, item.menu)
    add_menu_item( 'Compass ' + Compass::VERSION, open_compass_link_handler, Swt::SWT::PUSH, item.menu)
    add_menu_item( 'LiveReload.js',       open_livereloadjs_link_handler,    Swt::SWT::PUSH, item.menu)
    add_menu_item( 'Sass ' + Sass::VERSION,       open_sass_link_handler,    Swt::SWT::PUSH, item.menu)
    add_menu_item( 'Serve',       open_serve_link_handler,    Swt::SWT::PUSH, item.menu)
    add_menu_separator( item.menu )

    add_menu_item( "App Version: #{App.version}",                          nil, Swt::SWT::PUSH, item.menu)
    add_menu_item( App.compile_version, nil, Swt::SWT::PUSH, item.menu)
    add_menu_item( "Java System Properties", show_system_properties_handler, Swt::SWT::PUSH, item.menu)

    add_menu_item( "Quit",      exit_handler)
  end
  def shell 
    @shell
  end
  def run(options={})
    puts 'tray OK, spend '+(Time.now.to_f - INITAT.to_f).to_s

    if(options[:watch])
      watch(options[:watch])
    end

    SplashWindow.instance.dispose

    while(! @shell.is_disposed) do
      App.display.sleep if(!App.display.read_and_dispatch) 
      App.show_and_clean_notifications

    end

    App.display.dispose

  end

  def rewatch
    if @watching_dir
      dir = @watching_dir
      stop_watch
      watch(dir)
    end
  end

  def add_menu_separator(menu=nil, index=nil)
    menu = @menu unless menu
    if index
      Swt::Widgets::MenuItem.new(menu, Swt::SWT::SEPARATOR, index)
    else
      Swt::Widgets::MenuItem.new(menu, Swt::SWT::SEPARATOR)
    end
  end

  def add_menu_item(label, selection_handler = nil, item_type =  Swt::SWT::PUSH, menu = nil, index = nil)
    menu = @menu unless menu
    if index
      menuitem = Swt::Widgets::MenuItem.new(menu, item_type, index)
    else
      menuitem = Swt::Widgets::MenuItem.new(menu, item_type)
    end

    menuitem.text = label
    if selection_handler
      menuitem.addListener(Swt::SWT::Selection, selection_handler ) 
    else
      menuitem.enabled = false
    end
    menuitem
  end

  def add_compass_item(dir)
    if File.exists?(dir)
      menuitem = Swt::Widgets::MenuItem.new(@menu , Swt::SWT::PUSH, @menu.indexOf(@history_item) + 1 )
      menuitem.text = "#{dir}"
      menuitem.addListener(Swt::SWT::Selection, compass_switch_handler)
      menuitem
    end
  end

  def empty_handler
    Swt::Widgets::Listener.impl do |method, evt|

    end
  end

  def clear_history
    @menu.items.each do |item|
      item.dispose if @history_dirs.include?(item.text)
    end
    @history_dirs = []
    App.clear_histoy
    build_history_menuitem
  end

  def compass_switch_handler
    Swt::Widgets::Listener.impl do |method, evt|
      if @watching_dir
        stop_watch
      end
      watch(evt.widget.text)
    end
  end

  def open_dir_handler
    Swt::Widgets::Listener.impl do |method, evt|
      if @watching_dir
        stop_watch
      else
        dia = Swt::Widgets::DirectoryDialog.new(@shell)
        dir = dia.open
        watch(dir) if dir 
      end
    end
  end

  def open_extensions_folder_handler
    Swt::Widgets::Listener.impl do |method, evt|
      if !File.exists?(App.shared_extensions_path)
        FileUtils.mkdir_p(App.shared_extensions_path)
        FileUtils.cp(File.join(LIB_PATH, "documents", "extensions_readme.txt"), File.join(App.shared_extensions_path, "readme.txt") )
      end

      Swt::Program.launch(App.shared_extensions_path)
    end
  end

  def open_project_handler
    Swt::Widgets::Listener.impl do |method, evt|
      Swt::Program.launch(@watching_dir)
    end
  end

  def compass_project_config
    file_name = Compass.detect_configuration_file(@watching_dir)
    Compass.add_project_configuration(file_name)
  end

  def build_change_options_panel( index )
    @changeoptions_item = add_menu_item( "Change Options...", change_options_handler , Swt::SWT::PUSH, @menu, index)
    
  end

=begin
  def build_change_options_menuitem( index )

    @changeoptions_item = add_menu_item( "Change Sass Options...", empty_handler , Swt::SWT::CASCADE, @menu, index)
    submenu = Swt::Widgets::Menu.new( @menu )
    @changeoptions_item.menu = submenu

    outputstyle_item = add_menu_item( "Output Style", nil, Swt::SWT::PUSH, submenu)

    %W{nested expanded compact compressed}.each do |output_style|
      item = add_menu_item( output_style,     outputstyle_handler, Swt::SWT::RADIO, submenu )
      item.setSelection(true) if compass_project_config.output_style.to_s == output_style
    end

    add_menu_separator(submenu)

    options_item = add_menu_item( "Options", nil, Swt::SWT::PUSH, submenu)

    linecomments_item  = add_menu_item( "Line Comments", linecomments_handler, Swt::SWT::CHECK, submenu )
    linecomments_item.setSelection(true) if compass_project_config.line_comments

    debuginfo_item    = add_menu_item( "Debug Info",   debuginfo_handler,   Swt::SWT::CHECK, submenu )
    debuginfo_item.setSelection(true) if compass_project_config.sass_options && compass_project_config.sass_options[:debug_info] 
  end
=end

  def build_compass_framework_menuitem( submenu, handler )
    Compass::Frameworks::ALL.each do | framework |
      next if framework.name =~ /^_/
      next if framework.template_directories.empty?
      item = add_menu_item( framework.name, handler, Swt::SWT::CASCADE, submenu)
      framework_submenu = Swt::Widgets::Menu.new( submenu )
      item.menu = framework_submenu
      framework.template_directories.each do | dir |
        add_menu_item( dir, handler, Swt::SWT::PUSH, framework_submenu)
      end
    end
  end

  def build_history_menuitem
    @history_dirs.reverse.each do | dir |
      add_compass_item(dir)
    end
    App.set_histoy(@history_dirs[0, App::CONFIG["num_of_history"]])
  end

  def show_system_properties_handler
    Swt::Widgets::Listener.impl do |method, evt|
      str=[]
      java.lang.System.getProperties.each do |key, value|
        str << "#{key.strip} =>  #{value.strip}"
      end
      App.report( str.join("\n\n"))
    end
  end

  def create_project_handler
    Swt::Widgets::Listener.impl do |method, evt|
      dia = Swt::Widgets::FileDialog.new(@shell,Swt::SWT::SAVE)
      dir = dia.open
      if dir
        dir.gsub!('\\','/') if org.jruby.platform.Platform::IS_WINDOWS

        # if select a pattern
        if Compass::Frameworks::ALL.any?{ | f| f.name == evt.widget.getParent.getParentItem.text }
          framework = evt.widget.getParent.getParentItem.text
          pattern = evt.widget.text
        else
          framework = evt.widget.txt
          pattern = 'project'
        end

        App.try do 
          actual = App.get_stdout do
            Compass::Commands::CreateProject.new( dir, 
                                                 { :framework        => framework, 
                                                   :pattern          => pattern, 
                                                   :preferred_syntax => App::CONFIG["preferred_syntax"].to_sym 
            }).execute
          end
          App.report( actual) do
            Swt::Program.launch(dir)
          end
        end

        watch(dir)
      end
    end
  end

  def install_project_handler
    Swt::Widgets::Listener.impl do |method, evt|
      # if select a pattern
      if Compass::Frameworks::ALL.any?{ | f| f.name == evt.widget.getParent.getParentItem.text }
        framework = evt.widget.getParent.getParentItem.text
        pattern = evt.widget.text
      else
        framework = evt.widget.txt
        pattern = 'project'
      end

      App.try do 
        actual = App.get_stdout do
          Compass::Commands::StampPattern.new( @watching_dir, 
                                              { :framework => framework, 
                                                :pattern => pattern,
                                                :preferred_syntax => App::CONFIG["preferred_syntax"].to_sym 
          } ).execute
        end
        App.report( actual)
      end

    end
  end

  def change_options_handler 
    Swt::Widgets::Listener.impl do |method, evt|
      ChangeOptionsPanel.instance.open
    end
  end

  def preference_handler 
    Swt::Widgets::Listener.impl do |method, evt|
      PreferencePanel.instance.open
    end
  end

  def open_about_link_handler 
    Swt::Widgets::Listener.impl do |method, evt|
      Swt::Program.launch('http://compass.handlino.com')
    end
  end

  def open_compass_link_handler
    Swt::Widgets::Listener.impl do |method, evt|
      Swt::Program.launch('http://compass-style.org/')
    end
  end

  def open_sass_link_handler
    Swt::Widgets::Listener.impl do |method, evt|
      Swt::Program.launch('http://sass-lang.com/')
    end
  end

  def open_livereloadjs_link_handler
    Swt::Widgets::Listener.impl do |method, evt|
      Swt::Program.launch('https://github.com/livereload/livereload-js')
    end
  end

  def open_serve_link_handler
    Swt::Widgets::Listener.impl do |method, evt|
      Swt::Program.launch('http://get-serve.com/')
    end
  end

  def exit_handler
    Swt::Widgets::Listener.impl do |method, evt|
      stop_watch
      App.set_histoy(@history_dirs[0,App::CONFIG["num_of_history"]])
      @shell.close
    end
  end

  def show_menu_handler
    Swt::Widgets::Listener.impl do |method, evt|
      @tray_item.image = @active_icon
    end
  end
  def hide_menu_handler
    Swt::Widgets::Listener.impl do |method, evt|
      if @watching_dir
        @tray_item.image = @watching_icon
      else
        @tray_item.image = @standby_icon
      end
    end
  end

  def update_menu_position_handler 
    Swt::Widgets::Listener.impl do |method, evt|
      @menu.visible = true
    end
  end

  def clean_project_handler
    Swt::Widgets::Listener.impl do |method, evt|
      clean_project(true)
    end
  end

  def write_dynamaic_file(release_dir, request_path )
    new_file = File.join(release_dir, request_path)
    FileUtils.mkdir_p( File.dirname(  new_file ))
    puts request_path
    File.open(new_file, 'w') {|f| f.write( open("http://127.0.0.1:#{App::CONFIG['services_http_port']}#{URI.escape(request_path)}").read ) } 
  end 

  def build_project_handler
    Swt::Widgets::Listener.impl do |method, evt|
      build_project
    end
  end 
  def build_project(target_path=nil, options={})
    ENV["RACK_ENV"] = "production"

    project_path = File.expand_path(Compass.configuration.project_path)
    release_dir = File.expand_path( target_path || Compass.configuration.fireapp_build_path  || "build_#{Time.now.strftime('%Y%m%d%H%M%S')}")

    App.try do 

      report_window = nil
      if !options[:headless]
        report_window = App.report('Start build project!') do
          Swt::Program.launch(release_dir)
        end
      end

      FileUtils.rm_r( release_dir) if File.exists?(release_dir)
      FileUtils.mkdir_p( release_dir)

      # rebuild sass & coffeescript
      is_compass_project = false
      x = Compass::Commands::UpdateProject.new( project_path, {})
      if !x.new_compiler_instance.sass_files.empty? # if we rebuild compass project
        x.perform
        is_compass_project = true
      end

      blacklist = []

      build_ignore_file = "build_ignore.txt"

      if File.exists?(File.join( project_path, build_ignore_file))
        blacklist << build_ignore_file
        blacklist += File.open( File.join( project_path, build_ignore_file) ).readlines.map{|p|
          p.strip
        }
      else
        blacklist += [
          "*.swp",
          "*.layout",
          "*~",
          "*/.DS_Store",
          "*/.git",
          "*/.gitignore",
          "*.svn",
          "*/Thumbs.db",
          "*/.sass-cache",
          "*/.coffeescript-cache",
          "*/compass_app_log.txt",
          "*/fire_app_log.txt",
          "view_helpers.rb",
          "Gemfile",
          "Gemfile.lock",
          "config.ru"
        ]
        blacklist << File.basename(Compass.detect_configuration_file) if is_compass_project
      end

      if is_compass_project && Compass.configuration.fireapp_build_path 
        blacklist << File.join( Compass.configuration.fireapp_build_path, "*")
      end

      blacklist.uniq!
      blacklist = blacklist.map{|x| x.sub(/^.\//, '')}

      #build html 
      Dir.glob( File.join(project_path, '**', "[^_]*.*.{#{Tilt.mappings.keys.join(',')}}") ) do |file|
      if file =~ /build_\d{14}/ || file.index(release_dir)
        next 
      end
      extname=File.extname(file)
      if Tilt[ extname[1..-1] ]
        request_path = file[project_path.length ... (-1*extname.size)]
        pass = false
        blacklist.each do |pattern|
          if File.fnmatch(pattern, request_path[1..-1])
            pass = true
            break
          end
        end
        next if pass

        write_dynamaic_file(release_dir, request_path)
        report_window.append "Create: #{request_path}" if report_window
      end
      end

      Tilt.mappings.each{|key, value| blacklist << "*.#{key}" if !key.strip.empty? }

      #copy static file
      Dir.glob( File.join(project_path, '**', '*') ) do |file|
        path = file[(project_path.length+1) .. -1]
        next if path =~ /build_\d{14}/
          pass = false

        blacklist.each do |pattern|
          puts path,pattern if path =~ /proxy/
            if File.fnmatch(pattern, path)
              pass = true
              break
            end
        end
        next if pass

        new_file = File.join(release_dir, path)
        if File.file? file
          FileUtils.mkdir_p( File.dirname(  new_file ))
          FileUtils.cp( file, new_file )
          report_window.append "Copy: #{file.gsub(/#{project_path}/,'')}" if report_window
        end
      end

      end_build_project=Time.now
      report_window.append "Done!"  if report_window
    end
    ENV["RACK_ENV"] = "development"
    return release_dir
  end

  def deploy_project_handler
    Swt::Widgets::Listener.impl do |method, evt|
      App.try do 
        options = Compass.configuration.the_hold_options
        temp_build_folder = File.join(Dir.tmpdir, "fireapp", rand.to_s)
        respone = TheHoldUploader.upload_patch(build_project(temp_build_folder, {:headless => true}), options)
        if respone.code == "200"
          host=URI(options[:host]).host
          Swt::Program.launch("http://#{options[:project]}.#{options[:login]}.#{host}")
          App.alert("done")
        else
          App.alert(respone.body)
        end
      end
    end
  end

  def clean_project(show_report = false)
    dir = @watching_dir
    stop_watch
    App.try do 
      logger = Compass::Logger.new({ :display => App.display, :log_dir => dir})
      actual = App.get_stdout do
        Compass::Commands::CleanProject.new(dir, {:logger => logger}).perform
        Compass.reset_configuration!
        Compass::Commands::UpdateProject.new( dir, {:logger =>logger}).perform
        Compass.reset_configuration!
      end
      App.report( actual ) if show_report
    end
    watch(dir)
  end


  def update_config(need_clean_attr, value)
    new_config_str = "\n#{need_clean_attr} = #{value} # by Fire.app "

    file_name = Compass.detect_configuration_file(@watching_dir)

    if file_name
      new_config = ''
      last_is_blank = false
      config_file = File.new(file_name,'r').each do | x | 
        next if last_is_blank && x.strip.empty?
      new_config += x unless x =~ /by Fire\.app/ && x =~ Regexp.new(need_clean_attr)
      last_is_blank = x.strip.empty?
      end
      config_file.close
      new_config += new_config_str
      File.open(file_name, 'w'){ |f| f.write(new_config) }
    else

      config_filename = File.join(Compass.configuration.project_path, 'config.rb')

      if File.exists?(config_filename) #file "config.rb" exists!
        App.alert("can't create #{config_filename}")
        return
      end

      File.open( config_filename, 'w'){ |f| f.write(new_config_str) }
    end
  end

=begin
  def outputstyle_handler
    Swt::Widgets::Listener.impl do |method, evt|
      if evt.widget.getSelection 
        puts "output_style "+ ":#{evt.widget.text}"
        update_config( "output_style", ":#{evt.widget.text}" )
        clean_project
      end
    end
  end

  def linecomments_handler
    Swt::Widgets::Listener.impl do |method, evt|
      puts "line_comments "+ evt.widget.getSelection.to_s
      update_config( "line_comments", evt.widget.getSelection.to_s )
      clean_project
    end
  end

  def debuginfo_handler
    Swt::Widgets::Listener.impl do |method, evt|

      sass_options = compass_project_config.sass_options
      sass_options = {} if !sass_options.is_a? Hash
      sass_options[:debug_info] = evt.widget.getSelection

      update_config( "sass_options", sass_options.inspect )

      Compass::Commands::CleanProject.new(@watching_dir, {}).perform
      clean_project
    end
  end 
=end

  def watch(dir)
    dir.gsub!('\\','/') if org.jruby.platform.Platform::IS_WINDOWS
    App.try do 
      stop_watch
      logger = Compass::Logger.new({ :display => App.display, :log_dir => dir})
      Compass.reset_configuration!
      Dir.chdir(dir)

      x = Compass::Commands::UpdateProject.new( dir, {:logger => logger})

      Thread.abort_on_exception = true
      @compass_thread = Thread.new do
        Thread.current[:watcher]=Compass::Watcher::AppWatcher.new(dir, Compass.configuration.watches, {:logger=> logger})
        Thread.current[:watcher].watch!
      end

      @tray_item.image = @watching_icon
      @watching_dir = dir
      @menu.items.each do |item|
        item.dispose if @history_dirs.include?(item.text)
      end
      @history_dirs.delete_if { |x| x == dir }
      @history_dirs.unshift(dir)
      build_history_menuitem


      @watch_item.text="Stop watching " + dir

      @open_project_item =  add_menu_item( "Open Project Folder", 
                                          open_project_handler, 
                                          Swt::SWT::PUSH,
                                          @menu, 
                                          @menu.indexOf(@watch_item) +1 )

      @install_item =  add_menu_item( "Install...", 
                                     install_project_handler, 
                                     Swt::SWT::CASCADE,
                                     @menu, 
                                     @menu.indexOf(@open_project_item) +1 )
      @install_item.menu = Swt::Widgets::Menu.new( @menu )
      build_compass_framework_menuitem( @install_item.menu, install_project_handler )
      
      #build_change_options_menuitem( @menu.indexOf(@install_item) +1 )
      build_change_options_panel(@menu.indexOf(@install_item) +1 )

      @clean_item =  add_menu_item( "Clean && Compile", 
                                   clean_project_handler, 
                                   Swt::SWT::PUSH,
                                   @menu, 
                                   @menu.indexOf(@changeoptions_item) +1 )


      @build_project_item =  add_menu_item( "Build Project", 
                                           build_project_handler, 
                                           Swt::SWT::PUSH,
                                           @menu, 
                                           @menu.indexOf(@clean_item) +1 )
      last_item = @build_project_item
      if Compass.configuration.the_hold_options
        @deploy_project_item =  add_menu_item( "Deploy Project", 
                                              deploy_project_handler, 
                                              Swt::SWT::PUSH,
                                              @menu, 
                                              @menu.indexOf(@build_project_item) +1 )
        last_item = @deploy_project_item
      end

      if @menu.items[ @menu.indexOf(last_item)+1 ].getStyle != Swt::SWT::SEPARATOR
        add_menu_separator(@menu, @menu.indexOf(last_item) + 1 )
      end

      if App::CONFIG['services'].include?( :http )
        require "simplehttpserver"
        @simplehttpserver_thread = Thread.new do
          SimpleHTTPServer.instance.start(Compass.configuration.project_path, :Port =>  App::CONFIG['services_http_port'])
        end
      end

      if App::CONFIG['services'].include?( :livereload )
        @simplelivereload_thread = Thread.new do
          SimpleLivereload.instance.watch(Compass.configuration.project_path, { :port => App::CONFIG["services_livereload_port"] }) 
        end
      end

      return true

    end

    return false
  end

  def stop_watch

    SimpleLivereload.instance.unwatch if defined?(SimpleLivereload)
    SimpleHTTPServer.instance.stop if defined?(SimpleHTTPServer)
    FSEvent.stop_all_instances if Object.const_defined?("FSEvent") && FSEvent.methods.map{|x| x.to_sym}.include?(:stop_all_instances)

    if @compass_thread
      @compass_thread[:watcher].stop
    end

    [@simplelivereload_thread, @simplehttpserver_thread, @compass_thread].each do |x|
      x.kill if x && x.alive?
    end

    @logger = nil
    @compass_thread = nil
    @simplehttpserver_thread = nil
    @simplelivereload_thread = nil

    @watch_item.text="Watch a Folder..."
    @install_item.dispose() if @install_item && !@install_item.isDisposed
    @clean_item.dispose()   if @clean_item && !@clean_item.isDisposed
    @open_project_item.dispose()   if @open_project_item && !@open_project_item.isDisposed
    @build_project_item.dispose()  if @build_project_item && !@build_project_item.isDisposed
    @deploy_project_item.dispose() if @deploy_project_item && !@deploy_project_item.isDisposed
    @changeoptions_item.dispose()  if @changeoptions_item && !@changeoptions_item.isDisposed
    @watching_dir = nil
    @tray_item.image = @standby_icon
  end

end

