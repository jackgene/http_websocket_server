interface WebSocketHandler
  """
  Interface implemented by the application to handle WebSocket events.
  """
  fun ref text_received(text: String) =>
    None

  fun ref binary_received(data: Array[U8 val] val) =>
    None

  fun ref close_received(code: U16) =>
    None

  fun ref ping_received(data: Array[U8 val] val) =>
    None

  fun ref pong_received(data: Array[U8 val] val) =>
    None


interface WebSocketHandlerFactory
  """
  Creates `WebSocketHandler` instances.
  """
  fun apply(session: WebSocketSession): WebSocketHandler ref^
