-- | Oracle.Types
--
-- The typed representation of an ORACLE Experiment Definition: the
-- structured object every other engine (Julia's Simulation Engine,
-- Scala's Scheduler, the Web UI) agrees on. This module parses the
-- shared JSON experiment schema into strongly typed Haskell values so
-- the rest of the formal layer (Oracle.Validation) can reason about it
-- with the full power of the type system instead of raw JSON.
module Oracle.Types
  ( Distribution(..)
  , VariableKind(..)
  , VarSpec(..)
  , Constant(..)
  , Equation(..)
  , Constraint(..)
  , Solver(..)
  , Objective(..)
  , ExperimentDef(..)
  , parseExperiment
  ) where

import Oracle.Json
import Oracle.Formula (Expr, parseFormula)
import Data.Maybe (fromMaybe)

data Distribution
  = DUniform Double Double
  | DNormal Double Double
  | DLogNormal Double Double
  | DCategorical [String]
  | DConstant Double
  deriving (Eq, Show)

data VariableKind
  = KScalar | KVector | KMatrix | KTimeSeries
  | KCategorical | KBoolean | KInteger
  deriving (Eq, Show)

data VarSpec = VarSpec
  { vsName         :: String
  , vsKind         :: VariableKind
  , vsUnit         :: Maybe String
  , vsDefault      :: Maybe Double
  , vsMin          :: Maybe Double
  , vsMax          :: Maybe Double
  , vsDistribution :: Maybe Distribution
  , vsDoc          :: Maybe String
  } deriving (Eq, Show)

data Constant = Constant
  { cName  :: String
  , cValue :: Double
  , cUnit  :: Maybe String
  } deriving (Eq, Show)

data Equation = Equation
  { eqOutput :: String
  , eqExpr   :: Expr
  , eqExprSrc:: String
  , eqUnit   :: Maybe String
  } deriving (Eq, Show)

data Constraint = Constraint
  { conExprSrc  :: String
  , conExpr     :: Expr
  , conSeverity :: String -- "info" | "warning" | "error" | "fatal"
  } deriving (Eq, Show)

data Solver = Solver
  { solMethod   :: String -- "euler" | "rk4" | "rk45"
  , solStep     :: Double
  , solTol      :: Double
  , solMaxSteps :: Int
  } deriving (Eq, Show)

data Objective = Objective
  { objKind :: String -- "minimize" | "maximize"
  , objExpr :: Expr
  , objSrc  :: String
  } deriving (Eq, Show)

data ExperimentDef = ExperimentDef
  { edName             :: String
  , edDescription      :: String
  , edVariables        :: [VarSpec]
  , edParameters       :: [VarSpec]
  , edConstants        :: [Constant]
  , edEquations        :: [Equation]
  , edConstraints      :: [Constraint]
  , edInitialConditions:: [(String, Double)]
  , edSolver           :: Solver
  , edSeed             :: Int
  , edObjective        :: Maybe Objective
  , edMetrics          :: [String]
  , edStopConditions   :: [Expr]
  , edReplications     :: Int
  , edTimeRange        :: (Double, Double)
  , edSamplingRate     :: Double
  , edOutputSchema     :: [String]
  } deriving (Show)

-- Parsing --------------------------------------------------------------

note :: String -> Maybe a -> Either String a
note msg Nothing  = Left msg
note _   (Just x) = Right x

getField :: String -> JValue -> Either String JValue
getField k v = note ("Missing required field: " ++ k) (jLookup k v)

optField :: String -> JValue -> Maybe JValue
optField = jLookup

parseExperiment :: JValue -> Either String ExperimentDef
parseExperiment v = do
  name <- getField "name" v >>= req jGetString "name must be a string"
  let description = fromMaybe "" (optField "description" v >>= jGetString)
  varsJ <- maybe (Right []) req' (optField "variables" v)
  vars <- mapM parseVarSpec varsJ
  paramsJ <- maybe (Right []) req' (optField "parameters" v)
  params <- mapM parseVarSpec paramsJ
  constsJ <- maybe (Right []) req' (optField "constants" v)
  consts <- mapM parseConstant constsJ
  eqsJ <- getField "equations" v >>= req jGetArray "equations must be an array"
  eqs <- mapM parseEquation eqsJ
  consJ <- maybe (Right []) req' (optField "constraints" v)
  cons <- mapM parseConstraint consJ
  initJ <- maybe (Right []) (req jGetObject "initialConditions must be an object")
                 (optField "initialConditions" v)
  initConds <- mapM (\(k, val) -> (,) k <$> req jGetDouble (k ++ " must be numeric") val) initJ
  solverJ <- getField "solver" v
  solver <- parseSolver solverJ
  let seedVal = fromMaybe 0 (optField "seed" v >>= jGetInt)
  objective <- case optField "objective" v of
    Nothing -> Right Nothing
    Just oj -> Just <$> parseObjective oj
  let metrics = fromMaybe [] (optField "metrics" v >>= jGetArray >>= mapM jGetString)
  stopJ <- maybe (Right []) (req jGetArray "stopConditions must be an array")
                (optField "stopConditions" v)
  stopExprs <- mapM (\sj -> req jGetString "stop condition must be a string" sj >>= parseF) stopJ
  let replications = fromMaybe 1 (optField "replications" v >>= jGetInt)
  timeRange <- case optField "timeRange" v >>= jGetArray of
    Just [a, b] -> (,) <$> req jGetDouble "timeRange[0]" a <*> req jGetDouble "timeRange[1]" b
    Just _      -> Left "timeRange must be a 2-element array [start, end]"
    Nothing     -> Right (0, 1)
  let samplingRate = fromMaybe 1.0 (optField "samplingRate" v >>= jGetDouble)
  let outputSchema = fromMaybe [] (optField "outputSchema" v >>= jGetArray >>= mapM jGetString)
  Right ExperimentDef
    { edName = name, edDescription = description
    , edVariables = vars, edParameters = params, edConstants = consts
    , edEquations = eqs, edConstraints = cons
    , edInitialConditions = initConds, edSolver = solver
    , edSeed = seedVal, edObjective = objective, edMetrics = metrics
    , edStopConditions = stopExprs, edReplications = replications
    , edTimeRange = timeRange, edSamplingRate = samplingRate
    , edOutputSchema = outputSchema
    }
  where
    req getter msg jv = note msg (getter jv)
    req' jv = note "expected a JSON array" (jGetArray jv)
    parseF s = parseFormula s

parseVarSpec :: JValue -> Either String VarSpec
parseVarSpec v = do
  name <- getField "name" v >>= req jGetString "variable/parameter name must be a string"
  let kindStr = fromMaybe "scalar" (optField "kind" v >>= jGetString)
  kind <- parseKind kindStr
  let unit = optField "unit" v >>= jGetString
      def  = optField "default" v >>= jGetDouble
      mn   = optField "min" v >>= jGetDouble
      mx   = optField "max" v >>= jGetDouble
      doc  = optField "doc" v >>= jGetString
  dist <- case optField "distribution" v of
    Nothing -> Right Nothing
    Just dj -> Just <$> parseDistribution dj
  Right (VarSpec name kind unit def mn mx dist doc)
  where req getter msg jv = note msg (getter jv)

parseKind :: String -> Either String VariableKind
parseKind "scalar"       = Right KScalar
parseKind "vector"       = Right KVector
parseKind "matrix"       = Right KMatrix
parseKind "time_series"  = Right KTimeSeries
parseKind "categorical"  = Right KCategorical
parseKind "boolean"      = Right KBoolean
parseKind "integer"      = Right KInteger
parseKind other          = Left ("Unknown variable kind: " ++ other)

parseDistribution :: JValue -> Either String Distribution
parseDistribution v = do
  t <- getField "type" v >>= req jGetString "distribution type must be a string"
  case t of
    "uniform"    -> DUniform    <$> num "low" <*> num "high"
    "normal"     -> DNormal     <$> num "mean" <*> num "std"
    "lognormal"  -> DLogNormal  <$> num "mu" <*> num "sigma"
    "constant"   -> DConstant   <$> num "value"
    "categorical"-> DCategorical <$> (getField "values" v >>= req jGetArray "values must be an array" >>= mapM (req jGetString "category must be a string"))
    other        -> Left ("Unknown distribution type: " ++ other)
  where
    req getter msg jv = note msg (getter jv)
    num k = getField k v >>= req jGetDouble (k ++ " must be numeric")

parseConstant :: JValue -> Either String Constant
parseConstant v = do
  name <- getField "name" v >>= req jGetString "constant name must be a string"
  value <- getField "value" v >>= req jGetDouble "constant value must be numeric"
  let unit = optField "unit" v >>= jGetString
  Right (Constant name value unit)
  where req getter msg jv = note msg (getter jv)

parseEquation :: JValue -> Either String Equation
parseEquation v = do
  output <- getField "output" v >>= req jGetString "equation 'output' must be a string"
  src <- getField "expr" v >>= req jGetString "equation 'expr' must be a string"
  expr <- parseFormula src
  let unit = optField "unit" v >>= jGetString
  Right (Equation output expr src unit)
  where req getter msg jv = note msg (getter jv)

parseConstraint :: JValue -> Either String Constraint
parseConstraint v = do
  src <- getField "expr" v >>= req jGetString "constraint 'expr' must be a string"
  expr <- parseFormula src
  let sev = fromMaybe "error" (optField "severity" v >>= jGetString)
  Right (Constraint src expr sev)
  where req getter msg jv = note msg (getter jv)

parseSolver :: JValue -> Either String Solver
parseSolver v = do
  let method   = fromMaybe "rk4" (optField "method" v >>= jGetString)
      step     = fromMaybe 0.01 (optField "stepSize" v >>= jGetDouble)
      tol      = fromMaybe 1.0e-6 (optField "tolerance" v >>= jGetDouble)
      maxSteps = fromMaybe 1000000 (optField "maxSteps" v >>= jGetInt)
  Right (Solver method step tol maxSteps)

parseObjective :: JValue -> Either String Objective
parseObjective v = do
  kind <- getField "type" v >>= req jGetString "objective 'type' must be a string"
  src <- getField "expr" v >>= req jGetString "objective 'expr' must be a string"
  expr <- parseFormula src
  Right (Objective kind expr src)
  where req getter msg jv = note msg (getter jv)
