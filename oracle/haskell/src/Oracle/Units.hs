-- | Oracle.Units
--
-- A real dimensional-analysis engine over the seven SI base dimensions.
-- Every physical unit string used anywhere in an ORACLE experiment
-- (variables, parameters, constants, equation outputs) is parsed into
-- a 'Dimension' vector of integer exponents. Formulas are then checked
-- so that, e.g., a length can never be added to a time, and an
-- equation's declared output unit must match the dimension actually
-- produced by its right-hand side expression.
module Oracle.Units
  ( Dimension
  , UnitInfo(..)
  , dimensionless
  , baseUnitTable
  , parseUnitString
  , dimEq
  , dimMul
  , dimDiv
  , dimPow
  , showDimension
  ) where

import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import Data.List (foldl')

-- | Exponents of the seven SI base dimensions, keyed by a short code:
--   "L" length, "M" mass, "T" time, "I" electric current,
--   "K" thermodynamic temperature, "N" amount of substance, "J" luminous intensity.
type Dimension = Map String Int

data UnitInfo = UnitInfo
  { uiDimension :: Dimension
  , uiToBase    :: Double  -- ^ multiplicative factor to convert to the SI base unit
  } deriving (Eq, Show)

dimensionless :: Dimension
dimensionless = Map.empty

-- | Table of atomic (non-composite) units ORACLE understands out of the box.
-- Plugins / the Unit & Dimension System can extend this table at the
-- registry level without touching this module.
baseUnitTable :: Map String UnitInfo
baseUnitTable = Map.fromList
  [ ("1",   UnitInfo dimensionless 1)
  , ("rad", UnitInfo dimensionless 1)
  , ("m",   UnitInfo (dim [("L",1)]) 1)
  , ("km",  UnitInfo (dim [("L",1)]) 1000)
  , ("cm",  UnitInfo (dim [("L",1)]) 0.01)
  , ("mm",  UnitInfo (dim [("L",1)]) 0.001)
  , ("s",   UnitInfo (dim [("T",1)]) 1)
  , ("ms",  UnitInfo (dim [("T",1)]) 0.001)
  , ("min", UnitInfo (dim [("T",1)]) 60)
  , ("h",   UnitInfo (dim [("T",1)]) 3600)
  , ("kg",  UnitInfo (dim [("M",1)]) 1)
  , ("g",   UnitInfo (dim [("M",1)]) 0.001)
  , ("A",   UnitInfo (dim [("I",1)]) 1)
  , ("K",   UnitInfo (dim [("K",1)]) 1)
  , ("mol", UnitInfo (dim [("N",1)]) 1)
  , ("cd",  UnitInfo (dim [("J",1)]) 1)
  , ("N",   UnitInfo (dim [("M",1),("L",1),("T",-2)]) 1)
  , ("Pa",  UnitInfo (dim [("M",1),("L",-1),("T",-2)]) 1)
  , ("J",   UnitInfo (dim [("M",1),("L",2),("T",-2)]) 1)
  , ("W",   UnitInfo (dim [("M",1),("L",2),("T",-3)]) 1)
  , ("Hz",  UnitInfo (dim [("T",-1)]) 1)
  , ("V",   UnitInfo (dim [("M",1),("L",2),("T",-3),("I",-1)]) 1)
  , ("Ohm", UnitInfo (dim [("M",1),("L",2),("T",-3),("I",-2)]) 1)
  ]
  where dim = Map.fromList

dimMul :: Dimension -> Dimension -> Dimension
dimMul a b = Map.filter (/= 0) (Map.unionWith (+) a b)

dimDiv :: Dimension -> Dimension -> Dimension
dimDiv a b = dimMul a (Map.map negate b)

dimPow :: Dimension -> Int -> Dimension
dimPow a n = Map.filter (/= 0) (Map.map (* n) a)

dimEq :: Dimension -> Dimension -> Bool
dimEq a b = Map.filter (/= 0) a == Map.filter (/= 0) b

showDimension :: Dimension -> String
showDimension d
  | Map.null clean = "dimensionless"
  | otherwise = unwords [k ++ "^" ++ show v | (k, v) <- Map.toList clean]
  where clean = Map.filter (/= 0) d

-- | Parse a compound unit expression such as @"kg*m/s^2"@ or @"m/s"@ or
-- @"1"@ (dimensionless) into a dimension vector plus the scale factor
-- needed to convert a value expressed in that unit into SI base units.
-- Supports '*' , '/' and integer '^' exponents, left-to-right, with no
-- operator precedence surprises (this mirrors how physicists write
-- compound units in practice).
parseUnitString :: String -> Either String UnitInfo
parseUnitString raw =
  case tokenize raw of
    Left err -> Left err
    Right toks -> combine toks
  where
    tokenize :: String -> Either String [(Char, String)]
    tokenize s = go '*' (filter (/= ' ') s)
      where
        go _ [] = Right []
        go opBefore s' =
          let (tok, rest) = break (`elem` ("*/" :: String)) s'
          in if null tok
               then Left ("Malformed unit expression: " ++ raw)
               else case rest of
                      []        -> Right [(opBefore, tok)]
                      (op:rest') -> ((opBefore, tok) :) <$> go op rest'

    combine :: [(Char, String)] -> Either String UnitInfo
    combine = foldl' step (Right (UnitInfo dimensionless 1))
      where
        step acc (op, tok) = do
          UnitInfo accDim accScale <- acc
          (baseSym, expo) <- parseAtom tok
          info <- maybe (Left ("Unknown base unit: " ++ baseSym)) Right
                        (Map.lookup baseSym baseUnitTable)
          let atomDim   = dimPow (uiDimension info) expo
              atomScale = uiToBase info ** fromIntegral expo
          case op of
            '*' -> Right (UnitInfo (dimMul accDim atomDim) (accScale * atomScale))
            '/' -> Right (UnitInfo (dimDiv accDim atomDim) (accScale / atomScale))
            _   -> Left ("Unsupported unit operator: " ++ [op])

    parseAtom :: String -> Either String (String, Int)
    parseAtom tok = case break (== '^') tok of
      (sym, [])      -> Right (sym, 1)
      (sym, '^':expS) -> case reads expS of
        [(n, "")] -> Right (sym, n)
        _         -> Left ("Invalid exponent in unit: " ++ tok)
      _ -> Left ("Invalid unit atom: " ++ tok)
