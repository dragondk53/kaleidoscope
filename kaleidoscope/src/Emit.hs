{-# LANGUAGE OverloadedStrings #-}

module Emit where

import Codegen
import Control.Monad.Except
import Data.ByteString.Short
import qualified Data.Map as Map
import Data.String
import JIT
import qualified LLVM.AST as AST
import qualified LLVM.AST.Constant as C
import qualified LLVM.AST.Float as F
import qualified LLVM.AST.FloatingPointPredicate as FP
import qualified Syntax as S

toSig :: [ShortByteString] -> [(AST.Type, AST.Name)]
toSig = map (\x -> (double, AST.Name x))

codegenTop :: S.Expr -> LLVM ()
codegenTop (S.Function name arguments body) = do
  define double (fromString name) fnargs bls
  where
    fnargs = toSig (map fromString arguments)
    bls = createBlocks $
      execCodegen $ do
        entryBlk <- addBlock entryBlockName
        _ <- setBlock entryBlk
        forM_ arguments $ \a -> do
          var <- alloca double
          store var (local (AST.Name $ fromString a))
          assign (fromString a) var
        cgen body >>= ret
codegenTop (S.Extern name arguments) = do
  external double (fromString name) fnargs
  where
    fnargs = toSig $ map fromString arguments
codegenTop expression = do
  define double "main" [] blks
  where
    blks = createBlocks $
      execCodegen $ do
        entryBlk <- addBlock entryBlockName
        _ <- setBlock entryBlk
        cgen expression >>= ret

-------------------------------------------------------------------------------
-- Operations
-------------------------------------------------------------------------------

lt :: AST.Operand -> AST.Operand -> Codegen AST.Operand
lt a b = do
  test <- fcmp FP.ULT a b
  uitofp double test

binops :: Map.Map String (AST.Operand -> AST.Operand -> Codegen AST.Operand)
binops =
  Map.fromList
    [ ("+", fadd),
      ("-", fsub),
      ("*", fmul),
      ("/", fdiv),
      ("<", lt)
    ]

cgen :: S.Expr -> Codegen AST.Operand
cgen (S.UnaryOp op a) = do
  cgen $ S.Call ("unary" ++ op) [a]
cgen (S.BinOp "=" (S.Var var) val) = do
  a <- getvar (fromString var)
  cval <- cgen val
  store a cval
  return cval
cgen (S.BinOp op a b) = do
  case Map.lookup op binops of
    Just f -> do
      ca <- cgen a
      cb <- cgen b
      f ca cb
    Nothing -> error "No such operator"
cgen (S.Var x) = getvar (fromString x) >>= load
cgen (S.Float n) = return $ cons $ C.Float (F.Double n)
cgen (S.Call fn args) = do
  largs <- mapM cgen args
  call (externf (AST.Name $ fromString fn) largs) largs
cgen _ = error "This shouldn't have matched here :thinking_emoji"

-------------------------------------------------------------------------------
-- Compilation
-------------------------------------------------------------------------------

liftError :: ExceptT String IO a -> IO a
liftError = runExceptT >=> either fail return

-- codegen :: AST.Module -> [S.Expr] -> IO AST.Module
-- codegen mod fns = withContext $ \context ->
--   -- liftError $ withModuleFromAST context newast $ \m -> do
--   withModuleFromAST context newast $ \m -> do
--     llstr <- moduleLLVMAssembly m
--     putStrLn $ StringUtils.byteStringToString llstr
--     return newast
--   where
--     modn    = trace ("modn. fns= " ++ show fns) (mapM codegenTop fns)
--     newast  = runLLVM mod modn

codegen :: AST.Module -> [S.Expr] -> IO AST.Module
codegen modl fns = do
  res <- runJIT oldAst
  return res
  where
    modlName = mapM codegenTop fns
    oldAst = runLLVM modl modlName
