primitive UTF8
  fun from_array(data: Array[U8 val] iso): (String iso^ | (String iso^, Array[U8 val] iso^))? =>
    let char_width: Array[U8] = [
      1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1
      1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1
      1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1
      1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1
      1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1
      1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1
      1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1
      1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1
      // 0b1000_XXXX
      0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0
      0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0
      0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0
      0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0
      // 0b1100_XXXX
      0;0;2;2;2;2;2;2;2;2;2;2;2;2;2;2
      2;2;2;2;2;2;2;2;2;2;2;2;2;2;2;2
      3;3;3;3;3;3;3;3;3;3;3;3;3;3;3;3
      4;4;4;4;4;0;0;0;0;0;0;0;0;0;0;0
    ]
    let len: USize = data.size()
    var i: USize = 0
    var has_trailing: Bool = false

    while i < len do
      match data(i)?
      | let ascii: U8 if ascii < 0x80 =>
        // 1-byte
        i = i + 1

      | let b0: U8 if b0 >= 0xc2 =>
        match char_width(USize.from[U8](b0))?
        | 2 =>
          match len - i
          | 1 =>
            has_trailing = true
            break
          end
          _validate_continuation(data(i + 1)?)?
          i = i + 2

        | 3 =>
          match len - i
          | 1 =>
            has_trailing = true
            break
          | 2 =>
            _validate_3byte_codepoint(b0, data(i + 1)?)?
            has_trailing = true
            break
          end
          _validate_3byte_codepoint(b0, data(i + 1)?)?
          _validate_continuation(data(i + 2)?)?
          i = i + 3

        | 4 =>
          match len - i
          | 1 =>
            has_trailing = true
            break
          | 2 =>
            _validate_4byte_codepoint(b0, data(i + 1)?)?
            has_trailing = true
            break
          | 3 =>
            _validate_4byte_codepoint(b0, data(i + 1)?)?
            _validate_continuation(data(i + 2)?)?
            has_trailing = true
            break
          end
          _validate_4byte_codepoint(b0, data(i + 1)?)?
          _validate_continuation(data(i + 2)?)?
          _validate_continuation(data(i + 3)?)?
          i = i + 4

        else
          error
        end
      end
    end

    if has_trailing then
      (String.from_iso_array(consume data), [])
    else
      String.from_iso_array(consume data)
    end

  fun _validate_continuation(byte: U8)? =>
    if (byte < 0b1000_0000) or (0b1100_0000 <= byte) then error end

  fun _out_of_range(byte: U8, lower: U8, upper: U8): Bool =>
    (byte < lower) or (upper < byte)

  fun _validate_3byte_codepoint(b0: U8, b1: U8)? =>
    if
      ((b0 != 0xe0)                  or _out_of_range(b1, 0xa0, 0xbf)) and
      (_out_of_range(b0, 0xe1, 0xec) or _out_of_range(b1, 0x80, 0xbf)) and
      ((b0 != 0xed)                  or _out_of_range(b1, 0x80, 0x9f)) and
      (_out_of_range(b0, 0xee, 0xef) or _out_of_range(b1, 0x80, 0xbf))
    then
      error
    end

  fun _validate_4byte_codepoint(b0: U8, b1: U8)? =>
    if
      ((b0 != 0xf0)                  or _out_of_range(b1, 0x90, 0xbf)) and
      (_out_of_range(b0, 0xf1, 0xf3) or _out_of_range(b1, 0x80, 0xbf)) and
      ((b0 != 0xf4)                  or _out_of_range(b1, 0x80, 0x8f))
    then
      error
    end
