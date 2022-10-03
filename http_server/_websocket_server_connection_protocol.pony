use "net"
use "buffered"
use "debug"

class _WebSocketServerConnectionProtocol is _ServerConnectionProtocol
  let _backend: WebSocketHandler
  let _config: ServerConfig
  let _conn: TCPConnection
  let _timeout: _ServerConnectionTimeout
  let _buffer: Reader = Reader
  var _decode_state: _WebSocketDecodeState ref = _ExpectHeader

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
      while true do
        match _decode_state.decode_part(_buffer)?
        | (let state_none: (_WebSocketDecodeState ref | None), let frame_none: (WebSocketFrame val | None)) =>
          match state_none
          | let state: _WebSocketDecodeState ref =>
            _decode_state = state
          end
          match frame_none
          | let t: Text   => _backend.text_received(t.payload)
          | let b: Binary => _backend.binary_received(b.payload)
          | let c: Close  => _backend.close_received(c.status)
          | let p: Ping   => _backend.ping_received(p.payload)
          | let p: Pong   => _backend.pong_received(p.payload)
          end

        | let err: WebSocketDecodeError =>
          _backend.failed(err)
          _send(
            Close.with_reason(
              match err
              | let _: WebSocketDecodeFrameError => 1002
              | let _: WebSocketDecodePayloadError => 1007
              end,
              match err
              | ErrorNonZeroRSV => "RFC6455 5.2 (RSV1, RSV2, RSV3): MUST be 0 (extension not supported)"
              | ErrorNotMasked => "RFC6455 5.1: a client MUST mask all frames that it sends to the server"
              | ErrorUnsupportedOpCode => "RFC6455 5.2 (Opcode): Unsupported op code"
              | ErrorControlFrameFragmented => "RFC6455 5.5: All control frames MUST NOT be fragmented"
              | ErrorControlFrameTooLarge => "RFC6455 5.5: All control frames MUST have a payload length of 125 bytes or less"
              | ErrorBadPayloadLength => "RFC6455 5.2 (Payload length): the minimal number of bytes MUST be used to encode the length"
              | ErrorMalformedClosePayload => "RFC6455 5.5.1: Malformed close frame"
              | ErrorNonUTF8Text => "RFC6455 5.5.1/5.6: Text of Close frame payload is not UTF-8 encoded"
              end
            )?
          )
          closed()
          _conn.dispose()
          break

        | _NeedMore => break
        end
      end
    else
      _send(Close(1001))
      closed()
      _conn.dispose()
    end

  fun ref closed() =>
    _backend.closed()

  fun ref throttled() =>
    _backend.throttled()

  fun ref unthrottled() =>
    _backend.unthrottled()

  fun ref _send(frame: WebSocketFrame) =>
    _timeout.reset()
    _conn.unmute()
    _conn.writev(frame.encode())
