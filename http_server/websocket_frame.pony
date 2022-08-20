use "buffered"

primitive Continuation  fun apply(): U8 => 0x00
primitive Text          fun apply(): U8 => 0x01
primitive Binary        fun apply(): U8 => 0x02
primitive Close         fun apply(): U8 => 0x08
primitive Ping          fun apply(): U8 => 0x09
primitive Pong          fun apply(): U8 => 0x0A
type Opcode is (Continuation | Text | Binary | Ping | Pong | Close)

class val WebSocketFrame
  let _opcode: Opcode

  // Unmasked data.
  let _data: (String val | Array[U8 val] val)

  new iso create(opcode: Opcode, data:  (String val | Array[U8 val] iso)) =>
    _opcode = opcode
    _data = consume data

  // Create an Text frame
  new iso text(data: String = "") =>
    _opcode = Text
    _data = consume data

  // Create an Text frame
  new iso ping(data: Array[U8 val] val) =>
    _opcode = Ping
    _data = data

  new iso pong(data: Array[U8 val] val) =>
    _opcode = Pong
    _data = data

  new iso binary(data: Array[U8 val] val) =>
    _opcode = Binary
    _data = data

  new iso close(code: U16 = 1000) =>
    _opcode = Close
    _data = [U8.from[U16](code.shr(8)); U8.from[U16](code and 0xFF)]

  // Build a frame that the server can send to client, data is not masked
  fun val build(): Array[(String val | Array[U8 val] val)] iso^ =>
    let writer: Writer = Writer

    match _opcode
    | Text   => writer.u8(0b1000_0001)
    | Binary => writer.u8(0b1000_0010)
    | Ping   => writer.u8(0b1000_1001)
    | Pong   => writer.u8(0b1000_1010)
    | Close =>
      writer.u8(0b1000_1000)
      writer.u8(0x2)      // two bytes for code
      writer.write(_data)  // status code
      return writer.done()
    end

    var payload_len = _data.size()
    if payload_len < 126 then
      writer.u8(U8.from[USize](payload_len))
    elseif payload_len < 65536 then
      writer.u8(126)
      writer.u16_be(U16.from[USize](payload_len))
    else
      writer.u8(127)
      writer.u64_be(U64.from[USize](payload_len))
    end
    writer.write(_data)
    writer.done()
