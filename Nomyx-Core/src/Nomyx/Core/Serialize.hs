{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module Nomyx.Core.Serialize where

import           Prelude                             hiding (log, (.))
import           Control.Category
import           Control.Lens                        hiding ((.=))
import           Control.Monad.State
import           Data.Yaml                           (decodeEither, encode)
import           Data.List
import qualified Data.ByteString.Char8            as BL
import           Language.Haskell.Interpreter.Server
import           Nomyx.Core.Engine
import           Nomyx.Core.Interpret
import           Nomyx.Core.Types
import           Nomyx.Core.Utils
import           Nomyx.Language
import           System.FilePath

save :: Multi -> IO ()
save m = BL.writeFile (getSaveFile $ _mSettings m) (encode m)

save' :: StateT Multi IO ()
save' = get >>= lift . save

load :: FilePath -> IO Multi
load fp = do
   s <- BL.readFile fp
   case decodeEither s of
      Left e -> error $ "error decoding save file: " ++ e
      Right a -> return a

loadMulti :: Settings -> IO Multi
loadMulti s = do
   let sd = getSaveFile s
   m <- load sd
   gs' <- mapM (updateGameInfo interpretRule') $ _gameInfos m
   let m' = set gameInfos gs' m
   let m'' = set mSettings s m'
   return m''

updateGameInfo :: InterpretRule -> GameInfo -> IO GameInfo
updateGameInfo f gi = do
   gi' <- updateLoggedGame f (_loggedGame gi)
   return $ gi {_loggedGame = gi'}

updateLoggedGame :: InterpretRule -> LoggedGame -> IO LoggedGame
updateLoggedGame f (LoggedGame g log) = getLoggedGame g f log

-- read a library file
readLibrary :: FilePath -> IO Library
readLibrary yamlFile = do
   let dir = takeDirectory yamlFile
   ts <- readTemplates yamlFile
   let mods = nub $ join [ms | (RuleTemplate _ _ _ _ _ _ ms) <- ts]
   ms <- mapM (readModule dir) mods
   return $ Library ts ms

readTemplates :: FilePath -> IO [RuleTemplate]
readTemplates yamlFile = do
  s <- BL.readFile yamlFile
  case decodeEither s of
     Left e -> error $ "error decoding library: " ++ e
     Right ts -> return ts

readModule :: FilePath -> FilePath -> IO ModuleInfo
readModule basePath mod = do
  let absPath = basePath </> mod
  content <- readFile absPath
  return $ ModuleInfo mod content

