module Types where

import Syntax as S
import LLVM.AST as AST
import qualified LLVM.AST.Type as ASTType
import Data.ByteString.Short (ShortByteString)
import Data.List (find)

type LocalVarType = (Name, S.Type)

getExpressionType :: Expr -> [LocalVarType] -> AST.Type
getExpressionType (Int _) _ = ASTType.i32
getExpressionType (Float _) _ = ASTType.double
getExpressionType (Bool _) _ = ASTType.i1
getExpressionType (Constant Double _ _) _ = ASTType.double
getExpressionType (Constant Integer _ _) _ = ASTType.i32
getExpressionType (Constant Boolean _ _) _ = ASTType.i1
-- getExpressionType (S.Call _ _) = We can't infer this without context
getExpressionType (Var varName) localVars = getASTType $ findLocalVarType localVars varName
getExpressionType (UnaryOp _ _) _ = ASTType.double -- TODO!!
getExpressionType (BinOp _ a b) localVars = if getExpressionType a localVars == ASTType.double || getExpressionType b localVars == ASTType.double 
  then ASTType.double 
  else getExpressionType a localVars 
getExpressionType (Let _ _ _ e) localVars = getExpressionType e localVars
getExpressionType _ _ = ASTType.double


getASTType :: S.Type -> AST.Type
getASTType Double = ASTType.double
getASTType Integer = ASTType.i32
getASTType Boolean = ASTType.i1


findLocalVarType :: [LocalVarType] -> Name -> S.Type
findLocalVarType localVars varName = case find (\(n, _) -> n == varName) localVars of
  Just (var, t) -> t
  Nothing -> S.Double -- TODO!