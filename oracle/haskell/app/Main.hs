-- | app/Main.hs
--
-- ORACLE's Haskell CLI: the Verification Layer's entry point.
--
--   oracle-validate <experiment.json> [output.json]
--
-- Reads an Experiment Definition (JSON), runs it through the full
-- Rule Engine (Oracle.Validation), prints a human-readable validation
-- report, and — only if there are no blocking (error/fatal) violations
-- — writes the canonical validated JSON that the Julia Simulation
-- Engine and Scala Scheduler consume.
module Main (main) where

import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)
import Control.Monad (forM_, when)

import Oracle.Json
import Oracle.Types
import Oracle.Validation

main :: IO ()
main = do
  args <- getArgs
  case args of
    (inPath:rest) -> run inPath (case rest of (o:_) -> Just o; [] -> Nothing)
    _ -> do
      hPutStrLn stderr "Usage: oracle-validate <experiment.json> [output.json]"
      exitFailure

run :: FilePath -> Maybe FilePath -> IO ()
run inPath outPathM = do
  contents <- readFile inPath
  case parseJson contents of
    Left err -> do
      hPutStrLn stderr ("[JSON ERROR] " ++ err)
      exitFailure
    Right jv -> case parseExperiment jv of
      Left err -> do
        hPutStrLn stderr ("[SCHEMA ERROR] " ++ err)
        exitFailure
      Right ed -> do
        let report = validateExperiment defaultRules ed
            blocking = filter isBlocking (vrViolations report)
        putStrLn ("=== ORACLE Validation Report: " ++ vrExperimentName report ++ " ===")
        if null (vrViolations report)
          then putStrLn "No issues found."
          else forM_ (vrViolations report) $ \v ->
                 putStrLn (bracket (show (vSeverity v)) ++ " [" ++ vRuleId v ++ "] "
                            ++ vLocation v ++ ": " ++ vMessage v)
        putStrLn ("Total violations: " ++ show (length (vrViolations report))
                   ++ " (blocking: " ++ show (length blocking) ++ ")")
        if not (null blocking)
          then do
            hPutStrLn stderr "Validation failed: experiment was NOT exported."
            exitFailure
          else do
            let outPath = case outPathM of
                            Just p -> p
                            Nothing -> "validated_" ++ sanitize (edName ed) ++ ".json"
            writeFile outPath (encodeJsonPretty (exportValidated ed))
            putStrLn ("Validated experiment exported to: " ++ outPath)
            exitSuccess
  where
    bracket s = "[" ++ s ++ "]"
    sanitize = map (\c -> if c `elem` (" /\\:" :: String) then '_' else c)
