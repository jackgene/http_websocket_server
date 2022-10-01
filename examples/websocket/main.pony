use "../../http_server"
use "net"
use "valbytes"
use "debug"

actor Main
  """
  A simple HTTP server, that responds with a simple "hello world" in the response body.
  """
  new create(env: Env) =>
    for arg in env.args.values() do
      if (arg == "-h") or (arg == "--help") then
        _print_help(env)
        return
      end
    end

    let port = try env.args(1)? else "9292" end
    let limit = try env.args(2)?.usize()? else 10000 end
    let host = "localhost"

    // Start the top server control actor.
    let server = Server(
      TCPListenAuth(env.root),
      LoggingServerNotify(env),  // notify for server lifecycle events
      BackendMaker // factory for session-based application backend
      where config = ServerConfig( // configuration of Server
        where host' = host,
              port' = port,
              max_concurrent_connections' = limit)
    )

  fun _print_help(env: Env) =>
    env.err.print(
      """
      Usage:

         hello_world [<PORT> = 9292] [<MAX_CONCURRENT_CONNECTIONS> = 10000]

      """
    )


class LoggingServerNotify is ServerNotify
  """
  Notification class that is notified about
  important lifecycle events for the Server
  """
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref listening(server: Server ref) =>
    """
    Called when the Server starts listening on its host:port pair via TCP.
    """
    try
      (let host, let service) = server.local_address().name()?
      _env.err.print("connected: " + host + ":" + service)
    else
      _env.err.print("Couldn't get local address.")
      _env.exitcode(1)
      server.dispose()
    end

  fun ref not_listening(server: Server ref) =>
    """
    Called when the Server was not able to start listening on its host:port pair via TCP.
    """
    _env.err.print("Failed to listen.")
    _env.exitcode(1)

  fun ref closed(server: Server ref) =>
    """
    Called when the Server is closed.
    """
    _env.err.print("Shutdown.")

class val BackendMaker
  fun apply(session: Session): Handler ref^ =>
    BackendHandler(session)

class BackendHandler is Handler
  let _session: Session

  new ref create(session: Session) =>
    _session = session

  fun ref apply(request: Request val, request_id: RequestID) =>
    let listener_factory: WebSocketHandlerFactory val =
      { (session: WebSocketSession): WebSocketHandler ref^ =>
        session.send_frame(Text("Welcome to the echo service!"))
        object ref is WebSocketHandler
          fun box current_session(): WebSocketSession => session

          fun ref text_received(payload: String) =>
            session.send_frame(Text(payload))
            try
              session.send_frame(Ping.with_payload(payload.array())?)
            end

          fun ref binary_received(payload: Array[U8 val] val) =>
            session.send_frame(Binary(payload))
            try
              session.send_frame(Ping.with_payload(payload)?)
            end

          fun ref close_received(status: (CloseStatus | None)) =>
            match status
            | let s: CloseStatus => Debug(
                "Received close frame with status " + s.code.string() +
                match s.reason
                | let reason: String => " " + reason
                else ""
                end
              )
            else Debug("Received close frame with no status")
            end
            session.dispose()

          fun ref ping_received(payload: Array[U8 val] val) =>
            Debug("Received WebSocket ping: " + String.from_array(payload))

          fun ref pong_received(payload: Array[U8 val] val) =>
            Debug("Received WebSocket pong: " + String.from_array(payload))
        end
      }
    _session.upgrade_to_websocket(request, request_id, listener_factory)

  fun ref finished(request_id: RequestID) => None
