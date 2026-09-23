ThisBuild / scalaVersion := "2.13.14"
ThisBuild / organization := "oracle"

lazy val root = (project in file("."))
  .settings(
    name := "oracle-orchestration",
    version := "1.0.0",
    // ORACLE's Scala Orchestration layer runs on nothing but the
    // Scala/JDK standard library (java.util.concurrent, java.nio,
    // com.sun.net.httpserver, scala.sys.process) — no Akka, no circe,
    // no Cats — so `sbt run` never needs to resolve a third-party
    // dependency graph.
    Compile / mainClass := Some("oracle.Main"),
    fork := true,
  )
