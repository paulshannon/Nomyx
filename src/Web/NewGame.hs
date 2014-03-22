{-# LANGUAGE ExtendedDefaultRules #-}
{-# LANGUAGE OverloadedStrings #-}

module Web.NewGame where

import Prelude hiding (div)
import Text.Reform
import Text.Blaze.Html5.Attributes hiding (label)
import Text.Reform.Blaze.String as RB hiding (form)
import qualified Text.Reform.Blaze.Common as RBC
import Text.Reform.Happstack()
import Control.Applicative
import Types
import Happstack.Server
import Text.Reform.Happstack
import Web.Common
import Control.Monad.State
import Language.Nomyx.Engine
import Web.Routes.RouteT
import Control.Concurrent.STM
import Data.Text(Text)
import Text.Blaze.Internal(string)
import Session
default (Integer, Double, Data.Text.Text)


data NewGameForm = NewGameForm GameName GameDesc Bool

newGameForm :: Bool -> NomyxForm NewGameForm
newGameForm admin = pure NewGameForm <*> (br ++> errorList ++> label "Enter new game name: " ++> (RB.inputText "") `transformEither` (fieldRequired GameNameRequired) `RBC.setAttr` placeholder "Game name"  <++ br <++ br)
                               <*> newGameDesc
                               <*> if admin then label "Public game? " ++> (RB.inputCheckbox True) else pure False

newGameDesc :: NomyxForm GameDesc
newGameDesc = pure GameDesc <*> label "Enter game description:" ++> br ++> (textarea 40 3 "") `RBC.setAttr` placeholder "Enter game description" `RBC.setAttr` class_ "gameDesc" <++ br <++ br
                            <*> label "Enter a link to an agora (e.g. a forum, a mailing list...) where the players can discuss their rules: " ++> br ++> (RB.inputText "") `RBC.setAttr` placeholder "Agora URL (including http://...)" `RBC.setAttr` class_ "agora" <++ br <++ br

gameNameRequired :: String -> Either NomyxError String
gameNameRequired = fieldRequired GameNameRequired

newGamePage :: (TVar Session) -> RoutedNomyxServer Response
newGamePage ts = toResponse <$> do
   admin <- getIsAdmin ts
   newGameLink <- showURL SubmitNewGame
   mf <- lift $ viewForm "user" $ newGameForm admin
   mainPage "New game"
            "New game"
            (blazeForm mf newGameLink)
            False
            True

newGamePost :: (TVar Session) -> RoutedNomyxServer Response
newGamePost ts = toResponse <$> do
   methodM POST
   r <- liftRouteT $ eitherForm environment "user" (newGameForm False)
   link <- showURL MainPage
   newGameLink <- showURL SubmitNewGame
   pn <- getPlayerNumber ts
   case r of
      Left errorForm -> mainPage  "New game" "New game" (blazeForm errorForm newGameLink) False True
      Right (NewGameForm name desc isPublic) -> do
         webCommand ts $ newGame name desc pn isPublic
         seeOther link $ string "Redirecting..."
