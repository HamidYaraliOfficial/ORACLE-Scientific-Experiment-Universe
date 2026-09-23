package oracle

import java.nio.file.{Files, Paths, StandardCopyOption}
import java.time.Instant
import java.util.UUID
import scala.jdk.CollectionConverters._
import scala.collection.concurrent.TrieMap

/** ORACLE's Experiment Registry: a durable, file-backed store of every
  * registered experiment, keyed by id, with the operations the spec
  * requires — register, search, filter, tag, favorite, archive,
  * duplicate, fork, and compare. Metadata lives as one JSON file per
  * experiment under `<dataDir>/experiments/<id>.json`; this keeps the
  * registry provider-agnostic (swap the directory for a mounted
  * network volume or object-storage FUSE mount and nothing else
  * changes).
  */
final class Registry(dataDir: String) {
  private val expDir = Paths.get(dataDir, "experiments")
  private val runsDir = Paths.get(dataDir, "runs")
  Files.createDirectories(expDir)
  Files.createDirectories(runsDir)

  private val cache: TrieMap[String, ExperimentMeta] = TrieMap.empty
  loadAll()

  private def loadAll(): Unit = {
    if (Files.exists(expDir)) {
      Files.list(expDir).iterator().asScala.foreach { p =>
        if (p.toString.endsWith(".json")) {
          readMetaFile(p.toString).foreach(m => cache.put(m.id, m))
        }
      }
    }
  }

  private def metaPath(id: String): String = expDir.resolve(s"$id.json").toString

  private def readMetaFile(path: String): Option[ExperimentMeta] = {
    try {
      val text = new String(Files.readAllBytes(Paths.get(path)))
      JsonMini.parse(text).toOption.flatMap(fromJson)
    } catch { case _: Throwable => None }
  }

  private def fromJson(v: JValue): Option[ExperimentMeta] = for {
    id <- JsonMini.get(v, "id").flatMap(JsonMini.getString)
    name <- JsonMini.get(v, "name").flatMap(JsonMini.getString)
    configPath <- JsonMini.get(v, "configPath").flatMap(JsonMini.getString)
  } yield ExperimentMeta(
    id = id,
    name = name,
    description = JsonMini.get(v, "description").flatMap(JsonMini.getString).getOrElse(""),
    configPath = configPath,
    tags = JsonMini.get(v, "tags").flatMap(JsonMini.getArray).map(_.flatMap(JsonMini.getString).toSet).getOrElse(Set.empty),
    version = JsonMini.get(v, "version").flatMap(JsonMini.getInt).getOrElse(1),
    parentId = JsonMini.get(v, "parentId").flatMap(JsonMini.getString),
    archived = JsonMini.get(v, "archived").exists { case JBool(b) => b; case _ => false },
    favorite = JsonMini.get(v, "favorite").exists { case JBool(b) => b; case _ => false }
  )

  private def persist(m: ExperimentMeta): Unit = {
    Files.write(Paths.get(metaPath(m.id)), JsonMini.encodePretty(m.toJson).getBytes)
    cache.put(m.id, m)
  }

  // ---- CRUD -----------------------------------------------------------

  def register(name: String, description: String, configPath: String, tags: Set[String] = Set.empty): ExperimentMeta = {
    val m = ExperimentMeta(UUID.randomUUID().toString, name, description, configPath, tags, version = 1)
    persist(m)
    m
  }

  def get(id: String): Option[ExperimentMeta] = cache.get(id)

  def list(includeArchived: Boolean = false): Vector[ExperimentMeta] =
    cache.values.filter(m => includeArchived || !m.archived).toVector.sortBy(_.createdAt.toEpochMilli)

  /** Full-text-ish search across name/description, optionally
    * constrained by tag, favorite-only, or archived status — the
    * filter set the Experiment Registry spec calls for. */
  def search(query: Option[String] = None, tag: Option[String] = None,
             favoriteOnly: Boolean = false, includeArchived: Boolean = false): Vector[ExperimentMeta] =
    list(includeArchived).filter { m =>
      query.forall(q => m.name.toLowerCase.contains(q.toLowerCase) || m.description.toLowerCase.contains(q.toLowerCase)) &&
      tag.forall(t => m.tags.contains(t)) &&
      (!favoriteOnly || m.favorite)
    }

  def setFavorite(id: String, favorite: Boolean): Option[ExperimentMeta] =
    get(id).map { m => val updated = m.copy(favorite = favorite); persist(updated); updated }

  def archive(id: String): Option[ExperimentMeta] =
    get(id).map { m => val updated = m.copy(archived = true); persist(updated); updated }

  def restore(id: String): Option[ExperimentMeta] =
    get(id).map { m => val updated = m.copy(archived = false); persist(updated); updated }

  def addTag(id: String, tag: String): Option[ExperimentMeta] =
    get(id).map { m => val updated = m.copy(tags = m.tags + tag); persist(updated); updated }

  /** Duplicate: an independent copy with a fresh id and version 1,
    * config file physically copied so the two experiments can diverge
    * without affecting each other. */
  def duplicate(id: String, newName: String): Option[ExperimentMeta] = get(id).map { m =>
    val newId = UUID.randomUUID().toString
    val newConfigPath = m.configPath.replaceAll("\\.json$", "") + s"_copy_$newId.json"
    Files.copy(Paths.get(m.configPath), Paths.get(newConfigPath), StandardCopyOption.REPLACE_EXISTING)
    val copyMeta = ExperimentMeta(newId, newName, m.description, newConfigPath, m.tags, version = 1)
    persist(copyMeta)
    copyMeta
  }

  /** Fork/Branch: like duplicate, but the new experiment records its
    * lineage via `parentId`, which is what the Experiment Graph /
    * Experiment Version Control features use to render DerivedFrom
    * edges and branch diffs. */
  def fork(id: String, newName: String): Option[ExperimentMeta] = get(id).map { m =>
    val newId = UUID.randomUUID().toString
    val newConfigPath = m.configPath.replaceAll("\\.json$", "") + s"_fork_$newId.json"
    Files.copy(Paths.get(m.configPath), Paths.get(newConfigPath), StandardCopyOption.REPLACE_EXISTING)
    val forkMeta = ExperimentMeta(newId, newName, m.description, newConfigPath, m.tags,
                                   version = 1, parentId = Some(m.id))
    persist(forkMeta)
    forkMeta
  }

  /** Bump the version number after the underlying config file has been
    * edited in place — the minimal form of Experiment Version Control:
    * every past version's JSON remains addressable by its own path
    * even as `version` climbs, so a caller wanting a real diff can
    * always go read the prior file. */
  def newVersion(id: String, newConfigPath: String): Option[ExperimentMeta] = get(id).map { m =>
    val updated = m.copy(configPath = newConfigPath, version = m.version + 1)
    persist(updated)
    updated
  }

  // ---- Run bookkeeping --------------------------------------------------

  def recordRun(result: RunResult): Unit = {
    val path = runsDir.resolve(s"${result.runId}.json")
    Files.write(path, JsonMini.encodePretty(result.toJson).getBytes)
  }

  def listRuns(experimentId: String): Vector[RunResult] = {
    if (!Files.exists(runsDir)) return Vector.empty
    Files.list(runsDir).iterator().asScala.flatMap { p =>
      try {
        val text = new String(Files.readAllBytes(p))
        JsonMini.parse(text).toOption.flatMap(runFromJson).filter(_.experimentId == experimentId)
      } catch { case _: Throwable => None }
    }.toVector
  }

  private def runFromJson(v: JValue): Option[RunResult] = for {
    runId <- JsonMini.get(v, "runId").flatMap(JsonMini.getString)
    jobId <- JsonMini.get(v, "jobId").flatMap(JsonMini.getString)
    experimentId <- JsonMini.get(v, "experimentId").flatMap(JsonMini.getString)
    status <- JsonMini.get(v, "status").flatMap(JsonMini.getString)
    resultPath <- JsonMini.get(v, "resultPath").flatMap(JsonMini.getString)
  } yield RunResult(runId, jobId, experimentId, status, resultPath,
    JsonMini.get(v, "metrics").flatMap(JsonMini.getObject).map(_.flatMap {
      case (k, jv) => JsonMini.getDouble(jv).map(k -> _)
    }.toMap).getOrElse(Map.empty))
}
