trait WebSocketHandler
  """
  Interface implemented by the application to handle WebSocket events.
  """
  fun box _session(): WebSocketSession
    """
    The current websocket session, to be set by application at initialization
    """
  
  fun ref text_received(payload: String) =>
    """
    Received a text frame.
    """

  fun ref binary_received(payload: Array[U8 val] val) =>
    """
    Received a binary frame.
    """

  fun ref close_received(status: (CloseStatus | None)) =>
    """
    Received a close frame.
    """
    _session().dispose()

  fun ref ping_received(payload: Array[U8 val] val) =>
    """
    Received a ping frame.
    """
    try
      // If the payload fits in the incoming Ping, it will _always_ fit in a Pong
      // TODO think of a way to do this without being partial, perhaps:
      // `Pong.from_ping(Ping)`
      _session().send_frame(Pong.with_payload(payload)?)
    end

  fun ref pong_received(payload: Array[U8 val] val) =>
    """
    Received a pong frame.
    """

  fun ref failed(reason: WebSocketDecodeError) =>
    """
    Notification about failure decoding a WebSocket frame.
    """

  fun ref closed() =>
    """
    Notification that the underlying connection has been closed.
    """

  fun ref throttled() =>
    """
    Notification that the session temporarily can not accept more data.
    """

  fun ref unthrottled() =>
    """
    Notification that the session can resume accepting data.
    """


interface WebSocketHandlerFactory
  """
  Creates `WebSocketHandler` instances.
  """
  fun apply(session: WebSocketSession): WebSocketHandler ref^
