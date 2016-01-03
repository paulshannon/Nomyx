{-# LANGUAGE DoAndIfThenElse      #-}
{-# LANGUAGE ExtendedDefaultRules #-}
{-# LANGUAGE OverloadedStrings    #-}

module Nomyx.Web.Game.Templates where

import           Control.Applicative
import           Control.Monad
import           Control.Monad.State
import           Data.Maybe
import           Data.String
import           Data.Text                   (Text, pack, unpack)
import           Data.Text.Encoding
import           Happstack.Server            (Method (..), Response, methodM,
                                              ok, seeOther, toResponse)
import           Language.Nomyx
import           Nomyx.Core.Engine
import           Nomyx.Core.Session          as S
import           Nomyx.Core.Types            as T
import           Nomyx.Web.Common            as NWC
import qualified Nomyx.Web.Help              as Help
import           Nomyx.Web.Types
import           Prelude                     hiding (div)
import           Text.Blaze.Html5            as H (Html, a, div, h2, h3, h4,
                                                   img, input, label, li, pre,
                                                   toValue, ul, (!), p)
import           Text.Blaze.Html5.Attributes as A (class_, disabled, for, href,
                                                   id, placeholder, src, type_,
                                                   value)
import           Text.Reform                 (eitherForm, viewForm, (++>),
                                              (<++))
import           Text.Reform.Blaze.Common    (setAttr)
import           Text.Reform.Blaze.String    (inputHidden, inputSubmit, label,
                                              textarea)
import qualified Text.Reform.Blaze.String    as RB
import           Text.Reform.Happstack       (environment)
import           Web.Routes.RouteT           (liftRouteT)
import           Happstack.Server            (ContentType)
default (Integer, Double, Data.Text.Text)


-- * Templates display

viewRuleTemplates :: [RuleTemplate] -> Maybe LastRule -> GameName -> RoutedNomyxServer Html
viewRuleTemplates rts mlr gn = do
  vrs <- mapM (viewRuleTemplate gn mlr) rts
  ok $ do
    div ! class_ "ruleList" $ ul $ viewRuleTemplateNames rts mlr
    div ! class_ "rules" $ sequence_ vrs

viewRuleTemplateNames :: [RuleTemplate] -> Maybe LastRule -> Html
viewRuleTemplateNames rts mlr = do
  let allRules = rts ++ [(maybe (RuleTemplate "New Rule" "" "" "" Nothing [] []) fst mlr)]
  mapM_  viewRuleTemplateName allRules


viewRuleTemplateName :: RuleTemplate -> Html
viewRuleTemplateName rt = do
  let name = fromString $ _rName $ rt
  li $ H.a name ! A.class_ "ruleName" ! (A.href $ toValue $ "?ruleName=" ++ (idEncode $ _rName rt))

viewRuleTemplate :: GameName -> Maybe LastRule -> RuleTemplate -> RoutedNomyxServer Html
viewRuleTemplate gn mlr rt = do
  let toEdit = case mlr of
       Nothing -> (rt, "")
       Just lr -> if ((_rName $ fst lr) == (_rName rt)) then lr else (rt, "")
  com <- commandRule gn rt
  view <- viewrule gn rt
  edit <- viewRuleTemplateEdit toEdit gn
  ok $ div ! A.class_ "rule" ! A.id (toValue $ idEncode $ _rName rt) $ do
    com
    view
    edit

commandRule :: GameName -> RuleTemplate -> RoutedNomyxServer Html
commandRule gn rt = do
  let delLink = showRelURL (DelRuleTemplate gn (_rName rt))
  let idrt = idEncode $ _rName rt
  ok $ div ! A.class_ "commandrule" $ do
    p $ H.a "view"   ! (A.href $ toValue $ "?ruleName=" ++ idrt)
    p $ H.a "edit"   ! (A.href $ toValue $ "?ruleName=" ++ idrt ++ "&edit")
    p $ H.a "delete" ! (A.href $ toValue delLink)

viewrule :: GameName -> RuleTemplate -> RoutedNomyxServer Html
viewrule gn rt = do
  lf  <- liftRouteT $ lift $ viewForm "user" (hiddenSubmitRuleTemplatForm (Just rt))
  ok $ div ! A.class_ "viewrule" $ do
    let pic = fromMaybe "/static/pictures/democracy.png" (_rPicture rt)
    h2 $ fromString $ _rName rt
    img ! (A.src $ toValue $ pic)
    h3 $ fromString $ _rDescription rt
    h2 $ fromString $ "authored by " ++ (_rAuthor rt)
    viewRuleFunc rt
    blazeForm lf $ showRelURL (SubmitRule gn)

hiddenSubmitRuleTemplatForm :: (Maybe RuleTemplate) -> NomyxForm String
hiddenSubmitRuleTemplatForm rt = inputHidden (show rt)

viewRuleFunc :: RuleTemplate -> Html
viewRuleFunc rd = do
 let code = lines $ _rRuleCode rd
 let codeCutLines = 7
 div ! A.id "codeDiv" $ displayCode $ unlines $ take codeCutLines code
 div $ when (length code >= codeCutLines) $ fromString "(...)"

-- * Templates submit

-- | Submit a template to a given game
submitRuleTemplatePost :: GameName -> RoutedNomyxServer Response
submitRuleTemplatePost gn = toResponse <$> do
   methodM POST
   s <- getSession
   let gi = getGameByName gn s
   admin <- isGameAdmin (fromJust gi)
   r <- liftRouteT $ lift $ eitherForm environment "user" (hiddenSubmitRuleTemplatForm Nothing)
   pn <- fromJust <$> getPlayerNumber
   case r of
      Right rt -> webCommand $ submitRule (fromJust $ read rt) pn gn (_sh s)
      Right rt -> webCommand $ adminSubmitRule (fromJust $ read rt) pn gn (_sh s)
      (Left _) -> liftIO $ putStrLn "cannot retrieve form data"
   seeOther (showRelURL $ Menu Actions gn) $ "Redirecting..."


-- * Template edit

-- Edit a template
viewRuleTemplateEdit :: LastRule -> GameName -> RoutedNomyxServer Html
viewRuleTemplateEdit lr gn = do
  lf  <- liftRouteT $ lift $ viewForm "user" (newRuleTemplateForm (Just $ fst lr) True)
  ok $ div ! A.class_ "editRule" $ do
    blazeForm lf $ showRelURL $ NewRuleTemplate gn
    fromString $ snd lr

newRuleTemplateForm :: Maybe RuleTemplate -> Bool -> NomyxForm (RuleTemplateForm, Maybe String)
newRuleTemplateForm sr isGameAdmin = newRuleTemplateForm' (fromMaybe (RuleTemplate "" "" "" "" Nothing [] []) sr) isGameAdmin

newRuleTemplateForm' :: RuleTemplate -> Bool -> NomyxForm (RuleTemplateForm, Maybe String)
newRuleTemplateForm' rt isGameAdmin =
  (,) <$> newRuleTemplateForm'' rt
      <*> inputSubmit "Check"
      -- <*> if isGameAdmin then inputSubmit "Admin submit" else pure Nothing

data RuleTemplateForm = RuleTemplateForm {name :: String, desc :: String, code :: String, decls :: (FilePath, FilePath)}

newRuleTemplateForm'' :: RuleTemplate -> NomyxForm RuleTemplateForm
newRuleTemplateForm'' (RuleTemplate name desc code aut pic cat decls) =
  RuleTemplateForm <$> RB.label "Name: " ++> RB.inputText name `setAttr` class_ "ruleName"
               <*> (RB.label "      Short description: " ++> (RB.inputText desc `setAttr` class_ "ruleDescr") <++ RB.br)
               <*> RB.label "      Code: " ++> textarea 80 15 code `setAttr` class_ "ruleCode" `setAttr` placeholder "Enter here your rule"
               <*> ((\(a,b,c) -> (a,b)) <$> RB.inputFile)

newRuleTemplate :: GameName -> RoutedNomyxServer Response
newRuleTemplate gn = toResponse <$> do
  methodM POST
  s <- getSession
  r <- liftRouteT $ lift $ eitherForm environment "user" (newRuleTemplateForm Nothing False)
  pn <- fromJust <$> getPlayerNumber
  ruleName <- case r of
     Right (RuleTemplateForm name desc code (tempName, fileName), Nothing) -> do
       content <- liftIO $ readFile tempName
       webCommand $ S.newRuleTemplate (RuleTemplate name desc code "" Nothing [] [(Module fileName content)]) pn (_sh s)
       return name
     Right (RuleTemplateForm name desc code (tempName, fileName), Just _)  -> do
       content <- liftIO $ readFile tempName
       webCommand $ S.checkRule (RuleTemplate name desc code "" Nothing [] [(Module fileName content)]) pn (_sh s)
       return name
     _ -> do
       liftIO $ putStrLn "cannot retrieve form data"
       return ""
  let link = showRelURLParams (Menu Library gn) [("ruleName", Just $ pack $ idEncode ruleName)]
  seeOther link $ "Redirecting..."


delRuleTemplate :: GameName -> RuleName -> RoutedNomyxServer Response
delRuleTemplate gn rn = do
  pn <- fromJust <$> getPlayerNumber
  webCommand $ S.delRuleTemplate gn rn pn
  seeOther (showRelURL $ Menu Library gn) $ toResponse "Redirecting..."