// Error with the frame header (typically the first two bytes)
// These should result in a Status 1002 closure
primitive ErrorNonZeroRSV
primitive ErrorNotMasked
primitive ErrorUnsupportedOpCode
primitive ErrorControlFrameFragmented
primitive ErrorControlFrameTooLarge
primitive ErrorBadPayloadLength

type WebSocketDecodeFrameError is (
  ErrorNonZeroRSV |
  ErrorNotMasked |
  ErrorUnsupportedOpCode |
  ErrorControlFrameFragmented |
  ErrorControlFrameTooLarge |
  ErrorBadPayloadLength)

// Error with the payload
// These should result in a Status 1007 closure
primitive ErrorMalformedClosePayload
primitive ErrorNonUTF8Text

type WebSocketDecodePayloadError is (
  ErrorMalformedClosePayload |
  ErrorNonUTF8Text)

type WebSocketDecodeError is (
  WebSocketDecodeFrameError |
  WebSocketDecodePayloadError)
