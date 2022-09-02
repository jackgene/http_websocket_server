use "net"
use "collections"
use "crypto"
use "encode/base64"
use "valbytes"
use "debug"

actor _ServerConnection is (Session & WebSocketSession)
  """
  Manages a stream of requests coming into a server from a single client,
  dispatches those request to a back-end, and returns the responses back
  to the client.

  """
  var _protocol: (_HTTPServerConnectionProtocol | _WebSocketServerConnectionProtocol)
  let _config: ServerConfig
  let _conn: TCPConnection
  let _timeout: _ServerConnectionTimeout = _ServerConnectionTimeout

  new create(
    handlermaker: HandlerFactory val,
    config: ServerConfig,
    conn: TCPConnection)
  =>
    """
    Create a connection actor to manage communication with to a new
    client. We also create an instance of the application's back-end
    handler that will process incoming requests.

    We always start with HTTP/1.x, and upgrade if necessary.
    """
    _protocol = _HTTPServerConnectionProtocol(
      handlermaker(this), config, conn, _timeout)
    _config = config
    _conn = conn

  be received(data: Array[U8] iso) =>
    _protocol.received(consume data)

  be closed() =>
    """
    Notification that the underlying connection has been closed.
    """
    _protocol.closed()

  be throttled() =>
    """
    TCP connection can not accept data for a while.
    """
    _protocol.throttled()

  be unthrottled() =>
    """
    TCP connection can not accept data for a while.
    """
    _protocol.unthrottled()

//// SEND RESPONSE API ////
//// STANDARD API

  be send_start(response: Response val, request_id: RequestID) =>
    """
    Initiate transmission of the HTTP Response message for the current
    Request.
    """
    match _protocol
    | let http: _HTTPServerConnectionProtocol =>
      http._send_start(response, request_id)
    else
      Debug("Unable to send HTTP response on upgraded protocol")
    end

  be send_chunk(data: ByteSeq val, request_id: RequestID) =>
    """
    Write low level outbound raw byte stream.
    """
    match _protocol
    | let http: _HTTPServerConnectionProtocol =>
      http._send_chunk(data, request_id)
    else
      Debug("Unable to send HTTP response on upgraded protocol")
    end

  be send_finished(request_id: RequestID) =>
    """
    We are done sending a response. We close the connection if
    `keepalive` was not requested.
    """
    match _protocol
    | let http: _HTTPServerConnectionProtocol =>
      http._send_finished(request_id)
    else
      Debug("Unable to send HTTP response on upgraded protocol")
    end

  be send_cancel(request_id: RequestID) =>
    """
    Cancel the current response.

    TODO: keep this???
    """
    match _protocol
    | let http: _HTTPServerConnectionProtocol =>
      http._cancel(request_id)
    else
      Debug("Unable to send HTTP response on upgraded protocol")
    end

//// CONVENIENCE API

  be send_no_body(response: Response val, request_id: RequestID) =>
    """
    Start and finish sending a response without a body.

    This function calls `send_finished` for you, so no need to call it yourself.
    """
    match _protocol
    | let http: _HTTPServerConnectionProtocol =>
      http._send_start(response, request_id)
      http._send_finished(request_id)
    else
      Debug("Unable to send HTTP response on upgraded protocol")
    end

  be send(response: Response val, body: ByteArrays, request_id: RequestID) =>
    """
    Start and finish sending a response with body.
    """
    match _protocol
    | let http: _HTTPServerConnectionProtocol =>
      http._send(response, body, request_id)
    else
      Debug("Unable to send HTTP response on upgraded protocol")
    end

//// OPTIMIZED API

  be send_raw(raw: ByteSeqIter, request_id: RequestID, close_session: Bool = false) =>
    """
    If you have your response already in bytes, and don't want to build an expensive
    [Response](http_server-Response) object, use this method to send your [ByteSeqIter](builtin-ByteSeqIter).
    This `raw` argument can contain only the response without body,
    in which case you can send the body chunks later on using `send_chunk`,
    or, to further optimize your writes to the network, it might already contain
    the response body.

    If the session should be closed after sending this response,
    no matter the requested standard HTTP connection handling,
    set `close_session` to `true`. To be a good HTTP citizen, include
    a `Connection: close` header in the raw response, to signal to the client
    to also close the session.
    If set to `false`, then normal HTTP connection handling applies
    (request `Connection` header, HTTP/1.0 without `Connection: keep-alive`, etc.).

    In each case, finish sending your raw response using `send_finished`.
    """
    match _protocol
    | let http: _HTTPServerConnectionProtocol =>
      http._send_raw(raw, request_id, close_session)
    else
      Debug("Unable to send HTTP response on upgraded protocol")
    end

//// WebSocket API

  be upgrade_to_websocket(request: Request val, request_id: RequestID, handlermaker: WebSocketHandlerFactory val) =>
    """
    Upgrades connection to WebSocket.
    """
    match _protocol
    | let http: _HTTPServerConnectionProtocol =>
      try
        http._send_raw(_websocket_handshake(request)?, request_id)
        _protocol = _WebSocketServerConnectionProtocol(
          handlermaker(this), _config, _conn, _timeout)
      else
        let body = "Please upgrade to websocket/13"
        let response = Responses.builder()
          .set_status(StatusUpgradeRequired)
          .add_header("Content-Type", "text/plain")
          .add_header("Content-Length", body.size().string())
          .add_header("Connection", "Upgrade")
          .add_header("Upgrade", "websocket")
          .add_header("sec-websocket-version", "13")
          .finish_headers()
          .add_chunk(body.array())
          .build()
        http._send_raw(response, RequestIDs.next(request_id))
        http._send_finished(request_id)
      end
    else
      Debug("Unable to send HTTP response on upgraded protocol")
    end

  fun _websocket_handshake(request: Request val): ByteSeqIter val ? =>
    match (
      request.header("sec-websocket-version"),
      request.header("sec-websocket-key"),
      request.header("upgrade"),
      request.header("connection")
    )
    | (
        let version: String,
        let request_key: String,
        let upgrade: String,
        let connection: String
      )
      if (version == "13") and (upgrade.lower() == "websocket") =>

      var conn_upgrade = false
      for s in connection.split_by(",").values() do
        if s.lower().>strip(" ") == "upgrade" then
          conn_upgrade = true
          break
        end
      end
      if not conn_upgrade then error end

      Responses.builder()
        .set_status(StatusSwitchingProtocols)
        .add_header("Connection", "Upgrade")
        .add_header("Upgrade", "websocket")
        .add_header("Sec-WebSocket-Accept", _websocket_accept_key(request_key))
        .finish_headers()
        .build()
    else
      error
    end

  fun _websocket_accept_key(key: String): String =>
    let c = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    let digest = Digest.sha1()
    try
      digest.append(consume c)?
    end
    let d = digest.final()
    Base64.encode(d)

  be send_text(text: String) =>
    """
    """
    _send_websocket_frame(WebSocketFrame.text(text))
  
  be send_binary(data: Array[U8 val] val) =>
    """
    """
    _send_websocket_frame(WebSocketFrame.binary(data))

  be send_close(code: U16 = 1000) =>
    """
    """
    _send_websocket_frame(WebSocketFrame.close(code))

  be send_ping(data: Array[U8 val] val) =>
    """
    """
    _send_websocket_frame(WebSocketFrame.ping(data))

  be send_pong(data: Array[U8 val] val) =>
    """
    """
    _send_websocket_frame(WebSocketFrame.pong(data))

  fun ref _send_websocket_frame(frame: WebSocketFrame) =>
    _timeout.reset()
    _conn.unmute()
    _conn.writev(frame.build())

//// Connection Management

  be dispose() =>
    """
    Close the connection from the server end.
    """
    _conn.dispose()

  be _mute() =>
    _conn.mute()

  be _unmute() =>
    _conn.unmute()

//// Timeout API

  be _heartbeat(current_seconds: I64) =>
    let timeout = _config.connection_timeout.i64()
    //Debug("current_seconds=" + current_seconds.string() + ", last_activity=" + _timeout._last_activity_ts.string())
    if (timeout > 0) and ((current_seconds - _timeout.last_activity_ts()) >= timeout) then
      //Debug("Connection timed out.")
      // backend is notified asynchronously when the close happened
      dispose()
    end
