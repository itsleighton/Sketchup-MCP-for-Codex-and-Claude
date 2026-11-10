# Identifies which AI app is on the other end of an MCP connection.
#
# Claude and Codex each start their own copy of the connector (sketchup-mcp.exe),
# and requests carry no app name. Windows does know which process owns each TCP
# connection, so for a newly accepted client socket we:
#   1. look up the process that owns the client end (GetExtendedTcpTable), then
#   2. walk up its parent processes (Toolhelp32 snapshot) until we find a known app.
# Results are cached per client process. Any failure returns 'Unknown' and never
# raises, so identification can't break request handling. Windows only.

require 'fiddle'

module SU_MCP
  module ClientIdentity
    # Process names (lower case) of the apps that start the connector.
    KNOWN_APPS = {
      'claude.exe' => 'Claude',
      'codex.exe'  => 'Codex'
    }.freeze
    CONNECTOR_EXE = 'sketchup-mcp.exe'.freeze
    MAX_DEPTH     = 10
    CACHE_TTL     = 600 # seconds

    AF_INET                 = 2
    TCP_TABLE_OWNER_PID_ALL = 5
    TH32CS_SNAPPROCESS      = 0x2
    ERROR_INSUFFICIENT_BUFFER = 122

    @cache = {}
    @api = nil

    class << self
      # Returns 'Claude', 'Codex', 'Other (name.exe)' or 'Unknown'.
      def label_for(sock)
        return 'Unknown' unless windows?
        client_port = sock.peeraddr(false)[1].to_i
        server_port = sock.addr(false)[1].to_i
        pid = pid_for_connection(client_port, server_port)
        return 'Unknown' unless pid
        label_for_pid(pid)
      rescue StandardError, ScriptError
        'Unknown'
      end

      # Label for a process id (cached).
      def label_for_pid(pid)
        hit = @cache[pid]
        return hit[:label] if hit && Time.now - hit[:at] < CACHE_TTL
        label = classify(ancestor_names(pid))
        @cache[pid] = { label: label, at: Time.now }
        label
      rescue StandardError, ScriptError
        'Unknown'
      end

      # Process names from pid upward, e.g.
      # ["python.exe", "python.exe", "sketchup-mcp.exe", "claude.exe", ...]
      def ancestor_names(pid)
        procs = process_table
        names = []
        seen = {}
        current = pid
        MAX_DEPTH.times do
          break if current.nil? || current.zero? || seen[current]
          seen[current] = true
          info = procs[current]
          break unless info
          names << info[:name].downcase
          current = info[:parent]
        end
        names
      end

      # Process id that owns the client end of a connection to server_port.
      def pid_for_connection(client_port, server_port)
        tcp_rows.each do |row|
          return row[:pid] if row[:local_port] == client_port && row[:remote_port] == server_port
        end
        nil
      end

      private

      def windows?
        !!(RUBY_PLATFORM =~ /mswin|mingw|cygwin/)
      end

      def classify(names)
        names.each do |n|
          return KNOWN_APPS[n] if KNOWN_APPS.key?(n)
        end
        idx = names.index(CONNECTOR_EXE)
        if idx && names[idx + 1]
          "Other (#{names[idx + 1]})"
        else
          'Unknown'
        end
      end

      def api
        @api ||= begin
          iphlp = Fiddle.dlopen('iphlpapi.dll')
          k32   = Fiddle.dlopen('kernel32.dll')
          vp = Fiddle::TYPE_VOIDP
          i  = Fiddle::TYPE_INT
          {
            tcp:   Fiddle::Function.new(iphlp['GetExtendedTcpTable'], [vp, vp, i, i, i, i], i),
            snap:  Fiddle::Function.new(k32['CreateToolhelp32Snapshot'], [i, i], vp),
            first: Fiddle::Function.new(k32['Process32FirstW'], [vp, vp], i),
            nxt:   Fiddle::Function.new(k32['Process32NextW'], [vp, vp], i),
            close: Fiddle::Function.new(k32['CloseHandle'], [vp], i)
          }
        end
      end

      # IPv4 TCP connections with owning process ids.
      def tcp_rows
        size = [0].pack('L')
        api[:tcp].call(nil, size, 0, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0)
        3.times do
          n = size.unpack('L')[0]
          return [] if n.zero?
          # Binary (byte-indexed) buffer: Windows writes raw bytes into it.
          buf = ("\0" * (n + 1024)).force_encoding(Encoding::BINARY)
          size = [buf.bytesize].pack('L')
          rc = api[:tcp].call(buf, size, 0, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0)
          next if rc == ERROR_INSUFFICIENT_BUFFER
          return [] unless rc.zero?
          count = buf[0, 4].unpack('L')[0]
          rows = []
          count.times do |k|
            # MIB_TCPROW_OWNER_PID: state, localAddr, localPort, remoteAddr, remotePort, pid
            f = buf[4 + k * 24, 24].unpack('L6')
            rows << { local_port: net_port(f[2]), remote_port: net_port(f[4]), pid: f[5] }
          end
          return rows
        end
        []
      end

      # Ports are stored in network byte order in the low 16 bits.
      def net_port(v)
        ((v & 0xFF) << 8) | ((v >> 8) & 0xFF)
      end

      # pid => { parent:, name: } for all running processes.
      def process_table
        ptr = Fiddle::SIZEOF_VOIDP
        align = ->(o, a) { (o + a - 1) / a * a }
        heap_off   = align.call(12, ptr)
        module_off = heap_off + ptr
        parent_off = module_off + 8
        exe_off    = parent_off + 12
        entry_size = align.call(exe_off + 520, ptr)

        handle = api[:snap].call(TH32CS_SNAPPROCESS, 0)
        h = handle.to_i
        return {} if h.zero? || h == -1 || h == (2**(ptr * 8)) - 1
        table = {}
        begin
          entry = ("\0" * entry_size).force_encoding(Encoding::BINARY)
          entry[0, 4] = [entry_size].pack('L')
          ok = api[:first].call(handle, entry)
          while ok != 0
            pid    = entry[8, 4].unpack('L')[0]
            parent = entry[parent_off, 4].unpack('L')[0]
            chars  = entry[exe_off, 520].unpack('v*')
            len    = chars.index(0) || chars.length
            table[pid] = { parent: parent, name: chars[0, len].pack('U*') }
            entry[0, 4] = [entry_size].pack('L')
            ok = api[:nxt].call(handle, entry)
          end
        ensure
          api[:close].call(handle)
        end
        table
      end
    end
  end
end
