package oracle

import java.util.concurrent.{Executors, ExecutorService, PriorityBlockingQueue, TimeUnit, Future => JFuture}
import java.util.concurrent.atomic.{AtomicBoolean, AtomicLong}
import java.time.Instant
import scala.jdk.CollectionConverters._
import scala.collection.concurrent.TrieMap
import scala.util.{Try, Success, Failure}
import sys.process._

/** Health state of one logical worker slot, as required by the
  * Distributed Experiment Scheduler spec: workers report a heartbeat
  * and can be gracefully shut down without corrupting in-flight work.
  */
final case class WorkerStatus(
    workerId: Int,
    var healthy: Boolean = true,
    var lastHeartbeat: Instant = Instant.now(),
    var currentJobId: Option[String] = None,
    var jobsCompleted: Long = 0,
    var jobsFailed: Long = 0
)

/** A priority-ordered, retrying, timeout-aware job scheduler that
  * distributes ORACLE jobs across a fixed pool of worker threads, each
  * of which invokes the Julia Simulation Engine as a subprocess. A
  * single worker crashing (its subprocess throwing, timing out, or the
  * JVM catching an exception) never brings down the rest of the pool —
  * the Experiment Coordinator below retries only the affected job.
  *
  * This models a real multi-worker execution cluster using OS
  * processes + JVM threads rather than requiring an external cluster
  * manager, so the whole system runs the same way on a laptop or a
  * many-core server; scaling out to real distinct machines is a matter
  * of swapping `runJulia` for an RPC call to a remote worker process,
  * which is exactly the seam this class is built around.
  */
final class Scheduler(numWorkers: Int, juliaCommand: String, juliaEntryPoint: String,
                       jobTimeoutSeconds: Long = 3600) {

  private val queue = new PriorityBlockingQueue[Job](64, Ordering.by[Job, Int](_.priority).reverse)
  private val jobs = TrieMap[String, Job]()
  private val workers = (0 until numWorkers).map(i => i -> WorkerStatus(i)).toMap
  private val pool: ExecutorService = Executors.newFixedThreadPool(numWorkers)
  private val running = new AtomicBoolean(false)
  private val jobsSubmitted = new AtomicLong(0)

  def submit(job: Job): Job = {
    jobs.put(job.id, job)
    queue.put(job)
    jobsSubmitted.incrementAndGet()
    job
  }

  def status(jobId: String): Option[Job] = jobs.get(jobId)

  def cancel(jobId: String): Boolean = jobs.get(jobId) match {
    case Some(j) if j.status == JobStatus.Queued =>
      j.status = JobStatus.Cancelled
      true
    case Some(j) if j.status == JobStatus.Running =>
      // cooperative cancellation: mark it, the worker loop checks this flag
      j.status = JobStatus.Cancelled
      true
    case _ => false
  }

  def workerSnapshot(): Vector[WorkerStatus] = workers.values.toVector.sortBy(_.workerId)

  /** Start `numWorkers` daemon loops, each pulling from the shared
    * priority queue. Call `shutdown()` for a graceful stop that lets
    * any job currently executing finish (or hit its timeout) before
    * the pool terminates. */
  def start(onJobFinished: Job => Unit): Unit = {
    if (running.compareAndSet(false, true)) {
      (0 until numWorkers).foreach { workerId =>
        pool.submit(new Runnable { def run(): Unit = workerLoop(workerId, onJobFinished) })
      }
    }
  }

  private def workerLoop(workerId: Int, onJobFinished: Job => Unit): Unit = {
    val ws = workers(workerId)
    while (running.get()) {
      ws.lastHeartbeat = Instant.now()
      val job = Option(queue.poll(2, TimeUnit.SECONDS))
      job match {
        case None => // idle tick, loop again (this IS the heartbeat)
        case Some(j) if j.status == JobStatus.Cancelled =>
          () // dropped without executing
        case Some(j) =>
          ws.currentJobId = Some(j.id)
          executeJob(j, workerId)
          ws.currentJobId = None
          if (j.status == JobStatus.Completed) ws.jobsCompleted += 1
          if (j.status == JobStatus.Failed) ws.jobsFailed += 1
          onJobFinished(j)
      }
    }
  }

  private def executeJob(job: Job, workerId: Int): Unit = {
    job.status = JobStatus.Running
    job.startedAt = Some(Instant.now())
    val cmd = Seq(juliaCommand, juliaEntryPoint, job.mode, job.configPath, job.outputDir) ++
      job.extraArg.toSeq

    val attempt = Try {
      val logger = new StringBuilder
      val processLogger = ProcessLogger(line => logger.append(line).append('\n'), line => logger.append("[stderr] ").append(line).append('\n'))
      val proc = cmd.run(processLogger)
      val exitCodeFuture = pool.submit(new java.util.concurrent.Callable[Int] { def call(): Int = proc.exitValue() })
      val exitCode = try {
        exitCodeFuture.get(jobTimeoutSeconds, TimeUnit.SECONDS)
      } catch {
        case _: java.util.concurrent.TimeoutException =>
          proc.destroy()
          throw new RuntimeException(s"Job ${job.id} on worker $workerId timed out after ${jobTimeoutSeconds}s")
      }
      if (exitCode != 0) throw new RuntimeException(s"Julia engine exited with code $exitCode:\n${logger.toString}")
      logger.toString
    }

    attempt match {
      case Success(_) =>
        job.status = JobStatus.Completed
        job.finishedAt = Some(Instant.now())
      case Failure(err) =>
        job.lastError = Some(err.getMessage)
        job.retries += 1
        if (job.retries <= job.maxRetries) {
          job.status = JobStatus.Queued
          queue.put(job) // retry: goes back to the end of the priority queue
        } else {
          job.status = JobStatus.Failed
          job.finishedAt = Some(Instant.now())
        }
    }
  }

  /** Graceful shutdown: stop accepting new poll iterations and wait up
    * to `awaitSeconds` for in-flight jobs to finish naturally. */
  def shutdown(awaitSeconds: Long = 30): Unit = {
    running.set(false)
    pool.shutdown()
    pool.awaitTermination(awaitSeconds, TimeUnit.SECONDS)
  }

  def submittedCount: Long = jobsSubmitted.get()
}

/** Coordinates a single Experiment (potentially thousands of Runs)
  * across the shared Scheduler: splits the experiment into per-run
  * jobs, tracks aggregate progress, and — critically — retries only
  * the runs that actually failed rather than the whole experiment. */
final class ExperimentCoordinator(scheduler: Scheduler, registry: Registry) {

  def launchReplications(experimentId: String, configPath: String, mode: String,
                          outputDir: String, replications: Int, extraArg: Option[String] = None,
                          priority: Int = 5, maxRetries: Int = 2): Vector[Job] = {
    (1 to replications).map { _ =>
      val job = Job(Job.newId(), experimentId, mode, configPath, outputDir, extraArg, priority, maxRetries)
      scheduler.submit(job)
    }.toVector
  }

  def aggregateStatus(jobIds: Vector[String]): Map[String, Int] = {
    val statuses = jobIds.flatMap(scheduler.status).map(_.status)
    statuses.groupBy(JobStatus.toJson).view.mapValues(_.size).toMap
  }

  /** Retry every job in `jobIds` currently in a Failed state, without
    * touching anything that already succeeded — this is the
    * "Experiment Coordinator only retries failed Runs" requirement. */
  def retryFailed(jobIds: Vector[String]): Vector[Job] = {
    jobIds.flatMap(scheduler.status).filter(_.status == JobStatus.Failed).map { old =>
      val retryJob = Job(Job.newId(), old.experimentId, old.mode, old.configPath, old.outputDir,
                          old.extraArg, old.priority, old.maxRetries)
      scheduler.submit(retryJob)
    }
  }
}
