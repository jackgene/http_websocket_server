use "buffered"

type _Proceed is ((_WebSocketDecodeState ref | None), (WebSocketFrame val | None))

primitive _NeedMore

type _DecodeResult is (
  _Proceed |
  _NeedMore |
  WebSocketDecodeError val)

class val _ExpectHeader
  fun decode_part(input: Reader): _DecodeResult? =>
    if input.size() < 2 then return _NeedMore end
    // These should never fail, as we've already confirmed `input` size
    let first_byte = input.u8()?
    let second_byte = input.u8()?

    // Section 5.2 (RSV1, RSV2, RSV3)
    // MUST be 0 unless an extension is negotiated that defines meanings for non-zero values.
    let rsv = (first_byte and 0b0111_0000).shr(4)
    if rsv != 0 then return ErrorNonZeroRSV end

    // Section 5.2 (Mask)
    // All frames sent from client to server have this bit set to 1.
    let masked = second_byte.shr(7) == 0b1
    if not masked then return ErrorNotMasked end

    let fin = first_byte.shr(7) == 0b1
    let len_code = USize.from[U8](second_byte and 0b0111_1111)

    match first_byte and 0b0000_1111
    // TODO DRY 0x1 and 0x2
    | 0x1 =>
      // TODO implement fragmentation
      if not fin then error end
      match len_code
      | 0 => (None, Text(""))
      | 126 =>
        (_Expect16BitLength({(payload_len: USize): _WebSocketDecodeState ref => _ExpectText(payload_len) }), None)
      | 127 =>
        (_Expect64BitLength({(payload_len: USize): _WebSocketDecodeState ref => _ExpectText(payload_len) }), None)
      | let payload_len: USize => (_ExpectText(payload_len), None)
      end

    | 0x2 =>
      // TODO implement fragmentation
      if not fin then error end
      match len_code
      | 0 => (None, Binary([]))
      | 126 =>
        (_Expect16BitLength({(payload_len: USize): _WebSocketDecodeState ref => _ExpectBinary(payload_len) }), None)
      | 127 =>
        (_Expect64BitLength({(payload_len: USize): _WebSocketDecodeState ref => _ExpectBinary(payload_len) }), None)
      | let payload_len: USize => (_ExpectBinary(payload_len), None)
      end

    | let control: U8 if (control >= 0x8) and (control <= 0xA) =>
      // Section 5.5
      // All control frames MUST have a payload length of 125 bytes or less and MUST NOT be fragmented.
      if not fin then return ErrorControlFrameFragmented end
      if len_code > 125 then return ErrorControlFrameTooLarge end
      match control
      | 0x8 => (_ExpectClose(len_code), None)
      | 0x9 => (_ExpectPing(len_code), None)
      | 0xA => (_ExpectPong(len_code), None)
      else ErrorUnsupportedOpCode
      end

    else ErrorUnsupportedOpCode
    end

class val _Expect16BitLength
  let next_decode_state: _WebSocketDecodeStateFactory

  new create(next_decode_state': _WebSocketDecodeStateFactory) =>
    next_decode_state = next_decode_state'

  fun decode_part(input: Reader): _DecodeResult? =>
    if input.size() < 2 then return _NeedMore end

    let size =  input.u16_be()?

    // Section 5.2 (Payload length)
    // the minimal number of bytes MUST be used to encode the length
    if size <= 125 then return ErrorBadPayloadLength end

    (next_decode_state(USize.from[U16](size)), None)

class val _Expect64BitLength
  let next_decode_state: _WebSocketDecodeStateFactory

  new create(next_decode_state': _WebSocketDecodeStateFactory) =>
    next_decode_state = next_decode_state'

  fun decode_part(input: Reader): _DecodeResult? =>
    if input.size() < 4 then return _NeedMore end

    let size = input.u64_be()?

    // Section 5.2 (Payload length)
    // the minimal number of bytes MUST be used to encode the length
    if size <= 0xffff then return ErrorBadPayloadLength end

    (next_decode_state(USize.from[U64](size)), None)

class val _ExpectText
  let _payload_len: USize

  new create(payload_len: USize) =>
    _payload_len = payload_len

  fun decode_part(input: Reader): _DecodeResult? =>
    if input.size() < (_payload_len + 4) then return _NeedMore end

    let payload = _WebSocketDecodeHelper.unmask_payload(input, _payload_len)?
    // Section 5.6 (Text)
    // The "Payload data" is text data encoded as UTF-8.
    let payload_utf8 =
      try
        UTF8.from_array(consume payload)? as String
      else return ErrorNonUTF8Text end
    (_ExpectHeader, Text(payload_utf8))

class val _ExpectBinary
  let _payload_len: USize

  new create(payload_len: USize) =>
    _payload_len = payload_len

  fun decode_part(input: Reader): _DecodeResult? =>
    if input.size() < (_payload_len + 4) then return _NeedMore end

    let payload = _WebSocketDecodeHelper.unmask_payload(input, _payload_len)?
    (_ExpectHeader, Binary(consume payload))

class val _ExpectClose
  let _payload_len: USize

  new create(payload_len: USize) =>
    _payload_len = payload_len

  fun decode_part(input: Reader): _DecodeResult? =>
    if input.size() < (_payload_len + 4) then return _NeedMore end

    let payload = _WebSocketDecodeHelper.unmask_payload(input, _payload_len)?
    if payload.size() >= 2 then
      let code =
        try
          U16.from[U8](payload.shift()?).shl(8) + U16.from[U8](payload.shift()?)
        else return ErrorMalformedClosePayload end
      if payload.size() > 0 then
        let reason =
          try
            UTF8.from_array(consume payload)? as String
          else return ErrorNonUTF8Text end
        (_ExpectHeader, Close.with_reason(code, reason)?)
      else
        (_ExpectHeader, Close(code))
      end
    else
      (_ExpectHeader, Close.empty())
    end

class val _ExpectPing
  let _payload_len: USize

  new create(payload_len: USize) =>
    _payload_len = payload_len

  fun decode_part(input: Reader): _DecodeResult? =>
    if input.size() < (_payload_len + 4) then return _NeedMore end

    let payload = _WebSocketDecodeHelper.unmask_payload(input, _payload_len)?
    (_ExpectHeader, Ping.with_payload(consume payload)?)

class val _ExpectPong
  let _payload_len: USize

  new create(payload_len: USize) =>
    _payload_len = payload_len

  fun decode_part(input: Reader): _DecodeResult? =>
    if input.size() < (_payload_len + 4) then return _NeedMore end

    let payload = _WebSocketDecodeHelper.unmask_payload(input, _payload_len)?
    (_ExpectHeader, Pong.with_payload(consume payload)?)

type _WebSocketDecodeState is (
  _ExpectHeader |
  _Expect16BitLength |
  _Expect64BitLength |
  _ExpectText |
  _ExpectBinary |
  _ExpectClose |
  _ExpectPing |
  _ExpectPong)

interface _WebSocketDecodeStateFactory
  fun apply(payload_len: USize): _WebSocketDecodeState ref

primitive _WebSocketDecodeHelper
  fun unmask_payload(input: Reader, payload_len: USize): Array[U8 val] iso^? =>
    let mask_key = input.block(4)?
    let payload = input.block(payload_len)?
    var i: USize = 0
    let m1 = mask_key(0)?
    let m2 = mask_key(1)?
    let m3 = mask_key(2)?
    let m4 = mask_key(3)?
    // Microbenchmarks show that masking 16-bytes at a time is fastest
    let stop =
      match payload_len - 0xf
      | let valid: USize if valid < payload_len => valid
      else 0 // Overflowed
      end

    while i < stop do
      payload(i)?       = payload(i)?       xor m1
      payload(i + 0x1)? = payload(i + 0x1)? xor m2
      payload(i + 0x2)? = payload(i + 0x2)? xor m3
      payload(i + 0x3)? = payload(i + 0x3)? xor m4
      payload(i + 0x4)? = payload(i + 0x4)? xor m1
      payload(i + 0x5)? = payload(i + 0x5)? xor m2
      payload(i + 0x6)? = payload(i + 0x6)? xor m3
      payload(i + 0x7)? = payload(i + 0x7)? xor m4
      payload(i + 0x8)? = payload(i + 0x8)? xor m1
      payload(i + 0x9)? = payload(i + 0x9)? xor m2
      payload(i + 0xA)? = payload(i + 0xA)? xor m3
      payload(i + 0xB)? = payload(i + 0xB)? xor m4
      payload(i + 0xC)? = payload(i + 0xC)? xor m1
      payload(i + 0xD)? = payload(i + 0xD)? xor m2
      payload(i + 0xE)? = payload(i + 0xE)? xor m3
      payload(i + 0xF)? = payload(i + 0xF)? xor m4
      i = i + 0x10
    end
    while i < payload_len do
      payload(i)? = payload(i)? xor mask_key(i % 4)?
      i = i + 1
    end
    payload
