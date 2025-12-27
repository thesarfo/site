-- | The photo gallery page.
module Site.Pages.Lens
  ( lensPage
  ) where

import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

lensPage :: Html
lensPage =
  page defaultPage {pgTitle = "Lens", pgDescription = "Moments from side quests.", pgPath = "/lens"} $
    pageSection $ do
      title1 "Lens"
      ledeP "Moments from side quests."
      H.div ! A.id "lens" ! A.class_ "gallery col fade d2" $ do
        H.div ! A.class_ "skeleton" $ mempty
        H.div ! A.class_ "skeleton" $ mempty
        H.div ! A.class_ "skeleton" $ mempty
      H.noscript $ H.p ! A.class_ "coming" $ "Turn on JavaScript to see the photos."
