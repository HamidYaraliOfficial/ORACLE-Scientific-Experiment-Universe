package oracle

import com.sun.net.httpserver.{HttpServer, HttpExchange, HttpHandler}
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets
import scala.io.Source
import scala.util.Try

/** ORACLE's Experiment API (REST layer). Built on the JDK's own
  * `com.sun.net.httpserver`, so exposing the Registry and Scheduler
  * over HTTP requires zero external web-framework dependency — in
  * keeping with the zero-third-party-dependency design used across
  * every ORACLE language layer.
  *
  * Endpoints:
  *   GET  /experiments                 -> list registered experiments
  *   POST /experiments                 -> register {name,description,configPath,tags}
  *   GET  /experiments/{id}            -> one experiment's metadata
  *   POST /experiments/{id}/run        -> {mode,outputDir,replications,extraArg} -> submits jobs
  *   GET  /jobs/{id}                   -> job status
  *   GET  /experiments/{id}/runs       -> recorded RunResults for an experiment
  *   GET  /workers                     -> worker pool health snapshot
  */
final class ApiServer(port: Int, registry: Registry, scheduler: Scheduler, coordinator: ExperimentCoordinator) {

  private var server: HttpServer = _

  def start(): Unit = {
    server = HttpServer.create(new InetSocketAddress(port), 0)
    server.createContext("/experiments", handler(handleExperiments))
    server.createContext("/jobs", handler(handleJobs))
    server.createContext("/workers", handler(handleWorkers))
    server.setExecutor(java.util.concurrent.Executors.newCachedThreadPool())
    server.start()
    println(s"[ORACLE API] listening on http://0.0.0.0:$port")
  }

  def stop(): Unit = if (server != null) server.stop(0)

  private def handler(f: HttpExchange => Unit): HttpHandler = new HttpHandler {
    def handle(exchange: HttpExchange): Unit = {
      try f(exchange)
      catch {
        case e: Throwable => respond(exchange, 500, JsonMini.obj("error" -> JsonMini.str(e.getMessage)))
      } finally exchange.close()
    }
  }

  private def readBody(exchange: HttpExchange): String =
    Try(Source.fromInputStream(exchange.getRequestBody, "UTF-8").mkString).getOrElse("")

  private def respond(exchange: HttpExchange, code: Int, body: JValue): Unit = {
    val bytes = JsonMini.encodePretty(body).getBytes(StandardCharsets.UTF_8)
    exchange.getResponseHeaders.add("Content-Type", "application/json; charset=utf-8")
    exchange.sendResponseHeaders(code, bytes.length)
    val os = exchange.getResponseBody
    os.write(bytes); os.close()
  }

  private def pathSegments(exchange: HttpExchange): Vector[String] =
    exchange.getRequestURI.getPath.split("/").filter(_.nonEmpty).toVector

  private def handleExperiments(exchange: HttpExchange): Unit = {
    val segs = pathSegments(exchange) // ["experiments", maybe id, maybe "run"/"runs"]
    (exchange.getRequestMethod, segs) match {
      case ("GET", Vector("experiments")) =>
        val q = queryParam(exchange, "q")
        val tag = queryParam(exchange, "tag")
        val results = registry.search(q, tag)
        respond(exchange, 200, JArray(results.map(_.toJson)))

      case ("POST", Vector("experiments")) =>
        val body = JsonMini.parse(readBody(exchange)).getOrElse(JNull)
        val name = JsonMini.get(body, "name").flatMap(JsonMini.getString).getOrElse("unnamed")
        val desc = JsonMini.get(body, "description").flatMap(JsonMini.getString).getOrElse("")
        val cfg  = JsonMini.get(body, "configPath").flatMap(JsonMini.getString).getOrElse("")
        val tags = JsonMini.get(body, "tags").flatMap(JsonMini.getArray).map(_.flatMap(JsonMini.getString).toSet).getOrElse(Set.empty)
        val meta = registry.register(name, desc, cfg, tags)
        respond(exchange, 201, meta.toJson)

      case ("GET", Vector("experiments", id)) =>
        registry.get(id) match {
          case Some(m) => respond(exchange, 200, m.toJson)
          case None => respond(exchange, 404, JsonMini.obj("error" -> JsonMini.str("not found")))
        }

      case ("GET", Vector("experiments", id, "runs")) =>
        respond(exchange, 200, JArray(registry.listRuns(id).map(_.toJson)))

      case ("POST", Vector("experiments", id, "run")) =>
        registry.get(id) match {
          case None => respond(exchange, 404, JsonMini.obj("error" -> JsonMini.str("not found")))
          case Some(meta) =>
            val body = JsonMini.parse(readBody(exchange)).getOrElse(JNull)
            val mode = JsonMini.get(body, "mode").flatMap(JsonMini.getString).getOrElse("simulate")
            val outputDir = JsonMini.get(body, "outputDir").flatMap(JsonMini.getString).getOrElse("results")
            val replications = JsonMini.get(body, "replications").flatMap(JsonMini.getInt).getOrElse(1)
            val extraArg = JsonMini.get(body, "extraArg").flatMap(JsonMini.getString)
            val submitted = coordinator.launchReplications(meta.id, meta.configPath, mode, outputDir, replications, extraArg)
            respond(exchange, 202, JArray(submitted.map(_.toJson)))
        }

      case ("POST", Vector("experiments", id, "fork")) =>
        val body = JsonMini.parse(readBody(exchange)).getOrElse(JNull)
        val newName = JsonMini.get(body, "name").flatMap(JsonMini.getString).getOrElse(id + "-fork")
        registry.fork(id, newName) match {
          case Some(m) => respond(exchange, 201, m.toJson)
          case None => respond(exchange, 404, JsonMini.obj("error" -> JsonMini.str("not found")))
        }

      case _ => respond(exchange, 404, JsonMini.obj("error" -> JsonMini.str("no such route")))
    }
  }

  private def handleJobs(exchange: HttpExchange): Unit = {
    pathSegments(exchange) match {
      case Vector("jobs", id) =>
        scheduler.status(id) match {
          case Some(j) => respond(exchange, 200, j.toJson)
          case None => respond(exchange, 404, JsonMini.obj("error" -> JsonMini.str("not found")))
        }
      case _ => respond(exchange, 404, JsonMini.obj("error" -> JsonMini.str("no such route")))
    }
  }

  private def handleWorkers(exchange: HttpExchange): Unit = {
    val snapshot = scheduler.workerSnapshot().map { w =>
      JsonMini.obj(
        "workerId" -> JsonMini.num(w.workerId),
        "healthy" -> JBool(w.healthy),
        "lastHeartbeat" -> JsonMini.str(w.lastHeartbeat.toString),
        "currentJobId" -> w.currentJobId.map(JsonMini.str).getOrElse(JNull),
        "jobsCompleted" -> JsonMini.num(w.jobsCompleted),
        "jobsFailed" -> JsonMini.num(w.jobsFailed)
      )
    }
    respond(exchange, 200, JArray(snapshot))
  }

  private def queryParam(exchange: HttpExchange, key: String): Option[String] = {
    val raw = Option(exchange.getRequestURI.getQuery).getOrElse("")
    raw.split("&").flatMap(_.split("=", 2) match {
      case Array(k, v) if k == key => Some(java.net.URLDecoder.decode(v, "UTF-8"))
      case _ => None
    }).headOption
  }
}
