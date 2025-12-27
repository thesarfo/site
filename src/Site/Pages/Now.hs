-- | The now page.
module Site.Pages.Now
  ( nowPage
  ) where

import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

nowPage :: Html
nowPage =
  page defaultPage {pgTitle = "Now", pgDescription = "What I'm currently focused on, updated occasionally.", pgPath = "/now", pgNav = Just "/now"} $
    pageSection $ do
      title1 "Now"
      H.p ! A.class_ "lede after fade d1" $ do
        "What I'm currently focused on, updated occasionally."
        H.br
        H.span ! A.style "font-size:.875rem;font-style:italic" $ "Last updated: July 2026"
      H.div ! A.class_ "lede fade d2" ! A.style "display:flex;flex-direction:column;gap:3rem" $ do
        H.p "I haven't been particularly interested in or doing much of anything lately."
        H.div $ do
          H.h2 ! A.style "font-size:1.25rem;font-weight:600;margin-bottom:1rem;color:hsl(var(--foreground))" $ "Other"
          H.p $ do
            "I work on "
            H.a ! A.href "/projects" ! A.class_ "ulink" $ "other stuff"
            ", read "
            H.a ! A.href "/papers" ! A.class_ "ulink" $ "papers"
            " and make "
            H.a ! A.href "/books" ! A.class_ "ulink" $ "book notes"
            " when I have time."
