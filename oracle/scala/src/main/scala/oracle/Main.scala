package oracle

/** Entry point.
  *
  *   sbt run                          -> starts the REST API on :8080
  *   sbt "run api 9090"               -> REST API on a custom port
  *   sbt "run worker 8"               -> starts 8 local workers, CLI mode
  *   sbt "run experiment list"        -> any other args go to the Cli object
  *
  * Configuration is intentionally environment-variable driven
  * (ORACLE_DATA_DIR, ORACLE_JULIA_CMD, ORACLE_JULIA_ENTRY) rather than
  * a config-file parser, to keep this module dependency-free.
  */
object Main {
  def main(args: Array[String]): Unit = {
    val dataDir = sys.env.getOrElse("ORACLE_DATA_DIR", "./oracle-data")
    val juliaCommand = sys.env.getOrElse("ORACLE_JULIA_CMD", "julia")
    val juliaEntry = sys.env.getOrElse("ORACLE_JULIA_ENTRY", "../julia/src/run_experiment.jl")
    val numWorkers = sys.env.get("ORACLE_WORKERS").flatMap(s => scala.util.Try(s.toInt).toOption).getOrElse(4)

    val registry = new Registry(dataDir)
    val scheduler = new Scheduler(numWorkers, juliaCommand, juliaEntry)
    val coordinator = new ExperimentCoordinator(scheduler, registry)

    args.toList match {
      case "api" :: rest =>
        val port = rest.headOption.flatMap(s => scala.util.Try(s.toInt).toOption).getOrElse(8080)
        scheduler.start(job => registry.recordRun(RunResult(
          job.id, job.id, job.experimentId, JobStatus.toJson(job.status),
          job.resultPath.getOrElse(""), Map.empty)))
        val api = new ApiServer(port, registry, scheduler, coordinator)
        api.start()
        sys.addShutdownHook {
          println("Shutting down ORACLE API server...")
          api.stop()
          scheduler.shutdown()
        }
        Thread.currentThread().join()

      case Nil =>
        val api = new ApiServer(8080, registry, scheduler, coordinator)
        scheduler.start(_ => ())
        api.start()
        Thread.currentThread().join()

      case other =>
        Cli.run(other.toArray, registry, scheduler, coordinator, juliaCommand, juliaEntry)
    }
  }
}
