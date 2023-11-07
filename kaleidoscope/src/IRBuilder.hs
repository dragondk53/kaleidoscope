{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecursiveDo #-}

module IRBuilder where

import Data.ByteString.Short
import Debug.Trace
import JIT
import LLVM.AST as AST hiding (function)
import qualified LLVM.AST.Type as ASTType
import qualified LLVM.AST.Constant as C
import qualified LLVM.AST.Float as F
import qualified LLVM.AST.IntegerPredicate as P
import qualified LLVM.AST.ParameterAttribute as PA
import LLVM.IRBuilder.Constant as Con
import LLVM.IRBuilder.Instruction
import LLVM.IRBuilder.Module
import LLVM.IRBuilder.Monad
import Control.Monad (liftM)
import LLVM.AST.Constant (Constant(GlobalReference))
import Data.String
import Data.Maybe
import qualified Data.Map.Strict as M
-- import Control.Monad.RWS (MonadTrans, MonadState (state, get), MonadReader (local))
import Control.Monad.State.Strict
import Control.Monad.State.Class
import LLVM.AST.FloatingPointPredicate (FloatingPointPredicate(ULT, UGT, UEQ, UNE, ULE, UGE, ONE))
import Syntax as S

-- Syntax
-- data Expr
--   = Float Double
--   | Let Name Expr Expr
--   | Var Name
--   | Call Name [Expr]
--   | Function Name [ParameterName] Expr
--   | Extern Name [Name]
--   | UnaryOp ShortByteString Expr
--   | BinOp ShortByteString Expr Expr
--   | If Expr Expr Expr
--   deriving stock (Eq, Ord, Show)

-- Generates the Module from the previous module and the new expressions
-- Has to optimize the module
-- Has to execute the module
-- Has to update the module state
genModule :: [Expr] -> IO Module
genModule expressions = do
  res <- optimizeModule unoptimizedAst
  runJIT res
  return res
  where
    -- use old state and new expressions to generate the new state
    modlState = mapM genTopLevel expressions
    unoptimizedAst = buildModule "kaleidoscope" modlState

-- Generates functions, constants, externs, definitions and a main function otherwise
-- The result is a ModuleBuilder monad
genTopLevel :: Expr -> ModuleBuilder Operand

-- Function definition
genTopLevel (S.Function name args body) = do
  function name (map (\x -> (ASTType.double, x)) args) ASTType.double (genLevel body)
-- Extern definition
genTopLevel (S.Extern name args) = do
  extern name (map (const ASTType.double) args) ASTType.double
-- Unary operator definition
genTopLevel (S.UnaryDef name args body) = do
  function (Name ("unary_" <> name)) (map (\x -> (ASTType.double, x)) args) ASTType.double (genLevel body)
-- Binary operator definition
genTopLevel (S.BinaryDef name args body) = do
  function (Name ("binary_" <> name)) (map (\x -> (ASTType.double, x)) args) ASTType.double (genLevel body)
-- Any expression
genTopLevel expression = do
  function "main" [] ASTType.double (genLevel expression)

genLevel :: Expr -> [Operand] -> IRBuilderT ModuleBuilder ()
genLevel e localVars = genOperand e localVars >>= ret

-- Generates the Operands that codegenTop needs.
genOperand :: Expr -> [Operand] -> IRBuilderT ModuleBuilder Operand

-- Float
genOperand (Float n) _ = return $ ConstantOperand (C.Float (F.Double n))

-- Call
genOperand (S.Call fn args) localVars = do
  largs <- mapM (`genOperand` localVars) args 
  call (ConstantOperand (C.GlobalReference (ASTType.ptr (FunctionType ASTType.double (map (const ASTType.double) args) False)) fn)) (map (\x -> (x, [])) largs)

-- Unary Operands
genOperand (UnaryOp oper a) localVars = do
  op <- genOperand a localVars
  case M.lookup oper unops of
    Just f -> f op
    Nothing -> error "This shouldn't have matched here, unary operand doesn't exist."
  where
    unops :: M.Map ShortByteString (Operand -> IRBuilderT ModuleBuilder Operand)
    unops =
      M.fromList
        [ ("-", fneg) ]

-- Binary Operands
genOperand (BinOp oper a b) localVars = do
  opA <- genOperand a localVars
  opB <- genOperand b localVars
  case M.lookup oper binops of
    Just f -> f opA opB
    Nothing -> genOperand (S.Call (Name ("binary_" <> oper)) [a, b]) localVars
  where
    binops :: M.Map ShortByteString (Operand -> Operand -> IRBuilderT ModuleBuilder Operand)
    binops =
      M.fromList
        [ ("+", fadd),
          ("-", fsub),
          ("*", fmul),
          ("/", fdiv),
          ("<", fcmp ULT),
          (">", fcmp UGT),
          ("==", fcmp UEQ),
          ("!=", fcmp UNE),
          ("<=", fcmp ULE),
          (">=", fcmp UGE)
          ]
  
-- If
genOperand (If cond thenExpr elseExpr) localVars = mdo
  computedCond <- genOperand cond localVars
  -- test <- fcmp ONE computedCond (ConstantOperand (C.Float (F.Double 0.0)))
  condBr computedCond ifThen ifElse
  ifThen <- block `named` "if.then"
  computedThen <- genOperand thenExpr localVars
  br ifExit
  ifElse <- block `named` "if.else"
  computedElse <- genOperand elseExpr localVars
  br ifExit
  ifExit <- block `named` "if.exit"
  phi [(computedThen, ifThen), (computedElse, ifElse)]

-- Let in
genOperand (Let (Name varName) value body) localVars = do
  var <- alloca ASTType.double Nothing 0
  computedValue <- genOperand value localVars
  store var 0 computedValue
  genOperand body (var : localVars)

-- Variables
genOperand (Var (Name n)) localVars = do
  return $ LocalReference ASTType.double (Name $ n <> "_0") 

-- genOperand (Var (Name n)) localVars = do
--   s <- get 
--   let
--     usedNames = builderUsedNames s
--     nameCount = fromMaybe 0 $ M.lookup n usedNames
--     usedName = n <> fromString ("_" <> show (nameCount - 1))
--   case getLocalVar usedName localVars of
--     Just x -> return x
--     Nothing -> return $ ConstantOperand (GlobalReference (ASTType.ptr ASTType.double) (Name n))
--   where
--     getLocalVar :: ShortByteString -> [Operand] -> Maybe Operand
--     getLocalVar n vars = case filter (\(LocalReference _ (Name name)) -> name == n) vars of
--       x:xs -> Just x
--       _ -> Nothing

genOperand x _ = error $ "This shouldn't have matched here: " <> show x