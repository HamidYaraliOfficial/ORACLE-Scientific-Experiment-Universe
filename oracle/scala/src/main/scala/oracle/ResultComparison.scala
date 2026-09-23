package oracle

import java.nio.file.{Files, Paths}
import scala.util.Try

/** ORACLE's Result Comparison Engine: loads two or more result JSON
  * artifacts (as written by the Julia `ResultStore`) and computes a
  * structured diff over their metrics — the data the Scientific
  * Comparison Matrix and the Web UI's Result Explorer both render. */
object ResultComparison {

  final case class MetricDiff(metric: String, valueA: Double, valueB: Double, absoluteDiff: Double, relativeDiffPct: Double)

  final case class ComparisonReport(runIdA: String, runIdB: String, metricDiffs: Vector[MetricDiff],
                                     onlyInA: Vector[String], onlyInB: Vector[String]) {
    def toJson: JValue = JsonMini.obj(
      "runIdA" -> JsonMini.str(runIdA),
      "runIdB" -> JsonMini.str(runIdB),
      "metricDiffs" -> JArray(metricDiffs.map(d => JsonMini.obj(
        "metric" -> JsonMini.str(d.metric),
        "valueA" -> JsonMini.num(d.valueA),
        "valueB" -> JsonMini.num(d.valueB),
        "absoluteDiff" -> JsonMini.num(d.absoluteDiff),
        "relativeDiffPct" -> JsonMini.num(d.relativeDiffPct)
      ))),
      "onlyInA" -> JArray(onlyInA.map(JsonMini.str)),
      "onlyInB" -> JArray(onlyInB.map(JsonMini.str))
    )
  }

  private def loadMetrics(resultPath: String): Try[Map[String, Double]] = Try {
    val text = new String(Files.readAllBytes(Paths.get(resultPath)))
    val json = JsonMini.parse(text).getOrElse(throw new RuntimeException("invalid result JSON"))
    val result = JsonMini.get(json, "result").getOrElse(json)
    val metrics = JsonMini.get(result, "metrics").getOrElse(JNull)
    JsonMini.getObject(metrics).map(_.flatMap {
      case (k, v) => JsonMini.getDouble(v).map(k -> _)
    }.toMap).getOrElse(Map.empty)
  }

  def compare(runIdA: String, resultPathA: String, runIdB: String, resultPathB: String): Try[ComparisonReport] =
    for {
      ma <- loadMetrics(resultPathA)
      mb <- loadMetrics(resultPathB)
    } yield {
      val common = ma.keySet.intersect(mb.keySet)
      val diffs = common.toVector.sorted.map { k =>
        val a = ma(k); val b = mb(k)
        val abs = b - a
        val relPct = if (a == 0.0) (if (b == 0.0) 0.0 else Double.PositiveInfinity) else (abs / math.abs(a)) * 100.0
        MetricDiff(k, a, b, abs, relPct)
      }
      ComparisonReport(runIdA, runIdB, diffs, (ma.keySet -- mb.keySet).toVector.sorted, (mb.keySet -- ma.keySet).toVector.sorted)
    }

  /** Compare more than two runs at once by pivoting every metric into a
    * row of values, one column per run — this is the Scientific
    * Comparison Matrix's underlying data shape. */
  def matrix(runs: Vector[(String, String)]): Try[JValue] = Try {
    val loaded = runs.map { case (id, path) => id -> loadMetrics(path).getOrElse(Map.empty) }
    val allMetrics = loaded.flatMap(_._2.keySet).distinct.sorted
    val rows = allMetrics.map { metric =>
      JsonMini.obj(
        "metric" -> JsonMini.str(metric),
        "values" -> JObject(loaded.map { case (id, m) => id -> m.get(metric).map(JsonMini.num).getOrElse(JNull) })
      )
    }
    JArray(rows.toVector)
  }
}
