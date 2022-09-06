trait tag WebSocketSession
  """
  Represents a single WebSocket connection, and is used by a
  `WebSocketHandler` to send frames to the client.
  """
  be send_text(text: String) =>
    """
    Sends a text frame.
    """

  be send_binary(data: Array[U8 val] val) =>
    """
    Sends a binary frame.
    """

  be send_close(code: U16 = 1000) =>
    """
    Sends a close request frame.
    """

  be send_ping(data: Array[U8 val] val) =>
    """
    Sends a ping frame.
    """

  be send_pong(data: Array[U8 val] val) =>
    """
    Sends a pong frame.
    """
