package oracle

import java.nio.file.{Files, Paths}
import java.time.Instant
import scala.util.Try

/** ORACLE's Automatic Report Engine: turns a registered experiment
  * plus one of its recorded results into a complete, versioned
  * scientific report (Markdown and HTML), including the
  * reproducibility metadata needed to regenerate it later. */
object ReportGenerator {

  private def loadJson(path: String): Try[JValue] = Try {
    JsonMini.parse(new String(Files.readAllBytes(Paths.get(path)))).getOrElse(JNull)
  }

  def generateMarkdown(experiment: ExperimentMeta, resultPath: String): Try[String] =
    for {
      configJson <- loadJson(experiment.configPath)
      resultJson <- loadJson(resultPath)
    } yield {
      val sb = new StringBuilder
      sb.append(s"# ORACLE Experiment Report: ${experiment.name}\n\n")
      sb.append(s"*Generated: ${Instant.now()}*\n\n")
      sb.append(s"**Experiment ID:** `${experiment.id}`  \n")
      sb.append(s"**Version:** ${experiment.version}  \n")
      sb.append(s"**Tags:** ${experiment.tags.mkString(", ")}\n\n")
      sb.append("## Description\n\n").append(experiment.description).append("\n\n")

      sb.append("## Configuration\n\n```json\n").append(JsonMini.encodePretty(configJson)).append("\n```\n\n")

      val status = JsonMini.get(resultJson, "status").flatMap(JsonMini.getString).getOrElse("unknown")
      val cfgHash = JsonMini.get(resultJson, "configurationHash").flatMap(JsonMini.getString).getOrElse("n/a")
      val solver = JsonMini.get(resultJson, "solverMethod").flatMap(JsonMini.getString).getOrElse("n/a")
      sb.append("## Reproducibility\n\n")
      sb.append(s"- **Status:** $status\n")
      sb.append(s"- **Configuration hash:** `$cfgHash`\n")
      sb.append(s"- **Solver method:** $solver\n\n")

      val result = JsonMini.get(resultJson, "result").getOrElse(JNull)
      val metrics = JsonMini.get(result, "metrics").getOrElse(JNull)
      sb.append("## Metrics\n\n")
      JsonMini.getObject(metrics) match {
        case Some(fields) =>
          sb.append("| Metric | Value |\n|---|---|\n")
          fields.foreach { case (k, v) =>
            val display = v match {
              case JNumber(n) => n.toString
              case JObject(_) => JsonMini.encode(v)
              case other => JsonMini.encode(other)
            }
            sb.append(s"| $k | $display |\n")
          }
        case None => sb.append("_No scalar metrics recorded for this run._\n")
      }

      sb.append("\n## Limitations\n\n")
      sb.append("This report was generated automatically from a single recorded run. ")
      sb.append("Statistical conclusions should be interpreted alongside the sample size, ")
      sb.append("solver stability flag, and any constraint-violation probability reported above.\n")
      sb.toString
    }

  def generateHtml(experiment: ExperimentMeta, resultPath: String): Try[String] =
    generateMarkdown(experiment, resultPath).map { md =>
      // Minimal, dependency-free Markdown-to-HTML for report purposes:
      // headings, tables and code fences are the only constructs the
      // generator above ever produces, so a full CommonMark parser is
      // not needed here.
      val html = new StringBuilder
      html.append("<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>")
        .append(experiment.name).append(" — ORACLE Report</title>")
        .append("<style>body{font-family:Segoe UI,sans-serif;max-width:860px;margin:2rem auto;padding:0 1rem;line-height:1.55}")
        .append("table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:6px 10px}")
        .append("pre{background:#1e1e1e;color:#d4d4d4;padding:1rem;overflow-x:auto;border-radius:6px}</style></head><body>")
      var inCode = false
      for (line <- md.split("\n")) {
        if (line.startsWith("```")) {
          html.append(if (inCode) "</pre>" else "<pre>")
          inCode = !inCode
        } else if (inCode) {
          html.append(escape(line)).append("\n")
        } else if (line.startsWith("# ")) {
          html.append("<h1>").append(escape(line.drop(2))).append("</h1>")
        } else if (line.startsWith("## ")) {
          html.append("<h2>").append(escape(line.drop(3))).append("</h2>")
        } else if (line.startsWith("|")) {
          html.append("<tr>")
          line.split("\\|").filter(_.nonEmpty).foreach(cell => html.append("<td>").append(escape(cell.trim)).append("</td>"))
          html.append("</tr>")
        } else if (line.trim.nonEmpty) {
          html.append("<p>").append(escape(line)).append("</p>")
        }
      }
      html.append("</body></html>")
      html.toString
    }

  private def escape(s: String): String =
    s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
}
