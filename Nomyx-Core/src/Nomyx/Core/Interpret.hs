{-# LANGUAGE DoAndIfThenElse     #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | This module starts a Interpreter server that will read our strings representing rules to convert them to plain Rules.
module Nomyx.Core.Interpret where

import           Control.Exception                   as CE
import           Control.Monad
import           Data.List
import           Language.Haskell.Interpreter
import           Language.Haskell.Interpreter.Server
import           Language.Haskell.Interpreter.Unsafe (unsafeSetGhcOption)
import           Language.Nomyx
import           Nomyx.Core.Context
import           Nomyx.Core.Utils
import           System.FilePath                     (dropExtension, joinPath,
                                                      takeFileName, dropFileName,
                                                      splitDirectories, takeBaseName, (</>))
import           System.IO.Error
import           System.IO.Temp
import           System.Directory

exts :: [String]
exts = ["Safe", "GADTs"] ++ map show namedExts

namedExts :: [Extension]
namedExts = [GADTs,
             ScopedTypeVariables,
             TypeFamilies,
             DeriveDataTypeable]

-- | initializes the interpreter by loading some modules.
initializeInterpreter :: [ModuleInfo] -> Interpreter ()
initializeInterpreter mods = do
   reset
   -- Interpreter options
   set [installedModulesInScope := False,
        languageExtensions := map readExt exts]
   -- GHC options
   unsafeSetGhcOption "-w"
   unsafeSetGhcOption "-fpackage-trust"
   forM_ (defaultPackages >>= words) $ \pkg -> unsafeSetGhcOption ("-trust " ++ pkg)
   -- Modules
   when (not $ null mods) $ do
      dir <- liftIO $ createTempDirectory "/tmp" "Nomyx"
      modPaths <- liftIO $ mapM (copyModule dir) mods
      let modNames = map (getModName . _modPath) mods
      liftIO $ putStrLn $ "Loading modules: " ++ (intercalate ", " modPaths)
      liftIO $ putStrLn $ "module names: " ++ (intercalate ", " modNames)
      loadModules modPaths
      setTopLevelModules modNames
   -- Imports
   let importMods = qualImports ++ zip (unQualImports) (repeat Nothing)
   setImportsQ importMods

getModName :: FilePath -> String
getModName fp = intercalate "." $ (filter (/= ".") $ splitDirectories $ dropFileName fp) ++ [takeBaseName fp]

---- | reads a Rule out of a string.
interpretRule :: RuleCode -> [ModuleInfo] -> IO (Either InterpreterError Rule)
interpretRule rc ms = protectHandlers $ runInterpreter $ do
   initializeInterpreter ms
   --case res of
   --   Left e -> return $ Left e
   --   Right _ -> do
   let runRule = interpret rc (as :: Rule)
   -- let handler (e::IOException) = return $ Left $ NotAllowed $ "Caught exception: " ++ (show e)
   runRule -- `catchIOError` handler

interRule :: RuleCode -> [ModuleInfo] -> IO Rule
interRule rc ms = do
   res <- interpretRule rc ms
   case res of
      Right rf -> return rf
      Left e -> error $ show e

--TODO handle error cases
copyModule :: FilePath -> ModuleInfo -> IO (FilePath)
copyModule saveDir mod = do
   let dest = saveDir </> (_modPath mod)
   createDirectoryIfMissing True $ dropFileName dest
   writeFile dest (_modContent mod)
   return dest

showInterpreterError :: InterpreterError -> String
showInterpreterError (UnknownError s)  = "Unknown Error\n" ++ s
showInterpreterError (WontCompile ers) = "Won't Compile\n" ++ concatMap (\(GhcError errMsg) -> errMsg ++ "\n") ers
showInterpreterError (NotAllowed s)    = "Not Allowed (Probable cause: bad module or file name)\n" ++ s
showInterpreterError (GhcException s)  = "Ghc Exception\n" ++ s

readExt :: String -> Extension
readExt s = case reads s of
  [(e,[])] -> e
  _        -> UnknownExtension s
