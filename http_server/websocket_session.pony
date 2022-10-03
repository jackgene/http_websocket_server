use "valbytes"

trait tag WebSocketSession
  """
  Represents a single WebSocket connection, and is used by a
  `WebSocketHandler` to send frames to the client.
  """
  be send_frame(frame: WebSocketFrame val) =>
    """
    Sends a WebSocket frame.
    """
    None

  be dispose() =>
    """
    Close the connection from this end.
    """
    None
