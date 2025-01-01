-- | Helpers shared by the page modules.
module Site.Pages.Common
  ( s
  , t
  , v
  , ext
  , attr
  , pageSection
  , title1
  , ledeP
  , postHref
  , pager
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

s :: String -> Html
s = H.toHtml

t :: Text -> Html
t = H.toHtml

v :: Text -> H.AttributeValue
v = H.toValue

ext :: Text -> H.Attribute
ext url = A.href (v url) <> A.target "_blank" <> A.rel "noopener noreferrer"

attr :: Text -> Text -> H.Attribute
attr k val = H.customAttribute (H.stringTag (T.unpack k)) (v val)

pageSection :: Html -> Html
pageSection = H.section ! A.class_ "page"

title1 :: Text -> Html
title1 name = H.h1 ! A.class_ "page-title fade" $ t name

ledeP :: Text -> Html
ledeP body = H.div ! A.class_ "lede after fade d1" $ H.p (t body)

postHref :: String -> Text
postHref slug = "/writing/" <> T.pack slug

pager :: Text -> Int -> Int -> Html
pager base cur total
  | total <= 1 = mempty
  | otherwise = H.nav ! A.class_ "pager fade d4" ! attr "aria-label" "Pages" $ do
      if cur > 1 then H.a ! A.href (v (pageUrl (cur - 1))) $ "← Previous" else H.span ! A.class_ "off" $ "← Previous"
      mapM_ num [1 .. total]
      if cur < total then H.a ! A.href (v (pageUrl (cur + 1))) $ "Next →" else H.span ! A.class_ "off" $ "Next →"
  where
    pageUrl 1 = base
    pageUrl n = base <> "/page/" <> T.pack (show n)
    num n
      | n == cur = H.span ! A.class_ "num here" ! attr "aria-current" "page" $ s (show n)
      | otherwise = H.a ! A.class_ "num" ! A.href (v (pageUrl n)) $ s (show n)
