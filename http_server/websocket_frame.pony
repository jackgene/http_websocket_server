use "buffered"

// TODO TextContinuation, BinaryContinuation

class val Text
  let payload: String val

  new val create(payload': String) =>
    """
    TODO Arguably should be partial, as input of length > 2^63 bytes is illegal
    """
    payload = payload'

  fun val encode(): Array[(String val | Array[U8 val] val)] val =>
    _WebSocketFrame.encode(0b1000_0001, payload)

class val Binary
  let payload: Array[U8 val] val

  new val create(payload': Array[U8 val] val) =>
    """
    TODO Arguably should be partial, as input of length > 2^63 bytes is illegal
    """
    payload = payload'

  fun val encode(): Array[(String val | Array[U8 val] val)] val =>
    _WebSocketFrame.encode(0b1000_0010, payload)

class val Close
  let status: (CloseStatus val | None)

  new val create(status_code: U16 = 1000) =>
    status = CloseStatus(status_code)

  new val with_reason(status_code: U16 = 1000, reason: String val)? =>
    status = CloseStatus.with_reason(status_code, reason)?

  new val empty() =>
    status = None

  fun val encode(): Array[(String val | Array[U8 val] val)] val =>
    let payload: Array[U8 val] val =
      match status
      | let s: CloseStatus =>
        let buffer: Array[U8 val] iso =
          [U8.from[U16](s.code.shr(8)); U8.from[U16](s.code and 0xFF)]
        match s.reason
        | let reason: String => buffer.append(reason.array())
        end
        consume buffer
      | None => []
      end
    _WebSocketFrame.encode(0b1000_1000, payload)

class val CloseStatus
  let code: U16
  let reason: (String val | None)

  new val create(code': U16) =>
    code = code'
    reason = None

  new val with_reason(code': U16, reason': String val)? =>
    // All control frames MUST have a payload length of 125-bytes or less.
    // Status code uses 2 of those bytes, leaving up to 123-bytes for reason.
    // https://www.rfc-editor.org/rfc/rfc6455#section-5.5
    if reason'.size() > 123 then error end
    code = code'
    reason = reason'

class val Ping
  let payload: Array[U8 val] val

  new val create() =>
    payload = []

  new val with_payload(payload': Array[U8 val] val)? =>
    // All control frames MUST have a payload length of 125 bytes
    // or less and MUST NOT be fragmented.
    // https://www.rfc-editor.org/rfc/rfc6455#section-5.5
    if payload'.size() > 125 then error end
    payload = payload'

  fun val encode(): Array[(String val | Array[U8 val] val)] val =>
    _WebSocketFrame.encode(0b1000_1001, payload)

class val Pong
  let payload: Array[U8 val] val

  new val create() =>
    payload = []

  new val with_payload(payload': Array[U8 val] val)? =>
    // All control frames MUST have a payload length of 125 bytes
    // or less and MUST NOT be fragmented.
    // https://www.rfc-editor.org/rfc/rfc6455#section-5.5
    if payload'.size() > 125 then error end
    payload = payload'

  fun val encode(): Array[(String val | Array[U8 val] val)] val =>
    _WebSocketFrame.encode(0b1000_1010, payload)

type WebSocketFrame is (Text | Binary | Close | Ping | Pong)

primitive _WebSocketFrame
  fun encode(
    header: U8, payload: (String val | Array[U8 val] val)
  ): Array[(String val | Array[U8 val] val)] val =>
    let writer: Writer = Writer

    writer.u8(header)

    var payload_len = payload.size()
    if payload_len < 126 then
      writer.u8(U8.from[USize](payload_len))
    elseif payload_len < 65536 then
      writer.u8(126)
      writer.u16_be(U16.from[USize](payload_len))
    else
      writer.u8(127)
      writer.u64_be(U64.from[USize](payload_len))
    end
    writer.write(payload)

    writer.done()
