-- | Oracle.Json
--
-- A small, dependency-free JSON representation, parser and encoder.
-- ORACLE intentionally avoids third-party JSON libraries (aeson, etc.)
-- in its core so that the Haskell validation layer can be built with
-- nothing but the standard `base` library. This keeps the formal
-- specification layer maximally reproducible across environments,
-- which is itself one of ORACLE's core design goals.
module Oracle.Json
  ( JValue(..)
  , parseJson
  , encodeJson
  , encodeJsonPretty
  , jLookup
  , jGetString
  , jGetDouble
  , jGetInt
  , jGetBool
  , jGetArray
  , jGetObject
  , jString
  , jNumber
  , jBool
  , jArray
  , jObject
  ) where

import Data.Char (isDigit, isSpace, isHexDigit, digitToInt)
import Data.List (intercalate)
import Numeric (showHex)

-- | A JSON value.
data JValue
  = JNull
  | JBool Bool
  | JNumber Double
  | JString String
  | JArray [JValue]
  | JObject [(String, JValue)]
  deriving (Eq, Show)

-- Convenience constructors -------------------------------------------------

jString :: String -> JValue
jString = JString

jNumber :: Double -> JValue
jNumber = JNumber

jBool :: Bool -> JValue
jBool = JBool

jArray :: [JValue] -> JValue
jArray = JArray

jObject :: [(String, JValue)] -> JValue
jObject = JObject

-- Accessors -----------------------------------------------------------------

jLookup :: String -> JValue -> Maybe JValue
jLookup k (JObject kvs) = lookup k kvs
jLookup _ _             = Nothing

jGetString :: JValue -> Maybe String
jGetString (JString s) = Just s
jGetString _           = Nothing

jGetDouble :: JValue -> Maybe Double
jGetDouble (JNumber n) = Just n
jGetDouble _           = Nothing

jGetInt :: JValue -> Maybe Int
jGetInt (JNumber n) = Just (round n)
jGetInt _           = Nothing

jGetBool :: JValue -> Maybe Bool
jGetBool (JBool b) = Just b
jGetBool _         = Nothing

jGetArray :: JValue -> Maybe [JValue]
jGetArray (JArray xs) = Just xs
jGetArray _           = Nothing

jGetObject :: JValue -> Maybe [(String, JValue)]
jGetObject (JObject kvs) = Just kvs
jGetObject _             = Nothing

-- Encoding --------------------------------------------------------------

encodeJson :: JValue -> String
encodeJson JNull        = "null"
encodeJson (JBool True) = "true"
encodeJson (JBool False)= "false"
encodeJson (JNumber n)  = showNumber n
encodeJson (JString s)  = encodeString s
encodeJson (JArray xs)  = "[" ++ intercalate "," (map encodeJson xs) ++ "]"
encodeJson (JObject kvs)=
  "{" ++ intercalate "," (map (\(k,v) -> encodeString k ++ ":" ++ encodeJson v) kvs) ++ "}"

-- | Pretty printer with 2-space indentation, useful for exported
-- validated-experiment files that a human might want to inspect.
encodeJsonPretty :: JValue -> String
encodeJsonPretty = go 0
  where
    pad n = replicate (n * 2) ' '
    go _ JNull         = "null"
    go _ (JBool True)  = "true"
    go _ (JBool False) = "false"
    go _ (JNumber n)   = showNumber n
    go _ (JString s)   = encodeString s
    go _ (JArray [])   = "[]"
    go n (JArray xs)   =
      "[\n" ++ intercalate ",\n" (map (\x -> pad (n+1) ++ go (n+1) x) xs)
      ++ "\n" ++ pad n ++ "]"
    go _ (JObject [])  = "{}"
    go n (JObject kvs) =
      "{\n" ++ intercalate ",\n"
        (map (\(k,v) -> pad (n+1) ++ encodeString k ++ ": " ++ go (n+1) v) kvs)
      ++ "\n" ++ pad n ++ "}"

showNumber :: Double -> String
showNumber d
  | d == fromIntegral (round d :: Integer) && abs d < 1.0e15 = show (round d :: Integer)
  | otherwise = show d

encodeString :: String -> String
encodeString s = "\"" ++ concatMap esc s ++ "\""
  where
    esc '"'  = "\\\""
    esc '\\' = "\\\\"
    esc '\n' = "\\n"
    esc '\r' = "\\r"
    esc '\t' = "\\t"
    esc c
      | c < ' '   = "\\u" ++ pad4 (showHex (fromEnum c) "")
      | otherwise = [c]
    pad4 h = replicate (4 - length h) '0' ++ h

-- Parsing --------------------------------------------------------------

-- | Parse a JSON document. Returns 'Left' with a human-readable error
-- location on malformed input, or 'Right' the parsed value.
parseJson :: String -> Either String JValue
parseJson input =
  case pValue (dropWs input) of
    Left err -> Left err
    Right (v, rest) ->
      case dropWs rest of
        [] -> Right v
        _  -> Left ("Unexpected trailing content near: " ++ take 30 rest)

dropWs :: String -> String
dropWs = dropWhile isSpace

pValue :: String -> Either String (JValue, String)
pValue s = case s of
  ('n':'u':'l':'l':rest) -> Right (JNull, rest)
  ('t':'r':'u':'e':rest) -> Right (JBool True, rest)
  ('f':'a':'l':'s':'e':rest) -> Right (JBool False, rest)
  ('"':rest) -> pString rest
  ('[':rest) -> pArray (dropWs rest)
  ('{':rest) -> pObject (dropWs rest)
  (c:_) | isDigit c || c == '-' -> pNumber s
  [] -> Left "Unexpected end of input while expecting a value"
  _  -> Left ("Unexpected character while expecting a value: " ++ take 20 s)

pString :: String -> Either String (JValue, String)
pString = go []
  where
    go acc ('"':rest) = Right (JString (reverse acc), rest)
    go acc ('\\':c:rest) = case c of
      '"'  -> go ('"':acc) rest
      '\\' -> go ('\\':acc) rest
      '/'  -> go ('/':acc) rest
      'n'  -> go ('\n':acc) rest
      't'  -> go ('\t':acc) rest
      'r'  -> go ('\r':acc) rest
      'b'  -> go ('\b':acc) rest
      'f'  -> go ('\f':acc) rest
      'u'  -> case splitAt 4 rest of
                (hex, rest') | length hex == 4 && all isHexDigit hex ->
                  go (toEnum (hexToInt hex) : acc) rest'
                _ -> Left "Invalid \\u escape in string"
      _    -> Left ("Invalid escape character: \\" ++ [c])
    go _ [] = Left "Unterminated string literal"
    go acc (c:rest) = go (c:acc) rest

    hexToInt = foldl (\a c -> a * 16 + digitToInt c) 0

pNumber :: String -> Either String (JValue, String)
pNumber s =
  let (numStr, rest) = span isNumChar s
  in if null numStr
       then Left "Expected a number"
       else case reads (fixLeadingDot numStr) :: [(Double, String)] of
              [(d, "")] -> Right (JNumber d, rest)
              _         -> Left ("Invalid number literal: " ++ numStr)
  where
    isNumChar c = isDigit c || c `elem` ("-+.eE" :: String)
    fixLeadingDot ('-':'.':r) = "-0." ++ r
    fixLeadingDot ('.':r)     = "0." ++ r
    fixLeadingDot xs          = xs

pArray :: String -> Either String (JValue, String)
pArray (']':rest) = Right (JArray [], rest)
pArray s = go [] s
  where
    go acc s' = case pValue (dropWs s') of
      Left err -> Left err
      Right (v, rest) -> case dropWs rest of
        (',':rest') -> go (v:acc) (dropWs rest')
        (']':rest') -> Right (JArray (reverse (v:acc)), rest')
        _ -> Left ("Expected ',' or ']' in array near: " ++ take 20 rest)

pObject :: String -> Either String (JValue, String)
pObject ('}':rest) = Right (JObject [], rest)
pObject s = go [] s
  where
    go acc s' = case dropWs s' of
      ('"':afterQuote) -> case pString afterQuote of
        Left err -> Left err
        Right (JString key, rest) -> case dropWs rest of
          (':':rest') -> case pValue (dropWs rest') of
            Left err -> Left err
            Right (v, rest'') -> case dropWs rest'' of
              (',':rest3) -> go ((key,v):acc) (dropWs rest3)
              ('}':rest3) -> Right (JObject (reverse ((key,v):acc)), rest3)
              _ -> Left ("Expected ',' or '}' in object near: " ++ take 20 rest'')
          _ -> Left "Expected ':' after object key"
        Right _ -> Left "Internal error parsing object key"
      _ -> Left ("Expected a string key in object near: " ++ take 20 s')
