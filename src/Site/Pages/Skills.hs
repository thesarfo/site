-- | The skills timeline page.
module Site.Pages.Skills
  ( skillsPage
  ) where

import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

skillsPage :: Html
skillsPage =
  page
    defaultPage {pgTitle = "Skills", pgDescription = "An interactive learning timeline.", pgPath = "/skills", pgHead = H.link ! A.rel "stylesheet" ! A.href "/skills-timeline.css"}
    $ pageSection $ do
      title1 "Skills"
      H.div ! A.class_ "fade d2" $ H.div ! A.id "skills-timeline" ! attr "data-src" "/data/skills.json" $ mempty
      H.script ! A.src "/skills-timeline.js" ! A.defer "" $ mempty
