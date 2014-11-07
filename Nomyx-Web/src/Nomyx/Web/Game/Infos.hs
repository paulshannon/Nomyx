{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ExtendedDefaultRules #-}

module Nomyx.Web.Game.Infos where

import Prelude hiding (div)
import Control.Monad
import Control.Monad.State
import Control.Concurrent.STM
import Control.Applicative
import Data.Monoid
import Data.Maybe
import Data.String
import Data.List
import Data.List.Split
import Data.Text (Text)
import Language.Nomyx
import Text.Blaze.Html5                    (Html, div, (!), p, table, td, tr, h2, h3, h4, pre, toValue, br, a)
import Text.Blaze.Html5.Attributes as A    (id, class_, href)
import Text.Reform.Blaze.String            (inputHidden)
import Text.Reform                         (viewForm, eitherForm)
import Text.Reform.Happstack               (environment)
import Happstack.Server                    (Response, Method(..), seeOther, toResponse, methodM, ok)
import Web.Routes.RouteT                   (showURL, liftRouteT)
import Nomyx.Web.Common as NWC
import Nomyx.Core.Types as T
import Nomyx.Core.Engine
import Nomyx.Core.Session as S
import Nomyx.Core.Profile as Profile
default (Integer, Double, Data.Text.Text)

viewGameDesc :: Game -> Maybe PlayerNumber -> Bool -> RoutedNomyxServer Html
viewGameDesc g playAs gameAdmin = do
   vp <- viewPlayers (_players g) (_gameName g) gameAdmin
   ok $ do
      p $ do
        h3 $ fromString $ "Viewing game: " ++ _gameName g
        when (isJust playAs) $ h4 $ fromString $ "You are playing as player " ++ (show $ fromJust playAs)
      p $ pre $ fromString (_desc $ _gameDesc g)
      p $ h4 $ "This game is discussed in the " >> a "Agora" ! (A.href $ toValue (_agora $ _gameDesc g)) >> "."
      p $ h4 "Players in game:"
      when gameAdmin "(click on a player name to \"play as\" this player)"
      vp
      p $ viewVictory g

viewPlayers :: [PlayerInfo] -> GameName -> Bool -> RoutedNomyxServer Html
viewPlayers pis gn gameAdmin = do
   let plChunks = transpose $ chunksOf 15 (sort pis)
   vp <- mapM mkRow plChunks
   ok $ table $ mconcat vp
   where mkRow :: [PlayerInfo] -> RoutedNomyxServer Html
         mkRow row = do
         r <- mapM (viewPlayer gn gameAdmin) row
         ok $ tr $ mconcat r

viewPlayer :: GameName -> Bool -> PlayerInfo -> RoutedNomyxServer Html
viewPlayer gn gameAdmin (PlayerInfo pn name _) = do
   pad <- playAsDiv pn gn
   let inf = fromString name
   ok $ do
    pad
    td $ div ! A.id "playerNumber" $ fromString $ show pn
    td $ div ! A.id "playerName" $ if gameAdmin
       then a inf ! (href $ toValue $ "#openModalPlayAs" ++ show pn)
       else inf

playAsDiv :: PlayerNumber -> GameName -> RoutedNomyxServer Html
playAsDiv pn gn = do
   submitPlayAs <- showURL $ SubmitPlayAs gn
   main  <- showURL MainPage
   paf <- lift $ viewForm "user" $ playAsForm $ Just pn
   ok $ do
      let cancel = a "Cancel" ! (href $ toValue main) ! A.class_ "modalButton"
      div ! A.id (toValue $ "openModalPlayAs" ++ show pn) ! A.class_ "modalWindow" $ do
         div $ do
            h2 $ fromString $ "When you are in a private game, you can play instead of any players. This allows you to test " ++
               "the result of their actions."
            blazeForm (h2 (fromString $ "Play as player " ++ show pn ++ "?  ") >> paf) submitPlayAs
            br
            cancel

playAsForm :: Maybe PlayerNumber -> NomyxForm String
playAsForm pn = inputHidden (show pn)

viewVictory :: Game -> Html
viewVictory g = do
    let vs = _playerName <$> mapMaybe (Profile.getPlayerInfo g) (getVictorious g)
    case vs of
        []   -> br
        a:[] -> h3 $ fromString $ "Player " ++ show a ++ " won the game!"
        a:bs -> h3 $ fromString $ "Players " ++ intercalate ", " bs ++ " and " ++ a ++ " won the game!"

newPlayAs :: GameName -> TVar Session -> RoutedNomyxServer Response
newPlayAs gn ts = toResponse <$> do
   methodM POST
   p <- liftRouteT $ eitherForm environment "user" $ playAsForm Nothing
   pn <- fromJust <$> getPlayerNumber ts
   case p of
      Right playAs -> do
         webCommand ts $ S.playAs (read playAs) pn gn
         link <- showURL MainPage
         seeOther link "Redirecting..."
      (Left errorForm) -> do
         settingsLink <- showURL $ SubmitPlayAs gn
         mainPage  "Admin settings" "Admin settings" (blazeForm errorForm settingsLink) False True
