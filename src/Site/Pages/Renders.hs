-- | The Blender renders page.
module Site.Pages.Renders
  ( rendersPage
  ) where

import qualified Data.Text as T
import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

rendersPage :: [Render] -> Html
rendersPage renders =
  page defaultPage {pgTitle = "Renders", pgDescription = "3D renders made in Blender.", pgPath = "/renders"} $
    pageSection $ do
      title1 "Renders"
      if null renders
        then H.p ! A.class_ "coming" $ "Coming soon 🙂"
        else H.div ! A.class_ "gallery grid2 fade d2" $ mapM_ tile (zip [0 :: Int ..] renders)
  where
    tile (i, r) =
      H.a ! A.href (v ("/renders/" <> renderFile r)) ! attr "data-lightbox" "renders" ! attr "data-caption" (renderTitle r) ! attr "aria-label" ("View " <> renderTitle r) $
        H.img
          ! A.src (v ("/renders/" <> renderFile r))
          ! A.alt (v (renderTitle r))
          ! A.width (v (T.pack (show (renderWidth r))))
          ! A.height (v (T.pack (show (renderHeight r))))
          ! attr "loading" (if i < 2 then "eager" else "lazy")
