package oracle

/** A small, dependency-free JSON representation, parser and encoder.
  *
  * Just like the Haskell and Julia layers, ORACLE's Scala Orchestration
  * layer avoids third-party JSON libraries (circe, play-json, ...) in
  * its core so that `sbt run` needs to resolve nothing beyond the
  * Scala standard library itself.
  */
sealed trait JValue
case object JNull extends JValue
final case class JBool(value: Boolean) extends JValue
final case class JNumber(value: Double) extends JValue
final case class JString(value: String) extends JValue
final case class JArray(values: Vector[JValue]) extends JValue
final case class JObject(fields: Vector[(String, JValue)]) extends JValue

object JsonMini {

  // ---- Convenience constructors -----------------------------------
  def obj(fields: (String, JValue)*): JValue = JObject(fields.toVector)
  def arr(values: JValue*): JValue = JArray(values.toVector)
  def str(s: String): JValue = JString(s)
  def num(d: Double): JValue = JNumber(d)

  // ---- Accessors ----------------------------------------------------
  def get(v: JValue, key: String): Option[JValue] = v match {
    case JObject(fields) => fields.find(_._1 == key).map(_._2)
    case _ => None
  }

  def getString(v: JValue): Option[String] = v match {
    case JString(s) => Some(s); case _ => None
  }
  def getDouble(v: JValue): Option[Double] = v match {
    case JNumber(n) => Some(n); case _ => None
  }
  def getInt(v: JValue): Option[Int] = getDouble(v).map(_.round.toInt)
  def getArray(v: JValue): Option[Vector[JValue]] = v match {
    case JArray(xs) => Some(xs); case _ => None
  }
  def getObject(v: JValue): Option[Vector[(String, JValue)]] = v match {
    case JObject(xs) => Some(xs); case _ => None
  }

  // ---- Encoding -------------------------------------------------------
  def encode(v: JValue): String = v match {
    case JNull => "null"
    case JBool(b) => if (b) "true" else "false"
    case JNumber(n) => showNumber(n)
    case JString(s) => encodeString(s)
    case JArray(xs) => "[" + xs.map(encode).mkString(",") + "]"
    case JObject(kvs) =>
      "{" + kvs.map { case (k, v2) => encodeString(k) + ":" + encode(v2) }.mkString(",") + "}"
  }

  def encodePretty(v: JValue, indent: Int = 0): String = {
    val pad = "  " * indent
    val padIn = "  " * (indent + 1)
    v match {
      case JNull => "null"
      case JBool(b) => if (b) "true" else "false"
      case JNumber(n) => showNumber(n)
      case JString(s) => encodeString(s)
      case JArray(xs) if xs.isEmpty => "[]"
      case JArray(xs) =>
        "[\n" + xs.map(x => padIn + encodePretty(x, indent + 1)).mkString(",\n") + "\n" + pad + "]"
      case JObject(kvs) if kvs.isEmpty => "{}"
      case JObject(kvs) =>
        "{\n" + kvs.map { case (k, v2) =>
          padIn + encodeString(k) + ": " + encodePretty(v2, indent + 1)
        }.mkString(",\n") + "\n" + pad + "}"
    }
  }

  private def showNumber(d: Double): String =
    if (d == d.toLong.toDouble && math.abs(d) < 1.0e15) d.toLong.toString else d.toString

  private def encodeString(s: String): String = {
    val sb = new StringBuilder
    sb.append('"')
    for (c <- s) c match {
      case '"'  => sb.append("\\\"")
      case '\\' => sb.append("\\\\")
      case '\n' => sb.append("\\n")
      case '\t' => sb.append("\\t")
      case '\r' => sb.append("\\r")
      case c if c < ' ' => sb.append(f"\\u${c.toInt}%04x")
      case c => sb.append(c)
    }
    sb.append('"')
    sb.toString
  }

  // ---- Parsing --------------------------------------------------------
  def parse(input: String): Either[String, JValue] = {
    val p = new Parser(input)
    p.skipWs()
    p.parseValue().flatMap { v =>
      p.skipWs()
      if (p.pos < p.n) Left(s"Unexpected trailing content at position ${p.pos}") else Right(v)
    }
  }

  private class Parser(val s: String) {
    var pos: Int = 0
    val n: Int = s.length

    def skipWs(): Unit = { while (pos < n && s(pos).isWhitespace) pos += 1 }

    def parseValue(): Either[String, JValue] = {
      skipWs()
      if (pos >= n) return Left("Unexpected end of input")
      s(pos) match {
        case '"' => parseString().map(JString)
        case '{' => parseObject()
        case '[' => parseArray()
        case 't' if s.startsWith("true", pos)  => pos += 4; Right(JBool(true))
        case 'f' if s.startsWith("false", pos) => pos += 5; Right(JBool(false))
        case 'n' if s.startsWith("null", pos)  => pos += 4; Right(JNull)
        case c if c == '-' || c.isDigit => parseNumber()
        case c => Left(s"Unexpected character '$c' at position $pos")
      }
    }

    def parseString(): Either[String, String] = {
      pos += 1 // opening quote
      val sb = new StringBuilder
      while (true) {
        if (pos >= n) return Left("Unterminated string literal")
        s(pos) match {
          case '"' => pos += 1; return Right(sb.toString)
          case '\\' =>
            pos += 1
            if (pos >= n) return Left("Unterminated escape sequence")
            s(pos) match {
              case '"' => sb.append('"'); pos += 1
              case '\\' => sb.append('\\'); pos += 1
              case '/' => sb.append('/'); pos += 1
              case 'n' => sb.append('\n'); pos += 1
              case 't' => sb.append('\t'); pos += 1
              case 'r' => sb.append('\r'); pos += 1
              case 'b' => sb.append('\b'); pos += 1
              case 'f' => sb.append('\f'); pos += 1
              case 'u' =>
                val hex = s.substring(pos + 1, pos + 5)
                sb.append(Integer.parseInt(hex, 16).toChar)
                pos += 5
              case other => return Left(s"Invalid escape character: \\$other")
            }
          case c => sb.append(c); pos += 1
        }
      }
      Left("unreachable")
    }

    def parseNumber(): Either[String, JValue] = {
      val start = pos
      if (pos < n && s(pos) == '-') pos += 1
      while (pos < n && s(pos).isDigit) pos += 1
      if (pos < n && s(pos) == '.') { pos += 1; while (pos < n && s(pos).isDigit) pos += 1 }
      if (pos < n && (s(pos) == 'e' || s(pos) == 'E')) {
        pos += 1
        if (pos < n && (s(pos) == '+' || s(pos) == '-')) pos += 1
        while (pos < n && s(pos).isDigit) pos += 1
      }
      val numStr = s.substring(start, pos)
      try Right(JNumber(numStr.toDouble)) catch {
        case _: NumberFormatException => Left(s"Invalid number literal: $numStr")
      }
    }

    def parseArray(): Either[String, JValue] = {
      pos += 1 // '['
      skipWs()
      if (pos < n && s(pos) == ']') { pos += 1; return Right(JArray(Vector.empty)) }
      val buf = scala.collection.mutable.ArrayBuffer[JValue]()
      var continue = true
      while (continue) {
        parseValue() match {
          case Left(err) => return Left(err)
          case Right(v) => buf += v
        }
        skipWs()
        if (pos >= n) return Left("Unterminated array")
        s(pos) match {
          case ',' => pos += 1; skipWs()
          case ']' => pos += 1; continue = false
          case c => return Left(s"Expected ',' or ']' at position $pos, found '$c'")
        }
      }
      Right(JArray(buf.toVector))
    }

    def parseObject(): Either[String, JValue] = {
      pos += 1 // '{'
      skipWs()
      if (pos < n && s(pos) == '}') { pos += 1; return Right(JObject(Vector.empty)) }
      val buf = scala.collection.mutable.ArrayBuffer[(String, JValue)]()
      var continue = true
      while (continue) {
        skipWs()
        if (pos >= n || s(pos) != '"') return Left(s"Expected string key at position $pos")
        val keyResult = parseString()
        val key = keyResult match {
          case Left(err) => return Left(err)
          case Right(k) => k
        }
        skipWs()
        if (pos >= n || s(pos) != ':') return Left(s"Expected ':' at position $pos")
        pos += 1
        parseValue() match {
          case Left(err) => return Left(err)
          case Right(v) => buf += (key -> v)
        }
        skipWs()
        if (pos >= n) return Left("Unterminated object")
        s(pos) match {
          case ',' => pos += 1
          case '}' => pos += 1; continue = false
          case c => return Left(s"Expected ',' or '}' at position $pos, found '$c'")
        }
      }
      Right(JObject(buf.toVector))
    }
  }
}
