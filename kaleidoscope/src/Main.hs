module Main where

import ParserH
import Codegen
import Emit
import StringUtils

import Control.Monad.Trans

import System.IO
import System.Environment
import System.Console.Haskeline

import qualified LLVM.AST as AST


-- import Foreign
-- import Foreign.C


-- foreign import ccall unsafe "putchard.h putchard" cPutchard :: Double -> IO ()
-- putchard :: Double -> IO ()
-- putchard = do cPutchard


initModule :: AST.Module
initModule = emptyModule $ stringToShortByteString "Kaleidoscope"

process :: AST.Module -> String -> IO (Maybe AST.Module)
process modo source = do
  let res = parseToplevel source
  case res of
    Left err -> print err >> return Nothing
    Right ex -> do
      ast <- codegen modo ex
      return $ Just ast

processFile :: String -> IO (Maybe AST.Module)
processFile fname = readFile fname >>= process initModule

repl :: IO ()
repl = runInputT defaultSettings (loop initModule)
  where
  loop mod = do
    minput <- getInputLine "ready> "
    case minput of
      Nothing -> outputStrLn "Goodbye."
      Just input -> do
        modn <- liftIO $ process mod input
        case modn of
          Just modn -> loop modn
          Nothing -> loop mod

main :: IO ()
main = do
  -- putchard 120
  -- putchard 120
  -- putchard 120
  -- putchard 120
  -- putchard 120
  -- putchard 120
  -- putchard 120
  -- putchard 120
  -- putchard 120
  -- putchard 120
  args <- getArgs
  case args of
    []      -> repl
    [fname] -> processFile fname >> return ()


-- Imprimir el AST (chapter 2)
printAST :: String -> IO ()
printAST line = do
  let res = parseToplevel line
  case res of
    Left err -> print err
    Right ex -> mapM_ print ex





-- module Main where

-- import ParserH

-- import Control.Monad.Trans
-- import System.Console.Haskeline

-- process :: String -> IO ()
-- process line = do
--   let res = parseToplevel line
--   case res of
--     Left err -> print err
--     Right ex -> mapM_ print ex

-- main :: IO ()
-- main = runInputT defaultSettings loop
--   where
--     loop = do
--       minput <- getInputLine "ready> "
--       case minput of
--         Nothing -> outputStrLn "Goodbye."
--         Just input -> liftIO (process input) >> loop
