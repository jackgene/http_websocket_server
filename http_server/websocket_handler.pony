interface WebSocketHandler
  """
  Interface implemented by the application to handle WebSocket events.
  """
  fun ref text_received(text: String) =>
    """
    Received a text frame.
    """

  fun ref binary_received(data: Array[U8 val] val) =>
    """
    Received a binary frame.
    """

  fun ref close_received(code: U16) =>
    """
    Received a close frame.
    """

  fun ref ping_received(data: Array[U8 val] val) =>
    """
    Received a ping frame.
    """

  fun ref pong_received(data: Array[U8 val] val) =>
    """
    Received a pong frame.
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
