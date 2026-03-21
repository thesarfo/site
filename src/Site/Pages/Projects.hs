-- | The projects page.
module Site.Pages.Projects
  ( projectsPage
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Site.Colors
import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

projectsPage :: [Project] -> Html
projectsPage projects =
  page defaultPage {pgTitle = "Made", pgDescription = "A selection of software projects across libraries, infrastructure, and systems.", pgPath = "/projects"} $
    pageSection $ do
      H.h1 ! A.class_ "page-title tight fade" $ "Made"
      H.p ! A.class_ "muted fade" ! A.style "font-size:.875rem;margin-bottom:3rem" $ "Things I built for learning or to solve a personal problem."
      H.div ! A.class_ "projects fade d2" $ mapM_ project projects

project :: Project -> Html
project p =
  H.article ! A.class_ "project" $ do
    H.div ! A.class_ "project-head" $ do
      H.a ! ext (projHref p) ! A.class_ "project-name" $ t (projName p)
      H.span ! A.class_ "project-year" $ t (projYear p)
      mapM_ (shotChip (projName p)) (projShots p)
      case projStatus p of
        Just "in-progress" -> H.span ! A.class_ "status progress" $ H.i mempty >> "In Progress"
        Just "failed" -> H.span ! A.class_ "status failed" $ H.i mempty >> "Failed"
        _ -> mempty
    H.div ! A.class_ "tags" $
      mapM_
        ( \tg ->
            H.span
              ! A.class_ "tag-chip"
              ! A.style (v ("background-color:" <> tagBackground tg <> ";color:" <> tagColor tg))
              $ t tg
        )
        (projTags p)
    H.div ! A.class_ "writeup" $ mapM_ (H.p . t) (projWriteup p)
    H.div ! A.class_ "project-links" $ do
      H.a ! ext (projHref p) $ t (hostLabel (projHref p))
      mapM_ (\l -> H.a ! ext (linkHref l) $ t (linkLabel l)) (fromMaybe [] (projLinks p))
  where
    hostLabel h
      | "github.com" `T.isInfixOf` h = "GitHub"
      | "testflight.apple.com" `T.isInfixOf` h = "TestFlight"
      | otherwise = "Website"

shotChip :: Text -> [Shot] -> Html
shotChip name shots = do
  H.span ! A.class_ "shots" $
    mapM_ anchor (zip [0 :: Int ..] shots)
  H.span ! A.class_ "shots-count" $ t (count (length shots))
  where
    group = "shots-" <> T.toLower name
    count 1 = "1 shot"
    count n = T.pack (show n) <> " shots"
    anchor (_, sh) =
      H.a
        ! A.href (v (shotSrc sh))
        ! attr "data-lightbox" group
        ! attr "data-caption" (shotCaption sh)
        ! attr "aria-label" ("View " <> count (length shots) <> " of " <> name)
        $ H.img ! A.src (v (shotThumb sh)) ! A.alt "" ! A.width "36" ! A.height "24" ! attr "loading" "lazy"
