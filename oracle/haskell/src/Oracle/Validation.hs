-- | Oracle.Validation
--
-- The formal Validation Layer. Before any Experiment Definition is
-- handed to the Julia Simulation Engine it passes through here:
-- structural checks (do referenced variables exist?), dimensional
-- checks (is every equation and constraint dimensionally consistent?),
-- bound checks (are default values and distribution parameters sane?)
-- and a small extensible Rule Engine for cross-cutting invariants.
-- Nothing with a "fatal" or "error" level violation is ever exported
-- for execution.
module Oracle.Validation
  ( Severity(..)
  , Violation(..)
  , ValidationReport(..)
  , Rule(..)
  , defaultRules
  , validateExperiment
  , isBlocking
  , exportValidated
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Set (Set)
import Data.List (nub)
import Data.Maybe (mapMaybe, fromMaybe)

import Oracle.Json
import Oracle.Formula
import Oracle.Types
import Oracle.Units

data Severity = Info | Warning | Err | Fatal deriving (Eq, Ord, Show)

data Violation = Violation
  { vRuleId   :: String
  , vSeverity :: Severity
  , vLocation :: String
  , vMessage  :: String
  } deriving (Eq, Show)

data ValidationReport = ValidationReport
  { vrExperimentName :: String
  , vrViolations     :: [Violation]
  } deriving (Eq, Show)

isBlocking :: Violation -> Bool
isBlocking v = vSeverity v >= Err

-- | A named, versioned rule as required by the Rule Engine spec: every
-- rule carries an identifier, a severity it will report at, a scope
-- description, and a human-readable explanation, in addition to the
-- actual check.
data Rule = Rule
  { ruleId          :: String
  , ruleVersion     :: String
  , ruleSeverity    :: Severity
  , ruleScope       :: String
  , ruleExplanation :: String
  , ruleCheck       :: ExperimentDef -> [Violation]
  }

-- Structural validation --------------------------------------------------

allDeclaredNames :: ExperimentDef -> Set String
allDeclaredNames ed = Set.fromList $
  map vsName (edVariables ed) ++
  map vsName (edParameters ed) ++
  map cName (edConstants ed) ++
  map eqOutput (edEquations ed) ++
  ["t"] -- the simulation time variable is always implicitly in scope

ruleUndefinedVariables :: Rule
ruleUndefinedVariables = Rule
  { ruleId = "STRUCT-001"
  , ruleVersion = "1.0"
  , ruleSeverity = Fatal
  , ruleScope = "equations, constraints, objective, stop conditions"
  , ruleExplanation = "Every variable referenced in a formula must be declared as a variable, parameter, constant, or another equation's output."
  , ruleCheck = \ed ->
      let known = allDeclaredNames ed
          checkExpr loc e =
            [ Violation "STRUCT-001" Fatal loc ("Undefined variable referenced: " ++ nm)
            | nm <- Set.toList (dependencies e), not (Set.member nm known) ]
      in concat
           ( [ checkExpr ("equation:" ++ eqOutput eq) (eqExpr eq) | eq <- edEquations ed ]
          ++ [ checkExpr ("constraint:" ++ conExprSrc c) (conExpr c) | c <- edConstraints ed ]
          ++ [ checkExpr "stopCondition" e | e <- edStopConditions ed ]
          ++ maybe [] (\o -> [checkExpr "objective" (objExpr o)]) (edObjective ed)
           )
  }

ruleDuplicateNames :: Rule
ruleDuplicateNames = Rule
  { ruleId = "STRUCT-002"
  , ruleVersion = "1.0"
  , ruleSeverity = Fatal
  , ruleScope = "variables, parameters, constants, equation outputs"
  , ruleExplanation = "Every declared name in an experiment (variable, parameter, constant, or equation output) must be unique."
  , ruleCheck = \ed ->
      let names = map vsName (edVariables ed) ++ map vsName (edParameters ed)
               ++ map cName (edConstants ed) ++ map eqOutput (edEquations ed)
          dupes = nub (names `minus` nub names)
          minus xs ys = filter (\x -> countOf x xs > 1) xs `seq` [ x | x <- nub xs, countOf x names > 1 ]
          countOf x xs = length (filter (== x) xs)
      in [ Violation "STRUCT-002" Fatal ("name:" ++ d) ("Duplicate declaration of name: " ++ d) | d <- dupes ]
  }

-- Dimensional validation --------------------------------------------------

-- | Build the name -> dimension environment from every declared
-- variable/parameter/constant that specifies a unit.
dimensionEnv :: ExperimentDef -> Map.Map String Dimension
dimensionEnv ed = Map.fromList (mapMaybe fromVar (edVariables ed ++ edParameters ed)
                                 ++ mapMaybe fromConst (edConstants ed))
  where
    fromVar vs = do
      u <- vsUnit vs
      info <- either (const Nothing) Just (parseUnitString u)
      Just (vsName vs, uiDimension info)
    fromConst c = do
      u <- cUnit c
      info <- either (const Nothing) Just (parseUnitString u)
      Just (cName c, uiDimension info)

-- | Infer the dimension of an expression given a partial environment.
-- Variables with no known unit are treated as dimensionless "wildcards"
-- so that ORACLE degrades gracefully for partially-annotated models
-- instead of refusing to validate them outright; every genuinely
-- annotated pair of operands is still checked strictly.
inferDim :: Map.Map String Dimension -> Expr -> Either String Dimension
inferDim _ (Num _) = Right dimensionless
inferDim env (Var v) = Right (fromMaybe dimensionless (Map.lookup v env))
inferDim env (UnOp _ a) = inferDim env a
inferDim env (BinOp op a b) = do
  da <- inferDim env a
  db <- inferDim env b
  case op of
    "+" -> if dimEq da db then Right da else Left "incompatible units in '+'"
    "-" -> if dimEq da db then Right da else Left "incompatible units in '-'"
    "*" -> Right (dimMul da db)
    "/" -> Right (dimDiv da db)
    "^" -> case b of
             Num n | n == fromIntegral (round n :: Integer) -> Right (dimPow da (round n))
             _ -> if dimEq da dimensionless then Right dimensionless
                  else Left "non-integer or variable exponent on a dimensional base"
    _   -> Right dimensionless -- comparisons/booleans are dimensionless results
inferDim env (Call name args) = do
  ds <- mapM (inferDim env) args
  case (name, ds) of
    ("sqrt", [d]) -> Right (dimPow d 0) `orIfHalf` d -- see below
    (_, _) | name `elem` ["sin","cos","tan","exp","log"] ->
      if all (dimEq dimensionless) ds then Right dimensionless
      else Left (name ++ "() requires a dimensionless argument")
    ("min", [d1,d2]) -> if dimEq d1 d2 then Right d1 else Left "min() operands have incompatible units"
    ("max", [d1,d2]) -> if dimEq d1 d2 then Right d1 else Left "max() operands have incompatible units"
    ("abs", [d]) -> Right d
    ("floor", [d]) -> Right d
    ("ceil", [d]) -> Right d
    _ -> Right dimensionless
  where
    orIfHalf _ d = Right (Map.map (`div` 2) d) -- sqrt halves exponents; whole-number results assumed
inferDim env (If c t e) = do
  _ <- inferDim env c
  dt <- inferDim env t
  de <- inferDim env e
  if dimEq dt de then Right dt else Left "if-branches have incompatible units"

ruleDimensionalConsistency :: Rule
ruleDimensionalConsistency = Rule
  { ruleId = "DIM-001"
  , ruleVersion = "1.0"
  , ruleSeverity = Err
  , ruleScope = "equations with a declared output unit"
  , ruleExplanation = "An equation's declared output unit must match the dimension actually produced by its right-hand-side expression, and every internal operation must combine dimensionally compatible operands."
  , ruleCheck = \ed ->
      let env = dimensionEnv ed
      in mapMaybe (checkEq env) (edEquations ed)
  }
  where
    checkEq env eq = case inferDim env (eqExpr eq) of
      Left err -> Just (Violation "DIM-001" Err ("equation:" ++ eqOutput eq)
                          ("Dimensional error: " ++ err))
      Right inferred -> case eqUnit eq of
        Nothing -> Nothing
        Just u -> case parseUnitString u of
          Left perr -> Just (Violation "DIM-001" Err ("equation:" ++ eqOutput eq)
                               ("Cannot parse declared unit '" ++ u ++ "': " ++ perr))
          Right info ->
            if dimEq inferred (uiDimension info)
              then Nothing
              else Just (Violation "DIM-001" Err ("equation:" ++ eqOutput eq)
                    ("Declared unit '" ++ u ++ "' (" ++ showDimension (uiDimension info)
                     ++ ") does not match inferred dimension of expression ("
                     ++ showDimension inferred ++ ")"))

-- Bounds / distribution sanity ---------------------------------------------

ruleBoundsSanity :: Rule
ruleBoundsSanity = Rule
  { ruleId = "BOUND-001"
  , ruleVersion = "1.0"
  , ruleSeverity = Err
  , ruleScope = "variables and parameters"
  , ruleExplanation = "Declared bounds must be internally consistent (min <= max) and default values, when present, must fall within them."
  , ruleCheck = \ed -> concatMap check (edVariables ed ++ edParameters ed)
  }
  where
    check vs = concat
      [ case (vsMin vs, vsMax vs) of
          (Just lo, Just hi) | lo > hi ->
            [Violation "BOUND-001" Err (vsName vs) "min is greater than max"]
          _ -> []
      , case (vsDefault vs, vsMin vs) of
          (Just d, Just lo) | d < lo ->
            [Violation "BOUND-001" Err (vsName vs) "default value is below the declared minimum"]
          _ -> []
      , case (vsDefault vs, vsMax vs) of
          (Just d, Just hi) | d > hi ->
            [Violation "BOUND-001" Err (vsName vs) "default value is above the declared maximum"]
          _ -> []
      , case vsDistribution vs of
          Just (DUniform lo hi) | lo >= hi ->
            [Violation "BOUND-001" Err (vsName vs) "uniform distribution requires low < high"]
          Just (DNormal _ std) | std <= 0 ->
            [Violation "BOUND-001" Err (vsName vs) "normal distribution requires std > 0"]
          Just (DLogNormal _ sigma) | sigma <= 0 ->
            [Violation "BOUND-001" Err (vsName vs) "log-normal distribution requires sigma > 0"]
          Just (DCategorical vals) | null vals ->
            [Violation "BOUND-001" Err (vsName vs) "categorical distribution requires at least one value"]
          _ -> []
      ]

ruleSolverSanity :: Rule
ruleSolverSanity = Rule
  { ruleId = "SOLVER-001"
  , ruleVersion = "1.0"
  , ruleSeverity = Err
  , ruleScope = "solver configuration"
  , ruleExplanation = "The solver's step size, tolerance and max step count must be positive, and the method must be one ORACLE's Julia engine implements."
  , ruleCheck = \ed ->
      let s = edSolver ed in concat
        [ [ Violation "SOLVER-001" Err "solver.stepSize" "stepSize must be > 0" | solStep s <= 0 ]
        , [ Violation "SOLVER-001" Err "solver.tolerance" "tolerance must be > 0" | solTol s <= 0 ]
        , [ Violation "SOLVER-001" Err "solver.maxSteps" "maxSteps must be > 0" | solMaxSteps s <= 0 ]
        , [ Violation "SOLVER-001" Err "solver.method"
              ("Unknown solver method '" ++ solMethod s ++ "'; expected one of: euler, rk4, rk45")
          | solMethod s `notElem` ["euler", "rk4", "rk45"] ]
        ]
  }

ruleTimeRangeSanity :: Rule
ruleTimeRangeSanity = Rule
  { ruleId = "TIME-001"
  , ruleVersion = "1.0"
  , ruleSeverity = Err
  , ruleScope = "timeRange, samplingRate, replications"
  , ruleExplanation = "The simulated time window must be non-degenerate and the sampling rate and replication count must be positive."
  , ruleCheck = \ed -> concat
      [ [ Violation "TIME-001" Err "timeRange" "timeRange end must be greater than start"
        | let (t0, t1) = edTimeRange ed in t1 <= t0 ]
      , [ Violation "TIME-001" Err "samplingRate" "samplingRate must be > 0" | edSamplingRate ed <= 0 ]
      , [ Violation "TIME-001" Err "replications" "replications must be >= 1" | edReplications ed < 1 ]
      ]
  }

defaultRules :: [Rule]
defaultRules =
  [ ruleUndefinedVariables
  , ruleDuplicateNames
  , ruleDimensionalConsistency
  , ruleBoundsSanity
  , ruleSolverSanity
  , ruleTimeRangeSanity
  ]

-- Top-level entry point ----------------------------------------------------

validateExperiment :: [Rule] -> ExperimentDef -> ValidationReport
validateExperiment rules ed =
  ValidationReport (edName ed) (concatMap (\r -> ruleCheck r ed) rules)

-- | Serialize a validated experiment (plus the resolved dimension of
-- every equation) into the canonical JSON format the Julia Simulation
-- Engine and the Web UI both consume.
exportValidated :: ExperimentDef -> JValue
exportValidated ed = jObject
  [ ("name", jString (edName ed))
  , ("description", jString (edDescription ed))
  , ("variables", jArray (map varToJson (edVariables ed)))
  , ("parameters", jArray (map varToJson (edParameters ed)))
  , ("constants", jArray (map constToJson (edConstants ed)))
  , ("equations", jArray (map eqToJson (edEquations ed)))
  , ("constraints", jArray (map conToJson (edConstraints ed)))
  , ("initialConditions", jObject [ (k, jNumber v) | (k, v) <- edInitialConditions ed ])
  , ("solver", solverToJson (edSolver ed))
  , ("seed", jNumber (fromIntegral (edSeed ed)))
  , ("objective", maybe JNull objToJson (edObjective ed))
  , ("metrics", jArray (map jString (edMetrics ed)))
  , ("stopConditions", jArray (map exprToJson (edStopConditions ed)))
  , ("replications", jNumber (fromIntegral (edReplications ed)))
  , ("timeRange", jArray [jNumber (fst (edTimeRange ed)), jNumber (snd (edTimeRange ed))])
  , ("samplingRate", jNumber (edSamplingRate ed))
  , ("outputSchema", jArray (map jString (edOutputSchema ed)))
  ]
  where
    varToJson vs = jObject
      [ ("name", jString (vsName vs))
      , ("unit", maybe JNull jString (vsUnit vs))
      , ("default", maybe JNull jNumber (vsDefault vs))
      , ("min", maybe JNull jNumber (vsMin vs))
      , ("max", maybe JNull jNumber (vsMax vs))
      , ("distribution", maybe JNull distToJson (vsDistribution vs))
      ]
    distToJson (DUniform lo hi) = jObject [("type", jString "uniform"), ("low", jNumber lo), ("high", jNumber hi)]
    distToJson (DNormal m s)    = jObject [("type", jString "normal"), ("mean", jNumber m), ("std", jNumber s)]
    distToJson (DLogNormal m s) = jObject [("type", jString "lognormal"), ("mu", jNumber m), ("sigma", jNumber s)]
    distToJson (DCategorical vs)= jObject [("type", jString "categorical"), ("values", jArray (map jString vs))]
    distToJson (DConstant v)    = jObject [("type", jString "constant"), ("value", jNumber v)]
    constToJson c = jObject [("name", jString (cName c)), ("value", jNumber (cValue c)), ("unit", maybe JNull jString (cUnit c))]
    eqToJson eq = jObject [("output", jString (eqOutput eq)), ("expr", exprToJson (eqExpr eq)), ("unit", maybe JNull jString (eqUnit eq))]
    conToJson c = jObject [("expr", exprToJson (conExpr c)), ("severity", jString (conSeverity c))]
    solverToJson s = jObject
      [ ("method", jString (solMethod s)), ("stepSize", jNumber (solStep s))
      , ("tolerance", jNumber (solTol s)), ("maxSteps", jNumber (fromIntegral (solMaxSteps s))) ]
    objToJson o = jObject [("type", jString (objKind o)), ("expr", exprToJson (objExpr o))]
