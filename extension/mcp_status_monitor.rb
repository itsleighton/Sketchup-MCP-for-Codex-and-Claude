# MCP Status Monitor
# Live status light for the Sketchup MCP Server.
#
# WHY A PANEL AND NOT A TOOLBAR ICON:
# On SketchUp 26.1 a toolbar button never repaints after creation.
#   - UI::Command#small_icon= accepts a new path silently; the button keeps
#     the bitmap it was built with.
#   - The validation proc IS called continuously (verified), but returning
#     MF_CHECKED or MF_GRAYED produces no visible change.
# Both were tested on this machine and neither works. The only thing that
# reliably redraws is an HtmlDialog, so the status light lives there.
# The toolbar button's single job is to open the panel.
#
# Does not modify su_mcp. Activity is tracked by prepending a wrapper around
# SU_MCP::Server#handle_jsonrpc_request. su_mcp closes the client socket
# after each response, so ACTIVE means "a request arrived within
# ACTIVE_WINDOW seconds", not "a client is attached".

require 'sketchup.rb'

module ElmMCPStatus

  DIR           = File.join(File.dirname(__FILE__), 'mcp_status_monitor') unless defined?(DIR)
  ACTIVE_WINDOW = 120 unless defined?(ACTIVE_WINDOW)
  UI_VERSION    = 2   unless defined?(UI_VERSION)
  PANEL_W       = 125 unless defined?(PANEL_W)
  PANEL_H       = 56  unless defined?(PANEL_H)

  @cmd_status    ||= nil
  @cmd_info      ||= nil
  @toolbar       ||= nil
  @ui_version    ||= nil
  @dlg           ||= nil
  @panel_timer   ||= nil
  @panel_size    ||= nil
  @boot_timer    ||= nil
  @boot_tries    ||= 0
  @last_activity ||= nil
  @last_method   ||= nil
  @request_count ||= 0
  @patched       ||= false

  def self.icon(name)
    File.join(DIR, name)
  end

  # --- activity tracking -------------------------------------------------

  def self.note_activity(request)
    @last_activity = Time.now
    @request_count = @request_count.to_i + 1
    @last_method = begin
      if request.is_a?(Hash)
        m  = request["method"] || request[:method]
        nm = (request["params"] || {})["name"] rescue nil
        nm ? "#{m}:#{nm}" : m
      end
    rescue
      nil
    end
  rescue
    nil
  end

  def self.seconds_since_activity
    @last_activity.nil? ? nil : (Time.now - @last_activity)
  end

  def self.request_count
    @request_count.to_i
  end

  def self.last_method
    @last_method
  end

  def self.patched?
    @patched
  end

  module ActivityTracker
    def handle_jsonrpc_request(request)
      ElmMCPStatus.note_activity(request)
      super
    end
    private :handle_jsonrpc_request
  end

  def self.ensure_patched
    return true if @patched
    return false unless defined?(::SU_MCP) && defined?(::SU_MCP::Server)
    unless ::SU_MCP::Server.ancestors.include?(ActivityTracker)
      ::SU_MCP::Server.prepend(ActivityTracker)
    end
    @patched = true
  rescue
    @patched = false
  end

  # --- server state ------------------------------------------------------

  def self.server_instance
    return nil unless defined?(::SU_MCP) && defined?(::SU_MCP::Server)
    found = nil
    ObjectSpace.each_object(::SU_MCP::Server) { |o| found = o; break }
    found
  rescue
    nil
  end

  # :active | :listening | :stopped | :missing
  def self.state
    srv = server_instance
    return :missing if srv.nil?
    running = srv.instance_variable_get(:@running)
    sock    = srv.instance_variable_get(:@server)
    closed  = begin
                sock.nil? ? true : sock.closed?
              rescue
                true
              end
    return :stopped unless running && !closed
    age = seconds_since_activity
    (age && age <= ACTIVE_WINDOW) ? :active : :listening
  end

  def self.port
    srv = server_instance
    (srv && srv.instance_variable_get(:@port)) || 9876
  end

  def self.ago_text
    age = seconds_since_activity
    return "no requests yet" if age.nil?
    a = age.round
    return "#{a}s ago" if a < 60
    return "#{(a / 60).round}m ago" if a < 3600
    "#{(a / 3600.0).round(1)}h ago"
  end

  def self.headline(s = state)
    case s
    when :active    then "ACTIVE"
    when :listening then "LISTENING"
    when :stopped   then "STOPPED"
    else                 "NOT LOADED"
    end
  end

  # Kept short deliberately: the panel is ~125px wide.
  def self.subline(s = state)
    case s
    when :active    then ":#{port} - #{ago_text}"
    when :listening then ":#{port} - idle"
    when :stopped   then "not listening"
    else                 "extension absent"
    end
  end

  def self.label(s = state)
    "MCP #{headline(s)} - #{subline(s)}"
  end

  # --- status panel ------------------------------------------------------

  def self.html
    css = <<-CSS
      :root { color-scheme: dark; }
      body { margin:0; font-family:"Segoe UI",system-ui,sans-serif;
             background:#1e2127; color:#e6e6e6; user-select:none;
             padding:7px 9px; overflow:hidden; }
      .row { display:flex; align-items:center; gap:7px; }
      #dot { width:13px; height:13px; border-radius:50%;
             background:#6E6E6E; flex:0 0 auto; }
      #dot.active    { background:#19C463; animation:pulse 1.6s infinite; }
      #dot.listening { background:#E8A317; }
      #dot.stopped   { background:#E5484D; }
      #dot.missing   { background:#6E6E6E; }
      @keyframes pulse {
        0%   { box-shadow:0 0 0 0 rgba(25,196,99,.65); }
        70%  { box-shadow:0 0 0 6px rgba(25,196,99,0); }
        100% { box-shadow:0 0 0 0 rgba(25,196,99,0); }
      }
      #head { font-size:11px; font-weight:600; letter-spacing:.3px;
              white-space:nowrap; }
      #sub  { font-size:9px; color:#9aa3ad; margin-top:3px;
              white-space:nowrap; }
      button { margin-top:5px; font-size:9px; padding:2px 7px;
               background:#2d333d; color:#e6e6e6;
               border:1px solid #434c58; border-radius:3px; cursor:pointer; }
      button:hover { background:#39414d; }
      .hide { display:none; }
    CSS

    js = <<-JS
      window.setState = function(s, head, sub, meta, canStart) {
        document.getElementById('dot').className = s;
        document.getElementById('head').textContent = head;
        document.getElementById('sub').textContent  = sub;
        // Full detail lives in the hover tooltip; no room for it on screen.
        document.body.title = meta;
        document.getElementById('startbtn').className = canStart ? '' : 'hide';
      };
      document.getElementById('startbtn').onclick = function() {
        sketchup.start_server();
      };
      if (window.sketchup && sketchup.ready) { sketchup.ready(); }
    JS

    body = '<div class="row"><div id="dot"></div><div>' \
           '<div id="head">...</div><div id="sub"></div></div></div>' \
           '<button id="startbtn" class="hide">Start server</button>'

    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>#{css}</style>" \
    "</head><body>#{body}<script>#{js}</script></body></html>"
  end

  def self.push_update
    # Retried here every tick: on a cold start this file loads before
    # su_mcp.rb, so SU_MCP::Server does not exist yet and the tracking
    # hook cannot attach until it does. Cheap -- returns immediately
    # once attached.
    ensure_patched
    return unless @dlg
    vis = begin
            @dlg.visible?
          rescue
            false
          end
    return unless vis
    s = state
    meta = "MCP #{headline(s)} on port #{port}\n"
    meta += "#{request_count} requests handled, last #{ago_text}"
    meta += "\nlast method: #{last_method}" if last_method
    meta += "\nTRACKING NOT ATTACHED" unless @patched
    @dlg.execute_script(
      "window.setState(#{s.to_s.inspect},#{headline(s).inspect}," \
      "#{subline(s).inspect},#{meta.inspect},#{(s == :stopped).inspect});"
    )
    # Grow only when the Start button needs room, shrink back otherwise.
    want = (s == :stopped) ? [PANEL_W, PANEL_H + 28] : [PANEL_W, PANEL_H]
    if want != @panel_size
      @panel_size = want
      begin
        @dlg.set_size(want[0], want[1])
      rescue
      end
    end
  rescue
    nil
  end

  def self.stop_panel_timer
    UI.stop_timer(@panel_timer) if @panel_timer
    @panel_timer = nil
  rescue
    @panel_timer = nil
  end

  def self.show_panel
    ensure_patched
    already = begin
                @dlg && @dlg.visible?
              rescue
                false
              end
    if already
      @dlg.bring_to_front
      push_update
      return
    end

    @dlg = UI::HtmlDialog.new(
      dialog_title:    "MCP",
      preferences_key: "ElmMCPStatusPanel",
      scrollable:      false,
      resizable:       true,
      width:           PANEL_W,
      height:          PANEL_H,
      min_width:       100,
      min_height:      46,
      style:           UI::HtmlDialog::STYLE_UTILITY
    )
    @dlg.set_html(html)
    @dlg.add_action_callback("ready") { |_c| push_update; nil }
    @dlg.add_action_callback("start_server") { |_c|
      begin
        srv = server_instance
        srv.start if srv
      rescue => e
        UI.messagebox("Could not start the server:\n#{e.message}")
      end
      push_update
      nil
    }
    @dlg.set_on_closed { ElmMCPStatus.stop_panel_timer }
    @dlg.show
    # preferences_key restores a remembered size that overrides the
    # constructor values, so clamp it back down after showing.
    @panel_size = [PANEL_W, PANEL_H]
    begin
      @dlg.set_size(PANEL_W, PANEL_H)
    rescue
    end

    stop_panel_timer
    @panel_timer = UI.start_timer(1.0, true) { ElmMCPStatus.push_update }
    push_update
  end

  def self.details_text
    srv = server_instance
    out = [label, "-" * 46]
    if srv
      sock = srv.instance_variable_get(:@server)
      ss = begin
             sock.nil? ? "none" : (sock.closed? ? "closed" : "open (listening)")
           rescue
             "unreadable"
           end
      out << "Port:              #{srv.instance_variable_get(:@port).inspect}"
      out << "Running:           #{srv.instance_variable_get(:@running).inspect}"
      out << "Socket:            #{ss}"
      out << "Timer:             #{srv.instance_variable_get(:@timer_id).inspect}"
      out << ""
      out << "Activity tracking: #{@patched ? 'attached' : 'NOT attached'}"
      out << "Requests handled:  #{request_count}"
      out << "Last request:      #{ago_text}"
      out << "Last method:       #{last_method || '-'}"
    else
      out << "SU_MCP::Server was not found in memory."
    end
    out.join("\n")
  end

  ensure_patched

  if @ui_version != UI_VERSION
    @cmd_status = UI::Command.new("MCP Status") { ElmMCPStatus.show_panel }
    @cmd_status.small_icon      = icon('mcp_plug.svg')
    @cmd_status.large_icon      = icon('mcp_plug.svg')
    @cmd_status.tooltip         = "Open the MCP status light"
    @cmd_status.status_bar_text = "Open the MCP status light"

    @cmd_info = UI::Command.new("MCP Info") { UI.messagebox(ElmMCPStatus.details_text) }
    @cmd_info.small_icon      = icon('mcp_info.svg')
    @cmd_info.large_icon      = icon('mcp_info.svg')
    @cmd_info.tooltip         = "MCP server details"
    @cmd_info.status_bar_text = "Show MCP server details"

    @toolbar = UI::Toolbar.new("MCP")
    @toolbar.add_item(@cmd_status)
    @toolbar.add_item(@cmd_info)
    @toolbar.restore
    @ui_version = UI_VERSION
  end

  # Attach the tracking hook as soon as su_mcp finishes loading, whether or
  # not the panel is ever opened. Stops itself once attached, or gives up
  # after ~60s so it never polls forever.
  def self.start_boot_watch
    return if @boot_timer
    @boot_tries = 0
    @boot_timer = UI.start_timer(1.0, true) do
      @boot_tries = @boot_tries.to_i + 1
      if ensure_patched || @boot_tries > 60
        begin
          UI.stop_timer(@boot_timer)
        rescue
        end
        @boot_timer = nil
      end
    end
  rescue
    @boot_timer = nil
  end

  start_boot_watch

  # Open the light automatically so it is there after a restart.
  UI.start_timer(1.0, false) { ElmMCPStatus.show_panel rescue nil }

end
