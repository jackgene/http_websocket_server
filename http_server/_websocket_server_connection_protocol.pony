use "net"
use "buffered"
use "debug"

class _WebSocketServerConnectionProtocol is _ServerConnectionProtocol
  let _backend: WebSocketHandler
  let _config: ServerConfig
  let _conn: TCPConnection
  let _timeout: _ServerConnectionTimeout
  let _buffer: Reader ref = Reader
  let _decoder: _WebSocketDecoder ref = _WebSocketDecoder

  new create(
    backend: WebSocketHandler,
    config: ServerConfig,
    conn: TCPConnection,
    timeout: _ServerConnectionTimeout)
  =>
    _backend = backend
    _config = config
    _conn = conn
    _timeout = timeout

  fun ref received(data: Array[U8] iso) =>
    _timeout.reset()
    _buffer.append(consume data)
    try
      match _decoder.decode(_buffer)?
      | let f: WebSocketFrame val =>
        Debug("decoded a frame")
        match f.opcode
        | Text   => _backend.text_received(f.data as String)
        | Binary => _backend.binary_received(f.data as Array[U8] val)
        | Close  => _backend.close_received(1000)
        | Ping   => _backend.ping_received(f.data as Array[U8] val)
        | Pong   => _backend.pong_received(f.data as Array[U8] val)
        end
      //   _conn.expect(2)? // expect next header
      // | let n: USize =>
      //     // need more data to parse an frame
      //     // notice: if n > read_buffer_size, connection will be closed
      //     _conn.expect(n)?
      end
    else
      // Close connection?
      closed() // TODO Notify failure?
      _conn.dispose()
    end

  fun ref closed() =>
    _backend.closed()

  fun ref throttled() =>
    _backend.throttled()

  fun ref unthrottled() =>
    _backend.unthrottled()

  fun ref _send_websocket_frame(frame: WebSocketFrame) =>
    _timeout.reset()
    _conn.unmute()
    _conn.writev(frame.build())
