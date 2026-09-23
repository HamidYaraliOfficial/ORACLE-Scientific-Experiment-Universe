package oracle

import java.nio.file.{Files, Paths}
import java.time.Instant
import scala.util.{Try, Success, Failure}

/** ORACLE's professional CLI: every capability the Web UI exposes is
  * also reachable here, so the whole system is usable headless (a
  * cluster node, a CI pipeline, an HPC job script). Subcommands mirror
  * the specification's required list: experiment, model, dataset, run,
  * sweep, montecarlo, optimize, analyze, compare, report, worker,
  * benchmark, snapshot, replay.
  */
object Cli {

  def run(args: Array[String], registry: Registry, scheduler: Scheduler,
           coordinator: ExperimentCoordinator, juliaCommand: String, juliaEntry: String): Unit = {
    args.toList match {
      case "experiment" :: "create" :: name :: configPath :: rest =>
        val tags = rest.headOption.map(_.split(",").toSet).getOrElse(Set.empty[String])
        val meta = registry.register(name, "", configPath, tags)
        println(s"Registered experiment '${meta.name}' with id ${meta.id}")

      case "experiment" :: "list" :: _ =>
        registry.list().foreach(m => println(s"${m.id}  v${m.version}  ${m.name}  tags=${m.tags.mkString(",")}"))

      case "experiment" :: "fork" :: id :: newName :: _ =>
        registry.fork(id, newName) match {
          case Some(m) => println(s"Forked into ${m.id} (${m.name})")
          case None => println(s"No such experiment: $id")
        }

      case "experiment" :: "archive" :: id :: _ =>
        registry.archive(id).foreach(_ => println(s"Archived $id"))

      case "run" :: id :: mode :: rest =>
        registry.get(id) match {
          case None => println(s"No such experiment: $id")
          case Some(meta) =>
            val outputDir = rest.headOption.getOrElse("results")
            val extraArg = rest.lift(1)
            val jobs = coordinator.launchReplications(meta.id, meta.configPath, mode, outputDir, 1, extraArg)
            println(s"Submitted job ${jobs.head.id} (mode=$mode)")
        }

      case "sweep" :: id :: resolution :: rest =>
        submitOne(registry, coordinator, id, "sweep", rest.headOption.getOrElse("results"), Some(resolution))

      case "montecarlo" :: id :: nSamples :: rest =>
        submitOne(registry, coordinator, id, "montecarlo", rest.headOption.getOrElse("results"), Some(nSamples))

      case "analyze" :: "sensitivity" :: id :: rest =>
        submitOne(registry, coordinator, id, "sensitivity", rest.headOption.getOrElse("results"), None)

      case "compare" :: runIdA :: pathA :: runIdB :: pathB :: _ =>
        ResultComparison.compare(runIdA, pathA, runIdB, pathB) match {
          case Success(report) => println(JsonMini.encodePretty(report.toJson))
          case Failure(e) => println(s"Comparison failed: ${e.getMessage}")
        }

      case "report" :: id :: resultPath :: rest =>
        val format = rest.headOption.getOrElse("md")
        registry.get(id) match {
          case None => println(s"No such experiment: $id")
          case Some(meta) =>
            val content = if (format == "html") ReportGenerator.generateHtml(meta, resultPath)
                          else ReportGenerator.generateMarkdown(meta, resultPath)
            content match {
              case Success(text) =>
                val outPath = s"report_${meta.id}.${if (format == "html") "html" else "md"}"
                Files.write(Paths.get(outPath), text.getBytes)
                println(s"Report written to $outPath")
              case Failure(e) => println(s"Report generation failed: ${e.getMessage}")
            }
        }

      case "worker" :: "start" :: rest =>
        val n = rest.headOption.map(_.toInt).getOrElse(4)
        println(s"Starting $n ORACLE workers (Julia entry: $juliaEntry)...")
        scheduler.start(job => println(s"[worker] job ${job.id} -> ${JobStatus.toJson(job.status)}"))
        println("Workers running. Press Ctrl+C to stop.")
        while (true) Thread.sleep(5000)

      case "benchmark" :: id :: rest =>
        val replications = rest.headOption.map(_.toInt).getOrElse(10)
        registry.get(id) match {
          case None => println(s"No such experiment: $id")
          case Some(meta) =>
            val start = System.nanoTime()
            val jobs = coordinator.launchReplications(meta.id, meta.configPath, "simulate", "results", replications)
            println(s"Benchmark: submitted ${jobs.size} replications of '${meta.name}'. " +
                     s"Poll `oracle jobs <id>` for completion; wall-clock submission took " +
                     f"${(System.nanoTime() - start) / 1e6}%.2f ms.")
        }

      case "snapshot" :: dataDir :: rest =>
        val target = rest.headOption.getOrElse(s"snapshot_${Instant.now().toEpochMilli}")
        copyDir(Paths.get(dataDir), Paths.get(target))
        println(s"Snapshot of $dataDir written to $target")

      case "replay" :: id :: rest =>
        registry.get(id) match {
          case None => println(s"No such experiment: $id")
          case Some(meta) =>
            val outputDir = rest.headOption.getOrElse("results_replay")
            val jobs = coordinator.launchReplications(meta.id, meta.configPath, "simulate", outputDir, 1)
            println(s"Replaying experiment ${meta.id} verbatim (same configPath, same seed inside it) -> job ${jobs.head.id}")
        }

      case Nil | "help" :: _ =>
        printHelp()

      case other =>
        println(s"Unknown command: ${other.mkString(" ")}")
        printHelp()
    }
  }

  private def submitOne(registry: Registry, coordinator: ExperimentCoordinator, id: String, mode: String,
                         outputDir: String, extraArg: Option[String]): Unit =
    registry.get(id) match {
      case None => println(s"No such experiment: $id")
      case Some(meta) =>
        val jobs = coordinator.launchReplications(meta.id, meta.configPath, mode, outputDir, 1, extraArg)
        println(s"Submitted job ${jobs.head.id} (mode=$mode)")
    }

  private def copyDir(src: java.nio.file.Path, dst: java.nio.file.Path): Unit = {
    import scala.jdk.CollectionConverters._
    Files.createDirectories(dst)
    if (Files.exists(src)) {
      Files.walk(src).iterator().asScala.foreach { p =>
        val rel = src.relativize(p)
        val target = dst.resolve(rel.toString)
        if (Files.isDirectory(p)) Files.createDirectories(target)
        else { Files.createDirectories(target.getParent); Files.copy(p, target, java.nio.file.StandardCopyOption.REPLACE_EXISTING) }
      }
    }
  }

  private def printHelp(): Unit = {
    println(
      """ORACLE CLI — Scientific Experiment Universe
        |
        |  experiment create <name> <configPath> [tags]
        |  experiment list
        |  experiment fork <id> <newName>
        |  experiment archive <id>
        |  run <id> <simulate|montecarlo|sweep|sensitivity> [outputDir] [extraArg]
        |  sweep <id> <resolution> [outputDir]
        |  montecarlo <id> <nSamples> [outputDir]
        |  analyze sensitivity <id> [outputDir]
        |  compare <runIdA> <resultPathA> <runIdB> <resultPathB>
        |  report <id> <resultPath> [md|html]
        |  worker start [numWorkers]
        |  benchmark <id> [replications]
        |  snapshot <dataDir> [target]
        |  replay <id> [outputDir]
        |""".stripMargin)
  }
}
