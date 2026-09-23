package oracle

import java.time.Instant
import java.util.UUID

/** The lifecycle states ORACLE's Distributed Experiment Scheduler
  * assigns to a job, exactly as the specification requires: a job is
  * always in exactly one of these states, and every transition is
  * recorded in the job's history for the Scientific Audit Trail.
  */
sealed trait JobStatus
object JobStatus {
  case object Queued extends JobStatus
  case object Scheduled extends JobStatus
  case object Running extends JobStatus
  case object Paused extends JobStatus
  case object Failed extends JobStatus
  case object Cancelled extends JobStatus
  case object Completed extends JobStatus
  case object PartiallyCompleted extends JobStatus

  def toJson(s: JobStatus): String = s match {
    case Queued => "queued"
    case Scheduled => "scheduled"
    case Running => "running"
    case Paused => "paused"
    case Failed => "failed"
    case Cancelled => "cancelled"
    case Completed => "completed"
    case PartiallyCompleted => "partially_completed"
  }
}

/** One unit of distributable work: "run this validated experiment
  * configuration through the Julia engine in the given mode". */
final case class Job(
    id: String,
    experimentId: String,
    mode: String, // "simulate" | "montecarlo" | "sweep" | "sensitivity"
    configPath: String,
    outputDir: String,
    extraArg: Option[String], // n_samples / resolution, mode-dependent
    priority: Int,
    maxRetries: Int,
    var retries: Int = 0,
    var status: JobStatus = JobStatus.Queued,
    val createdAt: Instant = Instant.now(),
    var startedAt: Option[Instant] = None,
    var finishedAt: Option[Instant] = None,
    var lastError: Option[String] = None,
    var resultPath: Option[String] = None
) {
  def toJson: JValue = JsonMini.obj(
    "id" -> JsonMini.str(id),
    "experimentId" -> JsonMini.str(experimentId),
    "mode" -> JsonMini.str(mode),
    "configPath" -> JsonMini.str(configPath),
    "outputDir" -> JsonMini.str(outputDir),
    "priority" -> JsonMini.num(priority),
    "retries" -> JsonMini.num(retries),
    "maxRetries" -> JsonMini.num(maxRetries),
    "status" -> JsonMini.str(JobStatus.toJson(status)),
    "createdAt" -> JsonMini.str(createdAt.toString),
    "startedAt" -> startedAt.map(t => JsonMini.str(t.toString)).getOrElse(JNull),
    "finishedAt" -> finishedAt.map(t => JsonMini.str(t.toString)).getOrElse(JNull),
    "lastError" -> lastError.map(JsonMini.str).getOrElse(JNull),
    "resultPath" -> resultPath.map(JsonMini.str).getOrElse(JNull)
  )
}

object Job {
  def newId(): String = UUID.randomUUID().toString
}

/** Registry metadata for a registered Experiment Definition (as
  * distinct from any particular Run of it). */
final case class ExperimentMeta(
    id: String,
    name: String,
    description: String,
    configPath: String,
    tags: Set[String],
    version: Int,
    createdAt: Instant = Instant.now(),
    parentId: Option[String] = None, // set when this is a Fork/Branch of another experiment
    archived: Boolean = false,
    favorite: Boolean = false
) {
  def toJson: JValue = JsonMini.obj(
    "id" -> JsonMini.str(id),
    "name" -> JsonMini.str(name),
    "description" -> JsonMini.str(description),
    "configPath" -> JsonMini.str(configPath),
    "tags" -> JArray(tags.toVector.map(JsonMini.str)),
    "version" -> JsonMini.num(version),
    "createdAt" -> JsonMini.str(createdAt.toString),
    "parentId" -> parentId.map(JsonMini.str).getOrElse(JNull),
    "archived" -> JBool(archived),
    "favorite" -> JBool(favorite)
  )
}

final case class RunResult(
    runId: String,
    jobId: String,
    experimentId: String,
    status: String,
    resultPath: String,
    metrics: Map[String, Double]
) {
  def toJson: JValue = JsonMini.obj(
    "runId" -> JsonMini.str(runId),
    "jobId" -> JsonMini.str(jobId),
    "experimentId" -> JsonMini.str(experimentId),
    "status" -> JsonMini.str(status),
    "resultPath" -> JsonMini.str(resultPath),
    "metrics" -> JObject(metrics.toVector.map { case (k, v) => k -> JsonMini.num(v) })
  )
}
