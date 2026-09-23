-- | Oracle.Formula
--
-- The typed scientific expression language shared by every ORACLE
-- experiment. A formula such as @"-k * x + sin(omega * t)"@ is
-- tokenized, parsed into an 'Expr' AST, checked for undefined
-- variables / dependency cycles, and can be evaluated directly (for
-- constants and quick checks) or exported to the shared JSON AST
-- format that the Julia Simulation Engine consumes.
module Oracle.Formula
  ( Expr(..)
  , ParseError
  , tokenize
  , Token(..)
  , parseFormula
  , dependencies
  , evalExpr
  , exprToJson
  , exprFromJson
  ) where

import qualified Data.Set as Set
import Data.Set (Set)
import Data.Char (isDigit, isAlpha, isAlphaNum, isSpace)
import Oracle.Json

type ParseError = String

data Expr
  = Num Double
  | Var String
  | BinOp String Expr Expr   -- ^ "+","-","*","/","^","<","<=",">",">=","==","!="
  | UnOp String Expr         -- ^ "-", "!"
  | Call String [Expr]       -- ^ sin, cos, tan, exp, log, sqrt, abs, min, max, ...
  | If Expr Expr Expr
  deriving (Eq, Show)

-- Tokenizer ------------------------------------------------------------

data Token
  = TNum Double
  | TIdent String
  | TOp String
  | TLParen
  | TRParen
  | TComma
  deriving (Eq, Show)

tokenize :: String -> Either ParseError [Token]
tokenize [] = Right []
tokenize (c:cs)
  | isSpace c = tokenize cs
  | c == '(' = (TLParen :) <$> tokenize cs
  | c == ')' = (TRParen :) <$> tokenize cs
  | c == ',' = (TComma :) <$> tokenize cs
  | isDigit c || (c == '.' && not (null cs) && isDigit (head cs)) =
      let (numStr, rest) = span (\x -> isDigit x || x `elem` (".eE+-" :: String) ) (c:cs)
          numStr' = fixup numStr
      in case reads numStr' :: [(Double, String)] of
           [(n, "")] -> (TNum n :) <$> tokenize rest
           _         -> Left ("Invalid numeric literal near: " ++ take 10 (c:cs))
  | isAlpha c || c == '_' =
      let (ident, rest) = span (\x -> isAlphaNum x || x == '_') (c:cs)
      in (TIdent ident :) <$> tokenize rest
  | c `elem` ("<>=!" :: String) =
      case cs of
        ('=':rest) -> (TOp [c,'='] :) <$> tokenize rest
        _          -> (TOp [c] :) <$> tokenize cs
  | c `elem` ("+-*/^" :: String) = (TOp [c] :) <$> tokenize cs
  | otherwise = Left ("Unexpected character in formula: " ++ [c])
  where
    -- guard against runaway exponent scanning grabbing a following '-' that
    -- belongs to the next operator, e.g. "3-4" must not be read as "3e-4"-like.
    fixup s = s

-- Parser (recursive descent, standard precedence climbing) -------------

parseFormula :: String -> Either ParseError Expr
parseFormula s = do
  toks <- tokenize s
  (e, rest) <- pOr toks
  if null rest
    then Right e
    else Left ("Unexpected trailing tokens: " ++ show rest)

type P a = [Token] -> Either ParseError (a, [Token])

pOr :: P Expr
pOr toks = do
  (l, rest) <- pAnd toks
  go l rest
  where
    go l (TIdent "or":rest) = do (r, rest') <- pAnd rest; go (BinOp "||" l r) rest'
    go l rest = Right (l, rest)

pAnd :: P Expr
pAnd toks = do
  (l, rest) <- pCompare toks
  go l rest
  where
    go l (TIdent "and":rest) = do (r, rest') <- pCompare rest; go (BinOp "&&" l r) rest'
    go l rest = Right (l, rest)

pCompare :: P Expr
pCompare toks = do
  (l, rest) <- pAdd toks
  case rest of
    (TOp op:rest') | op `elem` ["<", "<=", ">", ">=", "==", "!="] -> do
      (r, rest'') <- pAdd rest'
      Right (BinOp op l r, rest'')
    _ -> Right (l, rest)

pAdd :: P Expr
pAdd toks = do
  (l, rest) <- pMul toks
  go l rest
  where
    go l (TOp op:rest) | op `elem` ["+","-"] = do
      (r, rest') <- pMul rest
      go (BinOp op l r) rest'
    go l rest = Right (l, rest)

pMul :: P Expr
pMul toks = do
  (l, rest) <- pUnary toks
  go l rest
  where
    go l (TOp op:rest) | op `elem` ["*","/"] = do
      (r, rest') <- pUnary rest
      go (BinOp op l r) rest'
    go l rest = Right (l, rest)

pUnary :: P Expr
pUnary (TOp "-":rest) = do (e, rest') <- pUnary rest; Right (UnOp "-" e, rest')
pUnary (TOp "!":rest) = do (e, rest') <- pUnary rest; Right (UnOp "!" e, rest')
pUnary toks = pPow toks

pPow :: P Expr
pPow toks = do
  (l, rest) <- pAtom toks
  case rest of
    (TOp "^":rest') -> do (r, rest'') <- pUnary rest'; Right (BinOp "^" l r, rest'')
    _ -> Right (l, rest)

pAtom :: P Expr
pAtom (TNum n:rest) = Right (Num n, rest)
pAtom (TIdent "if":TLParen:rest) = do
  (c, rest1) <- pOr rest
  rest2 <- expectComma rest1
  (t, rest3) <- pOr rest2
  rest4 <- expectComma rest3
  (e, rest5) <- pOr rest4
  rest6 <- expectRParen rest5
  Right (If c t e, rest6)
pAtom (TIdent name:TLParen:rest) = do
  (args, rest') <- pArgs rest
  Right (Call name args, rest')
pAtom (TIdent name:rest) = Right (Var name, rest)
pAtom (TLParen:rest) = do
  (e, rest') <- pOr rest
  rest'' <- expectRParen rest'
  Right (e, rest'')
pAtom toks = Left ("Expected a value but found: " ++ show (take 3 toks))

pArgs :: P [Expr]
pArgs (TRParen:rest) = Right ([], rest)
pArgs toks = do
  (e, rest) <- pOr toks
  case rest of
    (TComma:rest') -> do (es, rest'') <- pArgs rest'; Right (e:es, rest'')
    (TRParen:rest') -> Right ([e], rest')
    _ -> Left ("Expected ',' or ')' in argument list near: " ++ show (take 3 rest))

expectComma :: [Token] -> Either ParseError [Token]
expectComma (TComma:rest) = Right rest
expectComma toks = Left ("Expected ',' near: " ++ show (take 3 toks))

expectRParen :: [Token] -> Either ParseError [Token]
expectRParen (TRParen:rest) = Right rest
expectRParen toks = Left ("Expected ')' near: " ++ show (take 3 toks))

-- Analysis ---------------------------------------------------------------

-- | Every free variable referenced by an expression. Used both by the
-- Rule Engine (to check "all referenced variables are declared") and by
-- the Formula Dependency Graph (to know which outputs are affected when
-- a variable's definition changes).
dependencies :: Expr -> Set String
dependencies (Num _)          = Set.empty
dependencies (Var v)          = Set.singleton v
dependencies (BinOp _ a b)    = Set.union (dependencies a) (dependencies b)
dependencies (UnOp _ a)       = dependencies a
dependencies (Call _ args)    = Set.unions (map dependencies args)
dependencies (If c t e)       = Set.unions [dependencies c, dependencies t, dependencies e]

-- | Direct numeric evaluation given a fully-bound environment. This is
-- used by the Haskell layer for constant-folding and for validating
-- default/initial values before a run is ever handed to Julia; the
-- Julia Simulation Engine has its own evaluator for the hot path.
evalExpr :: [(String, Double)] -> Expr -> Either String Double
evalExpr _ (Num n) = Right n
evalExpr env (Var v) = maybe (Left ("Undefined variable: " ++ v)) Right (lookup v env)
evalExpr env (UnOp "-" a) = negate <$> evalExpr env a
evalExpr env (UnOp "!" a) = (\x -> if x == 0 then 1 else 0) <$> evalExpr env a
evalExpr _   (UnOp op _)  = Left ("Unknown unary operator: " ++ op)
evalExpr env (BinOp op a b) = do
  x <- evalExpr env a
  y <- evalExpr env b
  case op of
    "+"  -> Right (x + y)
    "-"  -> Right (x - y)
    "*"  -> Right (x * y)
    "/"  -> if y == 0 then Left "Division by zero" else Right (x / y)
    "^"  -> Right (x ** y)
    "<"  -> Right (bool01 (x < y))
    "<=" -> Right (bool01 (x <= y))
    ">"  -> Right (bool01 (x > y))
    ">=" -> Right (bool01 (x >= y))
    "==" -> Right (bool01 (x == y))
    "!=" -> Right (bool01 (x /= y))
    "&&" -> Right (bool01 (x /= 0 && y /= 0))
    "||" -> Right (bool01 (x /= 0 || y /= 0))
    _    -> Left ("Unknown binary operator: " ++ op)
  where bool01 b = if b then 1 else 0
evalExpr env (Call name args) = do
  xs <- mapM (evalExpr env) args
  applyFn name xs
evalExpr env (If c t e) = do
  cv <- evalExpr env c
  if cv /= 0 then evalExpr env t else evalExpr env e

applyFn :: String -> [Double] -> Either String Double
applyFn "sin"  [x]   = Right (sin x)
applyFn "cos"  [x]   = Right (cos x)
applyFn "tan"  [x]   = Right (tan x)
applyFn "exp"  [x]   = Right (exp x)
applyFn "log"  [x]   = if x > 0 then Right (log x) else Left "log of non-positive value"
applyFn "sqrt" [x]   = if x >= 0 then Right (sqrt x) else Left "sqrt of negative value"
applyFn "abs"  [x]   = Right (abs x)
applyFn "min"  [x,y] = Right (min x y)
applyFn "max"  [x,y] = Right (max x y)
applyFn "floor" [x]  = Right (fromIntegral (floor x :: Integer))
applyFn "ceil"  [x]  = Right (fromIntegral (ceiling x :: Integer))
applyFn name args    = Left ("Unknown function or wrong arity: " ++ name ++ "/" ++ show (length args))

-- JSON (de)serialization of the AST, shared verbatim with Julia/JS -----

exprToJson :: Expr -> JValue
exprToJson (Num n) = jObject [("type", jString "num"), ("value", jNumber n)]
exprToJson (Var v) = jObject [("type", jString "var"), ("name", jString v)]
exprToJson (BinOp op a b) = jObject
  [ ("type", jString "binop"), ("op", jString op)
  , ("left", exprToJson a), ("right", exprToJson b) ]
exprToJson (UnOp op a) = jObject
  [ ("type", jString "unop"), ("op", jString op), ("expr", exprToJson a) ]
exprToJson (Call name args) = jObject
  [ ("type", jString "call"), ("name", jString name)
  , ("args", jArray (map exprToJson args)) ]
exprToJson (If c t e) = jObject
  [ ("type", jString "if"), ("cond", exprToJson c)
  , ("then", exprToJson t), ("else", exprToJson e) ]

exprFromJson :: JValue -> Either String Expr
exprFromJson v = do
  t <- note "missing 'type'" (jLookup "type" v >>= jGetString)
  case t of
    "num"  -> Num <$> note "missing 'value'" (jLookup "value" v >>= jGetDouble)
    "var"  -> Var <$> note "missing 'name'" (jLookup "name" v >>= jGetString)
    "binop" -> BinOp
      <$> note "missing 'op'" (jLookup "op" v >>= jGetString)
      <*> (note "missing 'left'" (jLookup "left" v) >>= exprFromJson)
      <*> (note "missing 'right'" (jLookup "right" v) >>= exprFromJson)
    "unop" -> UnOp
      <$> note "missing 'op'" (jLookup "op" v >>= jGetString)
      <*> (note "missing 'expr'" (jLookup "expr" v) >>= exprFromJson)
    "call" -> do
      name <- note "missing 'name'" (jLookup "name" v >>= jGetString)
      argsJ <- note "missing 'args'" (jLookup "args" v >>= jGetArray)
      args <- mapM exprFromJson argsJ
      Right (Call name args)
    "if" -> If
      <$> (note "missing 'cond'" (jLookup "cond" v) >>= exprFromJson)
      <*> (note "missing 'then'" (jLookup "then" v) >>= exprFromJson)
      <*> (note "missing 'else'" (jLookup "else" v) >>= exprFromJson)
    other -> Left ("Unknown AST node type: " ++ other)
  where
    note msg Nothing  = Left msg
    note _   (Just x) = Right x
